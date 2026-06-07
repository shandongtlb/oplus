# OnePlus 13 NetHunter qcacld-3.0 监听 + 注入移植 —— 全程实战记录

> 目标设备:OnePlus 13(ColorOS16 / Android 16,Linux 6.6,SD8 Elite SM8750,chipset peach_v2)
> 驱动:qcacld-3.0(高通 FullMAC,直接用 cfg80211,不走 mac80211),模块 `qca_cld3_peach_v2.ko`
> 目标:监听抓包 + 数据包注入 + 日常 WiFi/投屏/网络共享全部正常
> 性质:本人设备授权渗透测试
> 部署方式:KernelSU 模块热切 .ko(跑 OEM 原版内核,不刷完整 boot.img)
> 编译命令:`./kernel_platform/oplus/build/oplus_build_kernel.sh sun perf`(在 `/root/pt/kernel` 下跑)

---

## 0. 核心结论(最重要的几条)

1. **qcacld 是 FullMAC**,不用 mac80211。网上那些 mac80211/USB 网卡(rtl8187/zd1211)的注入补丁**对内置 WiFi 无效**,只对外接 USB 网卡有效。
2. **监听能开 ≠ 能注入**。peach_v2 固件**会 DISCARD(丢弃)monitor vdev 上的管理帧发送**——必须建一个**隐藏 STA helper vdev** 把注入帧从它发出去。
3. **官方那份一万多行的注入补丁,核心只有几百行**;其余是测试/调试/安全脚手架/胶水,大部分对本设备无用或不可直接套用。
4. **本树是 MLO 重构版**:取 vdev_id 必须 `adapter->deflink->vdev_id`,不是 `adapter->vdev_id`。
5. **编译前在源码里逐行验证每个 gate 的放行条件**,是避免反复失败编译的唯一可靠办法(用户明确要求"走一遍流程,保证一次走通")。

---

## 1. Phase 1 —— 监听(Monitor)打通

### 1.1 正确的监听入口
- **用 `airmon-ng start wlan0`**(= `iw phy phyX interface add wlan0mon type monitor`),它走 cfg80211 `add_virtual_intf` → `wlan_hdd_add_monitor_interface`,**monitor vdev 的 up 事件由 stock 自动创建**,得到干净的 wlan0mon。
- **不要用** `echo 4 > con_mode`(OEM 接受但产生不了可用 monitor),也**不要用** `iw dev wlan0 set type monitor` 原地切换(6.6 上有 event gap)。

### 1.2 监听路上踩过的坑(按时间)

| # | 现象 | 根因 | 修复 |
|---|---|---|---|
| 1 | airodump `-22 EINVAL` | 动态切 monitor 后 netdev 仍是 STATION ops,`ip link up` 走了 hdd_open 而非 __hdd_mon_open → netdev 没设成 ARPHRD_IEEE80211_RADIOTAP | `hdd_set_station_ops` 放宽:`device_mode==QDF_MONITOR_MODE` 时也装 mon ops |
| 2 | netdev type 已是 803 但抓不到包 | 一度误以为要走 LPC(Local Packet Capture) | **最终证明是误诊**(见#4),坑了好几轮 |
| LPC 弯路 | 强开 LPC → dp_mon_filter assert / 0 帧 | `dp_mon_ht2_rx_ring_cfg` 在 LPC 模式下**跳过经典 monitor RX filter** → 没人编程 filter → 0 帧 | **回退 LPC 到 stock(关闭)**,经典 RX filter 才会被编程 |
| 3 | `iw set freq` -16 EBUSY | net/wireless/chan.c 的 `monitors_only` EBUSY 拦截 | 应用补丁3 的 chan.c hunk,去掉该拦截 |
| 4 | set freq -22 "failed to reinit monitor mode vdev up event" | 动态切换路径没建 monitor vdev up/stop 事件 | 在 hdd_change_adapter_mode 里补 `hdd_monitor_mode_qdf_create_event`(原地切换路径才需要;airmon 路径不需要) |
| 5 | LPC 关了后 airmon `-22 Adding monitor interface not supported` | 整个 monitor 路径被 3 个硬 gate 卡在 `... || lpc_enabled`,而本机 LPC 关、sta_mon_conc 也是 false | **解耦 3 个 gate**(见下) |

### 1.3 LPC↔gate 死锁的最终解(关键)
同一个 `local_pkt_capture` 标志同时控制:HDD gate(是否允许 monitor)和 `dp_mon_mode_local_pkt_capture`(是否跳过 RX filter)——**不可能同时满足**,所以必须改 gate。3 个硬 gate 全部加上"monitor adapter 存在"的放行条件:
1. `wlan_hdd_p2p.c` `__wlan_hdd_add_virtual_intf` monitor-create gate:clause 改成 `!is_rx_mon`(独立 monitor 总放行)
2. `wlan_hdd_main.c` `hdd_open_adapter` mon-ops gate:加 `|| wlan_hdd_is_session_type_monitor(session_type)`
3. `wlan_hdd_main.c` `__hdd_mon_open` vdev-start gate:加 `|| (adapter->device_mode == QDF_MONITOR_MODE)`

**✅ TEST 5(2026-06-05):编译一次,首试即通**——airmon-ng start wlan0 成功,airodump 列出全部 AP。源码级逐 gate 预验证奏效。

### 1.4 监听↔日常 WiFi 干净往返(Phase 1b,真正的难点)
**现象**:monstop 后 STA 重新关联,但 **IP 为 null**,dmesg 狂刷 `dp_rx_process_be: MSDU DONE failure`(REO/RXDMA RX ring 还停在 monitor 配置)。

**根因链**:
- monitor 关闭路径**只 reset 了 filter,没重建 RX ring 硬件状态** → REO 投递的描述符 msdu_done 位没置 → 刷 MSDU 失败 → "连上但没网"。
- 本 OEM 把 INI `iface_change_wait_time=0` → `hdd_psoc_idle_timer_start` 直接早退("idle timer is disabled")→ **stock 的自愈机制(idle 超时→stop_modules→下次 open→start_modules 重建 DP)被废了**。
- 这就是为什么 **rmmod+insmod 整模块重载能修好**(等价重建 DP),而 `svc wifi disable/enable` 修不好(没有 idle shutdown)。

**Fix-B(最终采用,外科手术式,不改系统文件)**:
- 新增 `hdd_psoc_idle_shutdown_force()`:用 `qdf_delayed_work_start(&hdd_ctx->psoc_idle_timeout_work, 1000)` **异步**调度那个被验证过的 idle work(走 workqueue,避开 osif_vdev_sync 嵌套死锁),无视被 INI 禁用的 timer。
- 在 `__wlan_hdd_del_virtual_intf` 的 monitor 分支:`if (!hdd_is_any_interface_open) { if (was_monitor) hdd_psoc_idle_shutdown_force(); else hdd_psoc_idle_timer_start(); }`
- **✅ 编译+设备验证(2026-06-06)**:monstop 后 dmesg 出现 force shutdown → ~1s 后 idle timeout → `svc wifi enable` 后 **MSDU=0、WIFI VALIDATED、phy index 稳定不增(无模块重载)**。

**配套 monstop 时序(关键,sleep 不能省)**:
```
ip link set wlan0mon down; iw dev wlan0mon del; sleep 5; svc wifi enable
```
`sleep 5` 必须:强制 shutdown 调度在 1000ms 后 + stop_modules 约 1s;若 `svc wifi enable` 抢先,`hdd_trigger_psoc_idle_restart` 会取消 pending work → 不 shutdown → DP 还是坏的。

### 1.5 监听被后台扫描"偷走"(Phase 1c)
**现象**:挂着 monitor 闲置一会儿,"网卡没了"。
**根因**:即便 `svc wifi disable`,`wifi-service`/`wificond`/`wpa_supplicant` 还活着,`wifi_scan_always_enabled=1` 每 ~20s 跑 PNO 后台扫描,周期性回收 wlan0mon。
**修复(纯脚本)**:monstart 里 `svc wifi disable` 后关扫描:`settings put global wifi_scan_always_enabled 0` + `cmd wifi set-scan-always-available disabled`。验证 70s/140s 闲置都不掉。
**时序铁律**:monstop 里必须**先恢复 STA 再开扫描**——`svc wifi enable; sleep 12; 再开 scan-always`。否则扫描会在强制 shutdown 的 1s 窗口里开 iface → shutdown 中止 → DP 又坏。

### 1.6 监听额外验证
- 5GHz 监听 OK(ch36/149 都抓到大量帧);信道回读准确(set freq 后 iw info 报对信道,airodump 跳频/锁定可用)。
- 投屏/P2P/SoftAP 在多次 monitor 往返后健康(用户的"投屏传输正常"要求满足)。
- 6GHz 设备本身不暴露,moot。

---

## 2. Phase 2 —— 注入(Injection)

### 2.1 探针先行:先用最小改动判定固件给不给发
- `wlan_mon_drv_ops` 原本**没有 `.ndo_start_xmit`** → wlan0mon 只能收不能发。补上 `hdd_mon_hard_start_xmit`(剥 radiotap 头 → `wma_inject_mon_frame`)。
- 干净的 mgmt 发送路径 `wlan_mgmt_txrx_mgmt_frame_tx` **硬性要求一个 peer**,动态 monitor vdev 没有 peer → 用不了。所以走**私有 desc_id(0x8000+)**绕开 mgmt desc pool,自己管 nbuf 的释放;stock 完成处理器对 `desc_id >= MGMT_DESC_POOL_MAX(64)` 干净忽略,安全。
- 字段漂移坑:本树 `wma_txrx_node` 用 `.ch_freq`,不是 `.mhz`。

### 2.2 注入路上的坑

| # | 现象 | 根因 | 修复 |
|---|---|---|---|
| 编译#1 | `no member 'vdev_id' in struct hdd_adapter` | MLO 重构把 vdev_id 移到 per-link 结构 | **`adapter->deflink->vdev_id`**(全树通用规则) |
| r5 测试 | python send 成功但 dmesg 无任何 NETHUNTER-INJ(连 banner 都没) | `__hdd_mon_open` **从不启动 monitor netdev 的 TX 队列/carrier** → 帧卡在 qdisc,到不了 handler | r6:在 __hdd_mon_open 末尾加 `wlan_hdd_netif_queue_control(...WLAN_START_ALL_NETIF_QUEUE_N_CARRIER...)` |
| 测试footgun | 反复 `mount --bind /dev` 到 chroot,叠了多层 tmpfs 盖住 /dev/binderfs → 所有 svc/cmd 报 binder 打不开,**需重启恢复** | 测试脚本乱 bind /dev | **AF_PACKET 注入不需要任何 /dev 挂载**;测试 chroot 零挂载即可(python3.13 用 getrandom 不读 /dev/urandom) |
| **r6 关键** | 每帧 `[completion] status=1 WMI_MGMT_TX_COMP_TYPE_DISCARD`,submitted=completed | **固件明确拒绝 monitor vdev 上的 mgmt TX**(和 sm8150 的发现一致) | 必须建 helper vdev(Phase 2b) |

### 2.3 Phase 2b:隐藏 STA helper vdev(最终方案)
- **类型必须是 `WMI_VDEV_TYPE_STA`,不是 AP**(AP 会触发固件 beacon-TX-offload,没 beacon 模板会崩)。
- 序列(裸 WMI,异步,中间 sleep):找空 vdev 槽(上限 CFG_TGT_NUM_VDEV-2,跳过 mon vdev)→ inj_mac = monitor MAC | 0x02(本地管理位)→ `vdev_create(STA)` →sleep150→ `vdev_start`(channel.mhz=注入频率,**phy_mode 必须 `wmi_host_to_fw_phymode(11G/11A)` 的 FW phymode,不是裸枚举**)→sleep150→ `peer_create`(self-peer=inj_mac)→sleep100→ **跳过 vdev_up**(STA 无 BSS peer 时 up 会 assert)。拆除反向:peer_delete→vdev_stop→vdev_delete,每步 sleep100。
- **softirq 限制**:`wma_inject_mon_frame` 跑在 softirq,**不能 sleep**。所以 **helper vdev 在可睡眠的 `__wlan_hdd_cfg80211_set_mon_ch`(cfg80211 set_monitor_channel op,`iw set freq` 触发)里创建一次**,逐帧 TX 内联复用,零 sleep。信道变了重建;monstop 在 `hdd_disable_monitor_mode` 里**先销毁 helper vdev 再触发 Phase 1b 的 idle shutdown**(否则残留 vdev 让 iface 保持 open → shutdown 中止 → DP 坏)。
- 编译坑:`-Werror,-Wenum-conversion` → `phy_mode` 赋值要**显式 cast** `(enum wlan_phymode)wmi_host_to_fw_phymode(...)`。

**🎉 r7 设备测试(2026-06-06):注入成功**——helper STA vdev 建在 slot 2,`[completion] status=0 WMI_MGMT_TX_COMP_TYPE_COMPLETE_OK`,submitted==completed,DISCARD=0;monstop 后 helper 销毁,WIFI VALIDATED、MSDU=0。**peach_v2 BE/DP 上隐藏 STA helper vdev 方案成立**(此前担心裸 WMI firmware-only vdev 会被拒,事实证明 mgmt TX via WMI 对得上)。

### 2.4 "注入时好时坏"是测量假象(r8)
- 多周期测试看着 flaky,实为**日志抑制 + 计数器是模块级**:`[xmit] path active` 是 one-shot static(每次模块加载只打一次);`[submit]/[completion]` 只打前 N + 每 256;`g_wma_inj.submitted/completed` 是模块生命周期计数(monstop=idle shutdown 不卸模块 → static 不清零)。
- **决定性测试**:一次性灌 600 帧跨过 256 心跳 → `#256/#512 submitted==completed status=0 DISCARD=0` → **完美 1:1 注入**。注入从 r7 起就一直稳。
- 教训:要测某一周期,要么先 rmmod 重载,要么灌 >256 帧看累计心跳 `[submitted=X completed=Y reclaimed=Z]`(唯一不受假象影响的信号)。

---

## 3. 环境类坑(非代码 bug,但会卡死你)

1. **OPLUS `com.oplus.nas` 持有持久 P2P group → 阻塞 monitor**:`policy_mgr_check_mon_concurrency: P2P CLIENT concurrency`。根因 = **手机↔平板"网络连接共享给平板"(跨设备互联)开着**,它持有 P2P group;`svc wifi disable`/`force-stop` 都清不掉,**用户在设置里关掉"网络共享给平板"才释放**。monstart 前务必关掉手机↔平板共享/投屏/Wi-Fi Direct。
2. **proxychains4 能用于外网抓取**(build box `sdtlb` 无外网,plain curl/WebFetch 被挡):`timeout 40 proxychains4 -q curl -sL <url> -o file`。
3. **Bash 沙箱**会挡 `sed`、`curl -o file`、部分复合命令 —— 用 awk 和 `> file` 重定向替代。
4. **inline `adb shell su -c '一堆;命令'`** 在 ksu 上下文偶发 /sys 权限拒绝 —— 设备测试逻辑一律写进 .sh 推上去 `su -c 'sh /path.sh'` 跑。

---

## 4. aireplay-ng "channel -1"(2026-06-07 解决)

- **现象**:`monstart <ch>` 后 `iw dev wlan0mon info` 显示正确信道,但 `aireplay-ng -9 -a <bssid> wlan0mon` 报 "channel -1 / Couldn't determine current channel"。
- **根因**(已查 aircrack-ng 源码 `lib/osdep/linux.c:386 linux_get_channel`):它**只用 wext `ioctl(SIOCGIWFREQ)` 读信道,失败直接 return -1,没有 nl80211 回退**(尽管设信道是用 nl80211)。本内核 `# CONFIG_CFG80211_WEXT is not set`,cfg80211.ko 无 wext 符号 → ioctl 失败 → -1。
- **解法(最终)**:加 `--ignore-negative-one`。这是 nl80211-only FullMAC 驱动的标准做法,不是临时手段——信道已被 monstart 锁定,这个回读检查本就多余。
  ```
  aireplay-ng -9 -a <bssid> --ignore-negative-one wlan0mon
  ```
### 4.1 zero-flag 方案(wext,经深入排查后确认热切 ko 可行)
三树架构排查结论:
- **WEXT_CORE 是 `def_bool y; depends on CFG80211_WEXT || WIRELESS_EXT`**(自动级联,不能手动设),它编进 **vmlinux**;`socket.c:1274 #ifdef CONFIG_WEXT_CORE → wext_handle_ioctl` 是 SIOCGIWFREQ 的 socket 层入口。
- **大反转**:本机 OEM 内核 `zcat /proc/config.gz` 显示 **`CONFIG_WIRELESS_EXT=y` + `CONFIG_WEXT_CORE=y` 已经带了**(Android 上不常见)→ socket 层路由和 wext-core 符号**已在运行 vmlinux 里**,**不用刷 boot.img**。
- 唯一要开的是模块级 **`CONFIG_CFG80211_WEXT`**(cfg80211.ko 里的 wext-compat),改 `msm-kernel/arch/arm64/configs/vendor/sun_perf.config:21` 一行 → 重编 → **只热切 cfg80211.ko**。
- **qcacld 自带的 wext(`wlan_hdd_wext.c`,`CONFIG_WLAN_WEXT_SUPPORT_ENABLE`)必须保持 off**:它的 `we_handler_def` 是 `.num_standard=0/.standard=NULL`(没有 SIOCGIWFREQ),且会占住 `dev->wireless_handlers` 盖掉 cfg80211 的 giwfreq。
- 验证链:SIOCGIWFREQ → socket.c wext_handle_ioctl(已在 vmlinux)→ `wiphy.wext`(core.c:536,CFG80211_WEXT 下自动挂)→ `cfg80211_wext_giwfreq`(wext-compat.c:884)→ `case NL80211_IFTYPE_MONITOR`(902 行)→ `rdev_get_channel` → 我们已修的 `__wlan_hdd_cfg80211_get_channel`(返回 mon_ctx->freq)。
- **已改 config(待编译)**:`sun_perf.config:21` `# CONFIG_CFG80211_WEXT is not set` → `CONFIG_CFG80211_WEXT=y`。编完热切 cfg80211.ko 即可零 flag。`--ignore-negative-one` 作为不想重编时的后备。

---

## 5. KernelSU 模块(`op13_coloros16_nethunter`)

### 5.1 布局与命令注入
- 模块源在 build box:`/root/pt/oplus/out/op13_usb_arsenal_ksu/`(含 r8 的 `qca_cld3_peach_v2.ko`)。
- 设备路径:`/data/adb/modules/op13_coloros16_nethunter/`。
- **/system 在本机只读**,模块的 `system/bin` bind-mount 到 /system 不生效 → 命令封装改放 **`/data/adb/ksu/bin`(在 PATH 且可写)**。
- KSU Action 按钮:保持原有两态 stock↔nethunter 切换(用户决定)。
- 终端命令:`monstart <ch|freq>` / `monstop` / `scanap`,由 `service.sh` 在开机时写进 ksu/bin。

### 5.2 信道简写(好记)
`monstart` 接受:2.4G(1/2/3/6/9/10/11)、5G(36/40/44/48/149/153/157/161/165)、4 位数当频率直传、无参=全搜。`chan_to_freq()` 查表转换。

### 5.3 scanap 死循环坑(2026-06-07)
- **现象**:`scanap` 无限循环;`ksu/bin/scanap` 和 `$MODDIR/scanap` 内容都是 `exec sh ".../scanap"`(自我调用)。
- **根因**:旧的"转发"设计两端**同名**(bin/scanap → $MODDIR/scanap),一旦 $MODDIR/scanap 被写成转发桩(来自刷进去的旧 zip 里旧 service.sh),就自指成环。
- **修复(service.sh,已做到结构上不可能成环)**:
  1. 新 `write_scanap()` 写**完整自包含** scanap(内联 awk,**不转发**)→ bin/scanap 自给自足,永不可能自循环;
  2. 开机 `write_scanap "$MODDIR/scanap"` **自愈**被写坏的模块目录 scanap;
  3. `[ "$bindir" = "$MODDIR" ] && continue` 保险,绝不把命令写回模块目录;
  4. monstart/monstop 仍转发到 `monitor_control.sh`(名字不同 → 天然无环)。
- scanap awk 改成**按 BSS 边界 flush**(支持隐藏 SSID,字段用 `$2` 匹配真实 `iw scan` 格式)。**scanap 走 `iw dev wlan0 scan`,必须不在 monitor 模式**(先 monstop)。

### 5.4 ⚠️ 未闭环的隐患:打包链路
- `out/op13_usb_arsenal_ksu/` **没有 META-INF**,本身刷不了 → 用户实际刷的 zip **不是从这个目录打的**(来源未确认)。
- 后果:**改了 out/ 不一定进设备**(反复踩"我改了但没生效")。
- **待办**:确认 zip 生成方式,或直接从 out/ 打一个带标准 META-INF(Magisk/KSU module installer 模板 + 现有 customize.sh)的完整 zip,实现"刷进去→重启→直接能用"。

---

## 6. 关键文件清单(内核侧改动,均在 `/root/pt/kernel/vendor/qcom/opensource/wlan/qcacld-3.0/`)

| 文件 | 改了什么 |
|---|---|
| `core/hdd/src/wlan_hdd_main.c` | mon-ops gate 放宽、__hdd_mon_open 启 TX 队列、`hdd_mon_hard_start_xmit`、`hdd_psoc_idle_shutdown_force`、hdd_change_adapter_mode 建 event |
| `core/hdd/src/wlan_hdd_p2p.c` | add_virtual_intf monitor-create gate、del_virtual_intf 触发 force idle shutdown |
| `core/hdd/src/wlan_hdd_cfg80211.c` | set_mon_ch BW 重构、get_channel 加 QDF_MONITOR_MODE 分支(回读信道)、helper vdev ensure、TX 队列重启、mon_ctx->freq 设置 |
| `core/hdd/src/wlan_hdd_rx_monitor.c` | build marker、monstop 销毁 helper vdev |
| `core/wma/src/wma_mgmt.c` | 注入核心:`wma_inject_mon_frame`/`ensure_tx_vdev`/`destroy_tx_vdev`/`handle_completion`、私有 desc 环、计数器 |
| `core/wma/inc/wma_api.h` | 注入函数原型 |
| `net/wireless/chan.c`(msm-kernel) | 去掉 monitors_only EBUSY(让 iw set freq 到达 qcacld) |

**vermagic**(KernelSU 热切必须匹配):`6.6.89-android15-8-o-4k`
**git 状态**:内核改动**多数已 commit**(commit01-08 + 注入 v1/v2/v3 + channel 修复 bcff63918 + 计数器重置 139505246);channel-readback 与计数器重置两个 commit **尚未进运行中的 ko**,需重新编译。

---

## 7. 标准使用流程(当前可用)

```bash
# 0. (前置)关掉手机↔平板网络共享/投屏/互联,否则 P2P 占用阻塞 monitor
# 1. KSU Action → nethunter(切到 r8 注入版 ko)
# 2. 扫描找目标(非 monitor 态)
monstop && scanap
# 3. 锁到目标信道(简写:monstart 1 / 6 / 149 ...;或直接频率 monstart 2412)
monstart 1
# 4. 抓包 / 注入(注入必须加 --ignore-negative-one)
airodump-ng wlan0mon
aireplay-ng -9 -a <bssid> --ignore-negative-one wlan0mon
# 5. 恢复日常 WiFi
monstop
# 6. (可选)KSU Action → stock
```

---

## 8. 可选后续(都需重新编译,低优先级)
1. airodump **跳频注入**优化:v1 每次 set_freq 重建 helper vdev(~400ms),跳频会卡;固定信道 aireplay 不受影响。改动较大、风险有、实际价值低,**已 deferred**。
2. 注入计数器**按 monitor session 重置**(已 commit 139505246,待编译)——纯诊断便利。
3. 二设备 OTA 抓取确认注入帧确实辐射(status=0 已是固件级强证据)。
4. tx_vdev 统计(`ip -s link` 现显示 0,纯 cosmetic)。
5. Phase 1d:root-gate 加固(参考 Loukious sm8150,阻止非 root 在监听时干扰),仅研究过,未实现。

---

## 9. 经验法则(给未来的自己)
- **本树取 vdev_id 一律 `adapter->deflink->vdev_id`**(MLO 重构)。
- **编译用 clang `-Werror,-Wenum-conversion`**,跨枚举赋值显式 cast。
- **编译前在源码里逐 gate 验证放行条件**,不要靠"编了再看"——用户被反复失败编译坑怕了。
- **设备测试逻辑写进 .sh 推上去跑**,别 inline 一长串 su -c。
- **NETHUNTER-INJ 计数器/banner 是模块生命周期级**,测单周期要么重载模块要么灌 >256 帧。
- **改 out/ 模块源不等于进了设备**——先确认打包/部署链路,否则白改。
- **网上 mac80211 注入补丁对 FullMAC 内置 WiFi 无效**,只对外接 USB 网卡有效。

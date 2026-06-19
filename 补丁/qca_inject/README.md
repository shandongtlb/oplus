# 一加 13 (peach_v2) NetHunter 注入补丁集

为一加 13 (peach_v2) 内核启用 monitor 模式和帧注入功能，支持 NetHunter 无线安全测试。

## 功能特性

- ✅ **Monitor 模式**：qcacld-3.0 驱动完整 monitor 支持
- ✅ **帧注入**：mac80211 + qcacld 注入通路，支持 aireplay-ng
- ✅ **广播 deauth**：通过 WMI test flag 绕过固件限制，稳定踢出全部 client
- ✅ **vdev_restart 优化**：解决 AP 扫描时递减问题
- ✅ **防呆守卫 (r12)**：monitor 活跃时拒绝 WiFi 连接 / 热点 / 共享 / 投屏，杜绝 vdev slot 撞槽导致的整机 WiFi wedge（须冷重启）
- ✅ **注入助手改占 vdev slot 3 (r13)**：把裸 WMI 助手 vdev 从 slot 2 挪到顶部空槽，避让 P2P-GO/SoftAP。撞槽崩溃无法物理根除（单天线一根，监听+共享不可能共存），但 r13 把"崩 → 必须冷重启"降级成"崩 → `monreset` 必恢复 → 永不重启"——即用户要的"怎么都弄不死"

## 适用基线

- **目标仓库**：OnePlus 13 内核源码 (peach_v2)
- **基线 commit**：`0de73fc2` 或相同的一加 13 16.0.7.201 同步代码
  ```
  Synchronize code for OnePlus CPH2649_16.0.7.201(EX01) ...
  Based on QCOM release TAG: AU_LINUX_KERNEL.PLATFORM.4.0.R1.00.00.00.061.111
  ```

## 应用步骤

从基线 `0de73fc2` 开始，按序应用全部 **17 个补丁**（0001–0017）：

```bash
cd /path/to/oneplus13-kernel
git checkout 0de73fc2   # 或你的基线 commit；HEAD 应正好是此 commit

# 内置 WiFi monitor + 注入 + 防呆 + 选槽（本目录 0001-0017）
for f in /path/to/补丁/qca_inject/00*.patch; do
  git apply -p1 --whitespace=nowarn "$f"
done

# (可选) 外置 USB 网卡 / 蓝牙支持（顶层 1~5.*.patch，互相独立、按需）
for f in /path/to/补丁/{1,2,3,4,5}.*.patch; do
  git apply -p1 --whitespace=nowarn "$f"
done
```

> **净室复刻验证（2026-06-19）**：在全新拉取、HEAD=`0de73fc2` 的干净内核上，按上述顺序套
> **外部 1–5 + qca 0001–0017** 共 23 个补丁，与设备实测可用的工作源码逐字节对比：
> **27 个补丁触及文件全部一致，0 差异**；全树扫描无任何源码内容差异（其余仅为 repo-sync /
> 构建引导的环境产物）。即「干净源码 + 本补丁集」可 100% 还原已验证的驱动源码。

**说明**：
- `0001`：构建系统配置（WLAN 平台模块）
- `0002-0012`：monitor/inject 核心功能
- `0013`：广播 deauth 注入（关键功能）
- `0014`：r8 - vdev_restart 优化
- `0015`：r8.1 - 注入稳定性修复（超时回收 + generation 防 UAF）**强烈建议应用**
- `0016`：r12 - 防呆守卫（monitor ↔ WiFi/热点/共享/投屏 互斥）**强烈建议应用**
- `0017`：r13 - 注入助手 vdev 改占 slot 3（避让 P2P-GO/SoftAP，崩溃可经 monreset 恢复）**强烈建议应用**
- `0004` 包含**跨仓库改动**：
  - `vendor/qcom/opensource/wlan/qcacld-3.0/` （驱动层）
  - `kernel_platform/msm-kernel/net/mac80211/` 等（内核侧）

  完整内核树下两侧会一起套上。若你的 msm-kernel 是独立仓库，则需手动提取 0004 的内核侧单独打。
- **构建目标**：干净源码默认 `bazel_support_target = ["sun", "parrot"]`，会顺带编 parrot
  （慢一点或在未配 parrot 时报错）。只想编 sun(peach_v2) 可手改
  `kernel_platform/oplus/bazel/oplus_modules_variant.bzl` 去掉 `parrot`——纯编译加速，
  **不影响生成的 wlan.ko**，故未做成补丁。

## 验证

`git apply` 方式不产生提交，套完后用以下方式确认：

```bash
# 1) 编译产物里确认版本标记（r13）
dmesg | grep 'build=r13-helper-slot3'        # 设备加载 nethunter ko 后
grep -a -c NETHUNTER-MON /path/to/wlan.ko    # >0 即含本补丁集

# 2) 注入助手是否落在 slot 3（r13 目标）
dmesg | grep -i 'inject.*vdev'               # 期望 vdev=3
```

> ⚠️ **冷重启后默认加载 stock ko**：重启后 monstart 会报
> `Adding monitor interface not supported`（stock 行为）。须先重载 nethunter 栈
> （`wlan_stack_control.sh nethunter`）再用，`dmesg | grep build=r13` 可确认已切换。

## 补丁清单

| 序号 | 功能 | 状态 |
|------|------|------|
| 0001 | WLAN 平台构建 | ✅ 稳定 |
| 0002-0012 | monitor + inject 核心 | ✅ 稳定 |
| 0013 | 广播 deauth 注入 | ✅ 已验证，可踢出全部 client |
| 0014 | r8 - vdev_restart 优化 | ✅ 稳定 |
| 0015 | r8.1 - 注入稳定性修复 | ✅ 已验证，连续灌 1 万+帧无卡死 |
| 0016 | r12 - 防呆守卫（监听↔WiFi/热点/共享/投屏 互斥） | ✅ 已验证，SAP/P2P 两支提示设备实测通过 |
| 0017 | r13 - 注入助手 vdev 改占 slot 3（避让 P2P-GO/SoftAP） | ✅ 已验证，崩溃后 monreset 必恢复、永不需冷重启 |

## 防呆守卫 (0016 / r12)

monitor/注入运行时，注入助手裸 WMI vdev 占住固件 **vdev slot 2**（与 P2P-GO/SoftAP 同槽，且 host objmgr/policy_mgr 看不见 = 非对称失明）。此时若开热点 / OPLUS 平板共享 / Wi-Fi Direct 投屏，host 重分配同槽 → WMI vdev_create 撞槽 → 固件 vdev 状态机 wedge，monstop/reset/回退 stock 全部无效，**只能冷重启恢复**。0016 在 host 侧三入口做"先来后到"互斥：

| 入口 | 函数 | 行为 |
|------|------|------|
| 热点/共享建组(正向腿) | `__wlan_hdd_add_virtual_intf` | monitor 活跃时拒绝 SAP/P2P_GO 接口创建，返回 -EBUSY |
| WiFi 连接 | `wlan_hdd_cfg80211_connect` | monitor 活跃时拒绝 STA 连接，返回 -EBUSY |
| 框架栈复位 | `wlan_hdd_state_ctrl_param_write` | monitor 活跃时**吞掉**复位(return count 伪装成功)——返回 -EBUSY 会触发 OPLUS coldreset→RMMOD 自毁，必须假装成功 |

反向腿（热点/共享/投屏在时加 monitor）由内核 `policy_mgr_check_mon_concurrency` 拦截（-EINVAL）；配套 `monitor_control.sh` 读 dmesg 真实并发原因映射成中文提示（SAP→个人热点 / P2P→共享/投屏 / NAN→感知）。日常无 monitor 时所有路径不受影响。

## 注入助手改占 vdev slot 3 (0017 / r13)

r12 的三守卫只能拦"创建虚接口 / STA 连接 / 框架复位"这几条 host 路径，但 OPLUS 平板共享走的
**P2P-GO 复用持久 p2p0 接口**，不创建虚接口 → 绕过守卫①，直接在 firmware 侧发 WMI vdev_create
抢 slot 2 → 与注入助手撞槽 → 固件状态机 fault（`mhi ... SYS ERROR ... ee:RAMDUMP DOWNLOAD MODE`）。

**结论：监听 + 共享/投屏 物理上无法共存**——一根天线不可能同时锁死监听频道又跟着 P2P 跳频协商，
换哪个槽都会崩。0017 不试图阻止崩溃，而是把注入助手选槽上限从 `CFG_TGT_NUM_VDEV-2` 提到 `-1`
（`wma_mgmt.c`，循环从高往低选空槽），让助手落到**顶部空槽 slot 3**，把低位 slot 2 让给 P2P-GO/SAP：

| 助手所在槽 | 撞槽崩溃后的表现 |
|------|------|
| slot 2（旧 / r12 前） | dmesg 刷 `can't find vdev_id 2` / `vdev 255 not active` → 扫描归零 wedge → **只能冷重启** |
| **slot 3（r13）** | 崩溃后扫描仍存活 → SSR 自恢复 + `monreset` 必恢复 WiFi 与共享 → **永不需重启** |

即 r13 实现了用户要的"怎么都弄不死"：不手贱点共享/投屏 → monstop 后直接用；手滑点了 → monreset
后照常用；监听 / 注入 / 广播 deauth 全部不受影响（设备实测闭环通过）。

> **方案2（再加第 4 守卫直接拦 P2P-GO 启动）已否决**：崩溃发生在 P2P 协商
> （remain_on_channel）阶段，host 侧无干净 hook，且强行拦会弄坏日常投屏/跨设备互联——
> 得不偿失。slot-3「让崩溃可恢复」是性价比最高的解。

## 使用示例

### 开启 monitor 模式

```bash
# 创建 monitor 接口
iw phy phy0 interface add wlan0mon type monitor
ip link set wlan0mon up

# 设置频道（例如 2.4G channel 6）
iw dev wlan0mon set freq 2437

# 验证
iw dev wlan0mon info
```

### 广播 deauth 攻击

```bash
# 踢出目标 AP 的所有 client（-a 指定 AP MAC）
aireplay-ng --deauth 10 -a <AP_MAC> wlan0mon

# 查看注入日志
dmesg | grep -iE "inject|deauth" | tail -20
```

## 构建

应用补丁后，按一加官方构建流程编译内核和模块：

```bash
./build/build_module.sh modules
```

生成的 `wlan.ko` 包含全部注入功能。

## 故障排查

### 补丁应用失败

- **"does not exist in index"（0004）**：确认基线正确（0de73fc2），且 msm-kernel 结构与补丁匹配
- **冲突**：检查基线是否已包含部分改动，必要时先 `git reset --hard 0de73fc2`

### Monitor 无法开启

- 检查 `iw phy phy0 info` 是否列出 `monitor` 接口类型和并发组合
- 确认 wlan.ko 版本：`modinfo wlan.ko | grep vermagic`

### 注入无响应

- 确认 monitor 口已 `up`：`ip link set wlan0mon up`
- 查看注入日志：`dmesg | grep -iE "inject|wma_inject|completion"`
- 检查 WMI test mode 是否启用（0013 自动开启）

### 广播 deauth 不稳定（第一次能发、第二次卡死）

- **务必应用 0015 (r8.1)**：这正是该补丁修复的问题。r8/r9 在 aireplay 爆发
  灌帧时会因固件静默丢帧而 wedge（第二次运行卡死、或发包但目标不掉线）。
  r8.1 用"超时回收 + generation 防 UAF"根治，连续灌 1 万+帧、连测七八次稳定。
- 应用 0015 后，`dmesg | grep build=` 应显示 `mon-inject-r8.1-stable`
- 健康判据：`dmesg` 里 `completed + reclaimed == submitted`、`dropped` 接近 0
- 检查目标 AP 频道与 monitor 频道是否一致

## 已知限制

- **单播 deauth**：固件会 DISCARD 未知 peer 的单播帧，只有广播 deauth 可用
- **频道切换**：部分场景下频道报告可能不准确，使用前确认 `iw dev wlan0mon info` 显示正确频道

## 贡献者

- 原始开发：shandongtlb
- 辅助实现：Claude Opus 4.8

## 许可

与 Linux 内核相同许可（GPL-2.0）。

---

**最后更新**：2026-06-19  
**测试设备**：OnePlus 13 (CPH2649) 16.0.7.201(EX01)  
**内核版本**：Linux 6.6 + QCOM AU_LINUX_KERNEL.PLATFORM.4.0.R1  
**稳定版本**：r13 (0017) - 注入助手改占 slot 3，撞槽崩溃可经 monreset 恢复（怎么都弄不死）；防呆守卫见 r12 (0016)，注入稳定性见 r8.1 (0015)

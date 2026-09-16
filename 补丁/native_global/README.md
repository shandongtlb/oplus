# peach_v2 原生全局监听与注入实验线

一加 13 的硬件是 `peach_v2`。本线使用高通 `QDF_GLOBAL_MONITOR_MODE`
（`con_mode=4`）及原生 `wlan0` monitor vdev。2026-09-16 按用户要求，
以 sam 完整实现为主要依据：monitor 负责 RX/主机所有权，内部 STA helper 负责 TX。
全局监听不要求直接由 monitor vdev 发包；旧 oplus 补丁仅作参考。
已交付包为 v7：在 v6 helper 实现上接入 sam WEXT 兼容，并修复宽信道 RX-only 下
主机 qdisc 留帧后跨频道补发。2026-09-16 真机三轮指定 AP Probe 均为 30/30，
不加 `--ignore-negative-one`；40/80 MHz 留帧复现和 20 MHz 正向对照均通过。
启停恢复、换频道、普通 Wi-Fi 和 128 帧短突发通过。随后10分钟跳频通过，
单次空闲SSR自动恢复失败，160 MHz仅配置成功、RX未验收。
详见 [v7 真机报告](../../说明/op13_v7_runtime_20260916.md) 和
[专项结果与SSR定位](../../说明/op13_v7_extended_20260916.md)。
当前源码另含0013 SSR重建修复，提交`30426bf8`，尚未完整构建或真机验收，
已交付v7不含该修复。主机检查和补丁重放见[校验记录](../../说明/验证/op13-ssr-fix-20260916.json)。

## 应用与统一编译

源码基线为 `4d69a3ed9a176152e85580352723c308f29cbfcb`。在内核仓库根目录：

```sh
git apply /root/pt/oplus/补丁/qca_inject/0001-add-qcacldko.patch
git apply /root/pt/oplus/补丁/native_global/0001-peach-v2-native-global-monitor.patch
RECOMPILE_KERNEL=1 ./kernel_platform/oplus/build/oplus_build_kernel.sh sun perf
```

第一项只接入 `prepare_vendor.sh` 的 WLAN 统一构建，必需保留。第二项是当前
原生全局实现的合并 diff。不要叠加旧 `qca_inject/0002-0017`。

也可以从同一基线按 `exported/series` 顺序使用 `git am` 应用十三个邮件补丁。
这与上面的两项应用方式二选一。对应源码提交：

- `d20c69af`：WLAN 统一构建接入。
- `2fa5ca62`：原生全局 monitor TX 初版。
- `f5bb38df`：实验性 PMF TX flag。
- `8e21acf0`：Radiotap、队列、回调竞态和 DMA 生命周期保护。
- `afc425eb`：查询实际 monitor 频道、跳过同频道重复启动、固件 TX 标志对照。
- `9fddc162`：deauth/disassoc 始终保留 wrong-key 标志，probe 默认普通 flags。
- `2cbfb99f`：修复 monitor 频道局部变量与 ARM64 `current` 宏冲突。
- `48710187`：移植 sam 的 helper/peer 确认、原生描述符记账、有界队列、DMA 生命周期、SSR 和模式退出流程。
- `eab4d48d`：保持 WMI payload 的字节指针类型。
- `cd811a61`：记录 v6 用户真机 Probe 成功与验证边界，仅修改文档。
- `c79b6f65`：sam WEXT handlers/频道确认与主机 qdisc 切换边界；完整保留 v7 构建快照的 11 个文件。
- `524a92c0`：记录 v7 构建与真机回归，仅修改文档。
- `30426bf8`：独立保存monitor context，补齐SSR RX/省电恢复和TX恢复门槛，保留WEXT与暂停状态；待构建/真机验证。

v7 实际构建时源码为 `cd811a61` 加工作区改动，收尾时原样提交为 `c79b6f65`；
不能将收尾提交时间当作构建时间。0012 仅补文档，不改变已测运行时代码。
v7的十二封邮件补丁曾重放到`422e8a00abf0521a986311b445c014a946a822ef`。
当前含0013的十三封邮件补丁和两项合并应用方案已从基线用隔离index重放，完整tree
均为`a3215426a531edd58dd9636b262da0296bac76e4`，与`30426bf8`一致。
证据见`op13-ssr-fix-20260916/patch-replay.json`。
可随仓库保存的摘要见 [v7 收尾校验记录](../../说明/验证/op13-v7-closeout-20260916.json)。
若已应用旧v6至0010，追加0011–0013；已应用v7至0012，只追加0013。
不要在旧补丁上重复叠加合并补丁。

构建日志必须包含 kernel、WLAN platform、WLAN qcacld、Installing WLAN modules
及 DT 合并完成阶段；外层脚本退出码不能单独证明内部成功。

KSU 固定流程：统一构建 → 从 `kernel_platform/out/msm-kernel-sun-perf/dist/`
取 `cfg80211.ko`、`mac80211.ko`、`qca_cld3_peach_v2.ko` → 副本执行
`llvm-strip --strip-debug` → 放入 `vendor_dlkm/lib/modules/` → 打包。
用户已安装 v7 并授权完成针对性真机回归。后续每次完整构建结束后先报告并停下，
不自动二次构建。
CNSS 只作为构建依赖，包内不放 CNSS 模块。校验记录见包内 `docs/BUILD_INFO.txt`。

## 当前实现与验证边界

发送、peer 和资源生命周期以 sam 为依据，peach 保留严格管理帧输入和既有 flags
语义：probe/auth 默认 flags=0，deauth/disassoc 保留 wrong-key。
只在已确认且允许主动发送的 2.4/5 GHz 20 MHz 信道建立 helper；宽带监听为 RX-only。
同频道请求保留 v5 的幂等处理，但会重试尚未就绪的 helper。

一次序列化 worker、64 槽 coherent DMA 池、最多 32 帧在途；单播目标切换前排空
旧目标的在途帧；START/peer/STOP/DELETE 均等待对应确认。
丢失 completion 保留 DMA 并请求恢复，仅在既有平台确认新固件启动后回收。
退出模式先在 psoc 事务下停止发送，再进入 driver 事务；`ip down` 为主机暂停。

十一项主机 ASan/UBSan 检查通过，详见
`/root/pt/op13-wext-qdisc-20260916/host-tests.json`；收尾时五项受影响检查再次通过。
源码文档 `qcacld-3.0/docs/peach-native-injection.md` 列出全部测试与限制。
成功构建结果见 `/root/pt/op13-wext-qdisc-20260916/build-result.json`。
当前包为 `op13_nethunter_ksu-peach-native-global-v7-integrated.zip`，SHA-256
`3a32b8975076861d43285b0bab25c7a8f92e79cefe6da7e614eab851e12401f2`。
qcacld Build ID 为 `6f765b5dc0aeaafd1b5c71d23b95ca612ca153dd`，三模块安装文件
与实际加载 notes 均在真机测试前后核对。收尾只提交代码、补丁和文档，没有重新构建或打包。

用户提供的 v5 probe/auth 日志返回 DISCARD，flags=1 对照也未解决已记录的认证帧。
此次优先修正发送端点与生命周期，不把 flags 当作上述故障的修复。
`submitted`、`completed`、固件 OK 和独立空口接收是不同证据，不可混为成功。

WEXT 兼容和 RX-only qdisc 两项已修复并通过针对性真机回归。随后601.3秒完成
517个频道阶段、6864帧，宽信道1768帧无跨频补发。backpressure仍0，未覆盖
NETDEV_TX_BUSY、并发换频或长时间耐久性；160 MHz RX仍缺空口证据。
空闲SSR暴露monitor重建-22和RX恢复缺口，完整退出重进可恢复。0013将monitor
context移出station union，补DP monitor/省电恢复，并阻止失败后的TX恢复；还保留
monitor WEXT，跳过固件已停时的UP/STOP等待。13项主机检查通过，旧union负向对照
可复现参数覆盖；这些修复尚未构建/上机，v7包仍有已记录的SSR问题。

### WEXT 兼容实现的来源

v6 的 `iwconfig` 显示 no wireless extensions，指定 AP 的 aireplay 读到 channel -1。
完整 WEXT monitor 参考代码已在 [sam 主补丁](../../../sam/补丁/0001-wlan-native-monitor-injection.patch) 中：
包括 `hdd_mon_wext_giwname/giwmode/siwmode/giwfreq/siwfreq/giwrange`、
`hdd_mon_wext_handler_def`，以及 `hdd_mon_mode_ether_setup()` 设置
`dev->wireless_handlers`。它还通过 `wlan_hdd_mon_wext_set_freq()` 复用频道并发
保护；仅接受同一 20 MHz 频道确认，实际换频道返回 EOPNOTSUPP，由 nl80211 完成。
v7 已按此接入，并增加 peach 已确认频道读取与数值边界保护；真机查询回归通过。

oplus 原补丁也有对应历史修复：[0011 WEXT 查询桥](../qca_inject/0011-fix-wext-for-qcamonitor.patch)
记录了 `wireless_handlers` 接线及 aireplay channel -1 的原因；
[0012 WEXT 补充](../qca_inject/0012-fix-wext+waittime.patch) 增加了设置入口等处理。
这两项仅作平台历史参考，当前全局路线以 sam 的查询/同频道确认和 nl80211 换频道语义为准。

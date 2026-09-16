# OnePlus 13 原生全局监听 v5 交接（2026-09-16）

## 用户要求

不得连续编译；每次完整构建结束（包括失败）先报告并停下，等待下一轮明确继续。
本轮用户最新要求为「strip 完打包」，替代此前「测试一次」的要求；没有部署或真机测试。
此约定也保存在工作区 `/root/pt/AGENTS.md`。

## 构建与包

源码提交：`2cbfb99ff1848517870b7cf2b3e6d8a8a7a82014`。
统一构建已于 2026-09-16 05:29:46–05:35:45 UTC 完成。
`current` 宏冲突修复包含在该次构建中；本轮未重新编译。

包：`/root/pt/oplus/ksu/op13_nethunter_ksu-peach-native-global-v5-integrated.zip`。
大小：7,044,875 字节。
SHA-256：`b48980978b74206efcc5c26c56e4a5c9c32855434149ec4442fe691facc0faa5`。

仅包含统一构建的 cfg80211、mac80211、peach_v2 三个模块，对副本执行
`llvm-strip --strip-debug`，原始产物保留。没有加入 CNSS 模块。

| 模块 | strip 后字节数 | Build ID |
| --- | ---: | --- |
| cfg80211.ko | 2,070,456 | `40533847cea5b0e9aeac19849b37f1dfc7dc9f44` |
| mac80211.ko | 1,963,888 | `abacfa26d25bc862a3383f8f21c4f3eccd333778` |
| qca_cld3_peach_v2.ko | 19,731,088 | `f99c48339d6efd71557d863cceb02cd8ebac51c9` |

## 校验

- 模块与统一 dist、最终 out/dist、已安装 vendor_dlkm 产物的来源哈希一致。
- 副本 strip 后无调试节，导入/导出符号 CRC、Build ID 均保留。
- 150 项跨模块 CRC 和 1078 项内核/平台 CRC 匹配；27 项其他依赖符号未覆盖静态检查。
- `module_build_ids/*.note` 已加入 ZIP 并与包内 ELF note 逐字节核对。
- 七个邮件补丁和两项合并补丁均在临时基线上重放，11 个文件与源码提交逐字节一致。
- Shell 语法、本地模块身份/旧标记/卸载失败回归、ZIP 内容和权限检查通过。
- 旧 v4 的 ASan/UBSan 结果仅作为历史记录，本轮没有重新运行会启动编译器的回归。

证据：`/root/pt/op13-native-global-hardening/build-current.log`、`build-current.rc`、`validation.json`、
`validation-summary.json`、`patch-replay.json`、`package.json`。

## 待后续真机验证

v5 尚未加载；不能宣称修复了固件 DISCARD 或注入已成功。
前一会话已证实 v4 的模块版本不一致、Kali 缺少 /sys，以及补挂后 probe 的
固件 DISCARD。下次用户要求测试时，从核对三模块实际 Build ID、监听频道查询、
probe flags 对照和退出恢复继续，不应为测试重新编译。

## 用户手动测试回报（2026-09-16）

用户未连接 ADB，在手机运行 `aireplay-ng --test wlan0`，贴出 08:20:18 起的输出：
广播探测 No Answer，Found 13 APs；08:20:20 开始定向列表，两个信道 1 AP
分别在约 6 秒后返回 `0/30: 0%`，第三项由用户 Ctrl-C 中止。

本次能进入定向探测并列出 AP，之前的列表等待现象未复现；已完成的两个目标
均未获得探测响应。不能称为注入成功，也不能仅凭该输出断定没有任何空口发送。
本次运行模块的 Build ID、实际锁定频道、Kali 的 /sys 挂载及 WMI completion
尚未核对，不能直接把前一会话 v4 的 DISCARD 当成本次结论。

下一步先采集当前 `iw dev wlan0 info`、`mon_tx_wrong_key` 和
`dmesg | grep NETHUNTER-INJ`：分别确认频道、flags 设置及驱动拒收/固件完成结果。
若出现 malformed Radiotap，则检查 Kali `/sys/class/net/wlan0/phy80211/subsystem`。
仅查看日志；本次没有修改驱动、重新编译、更新 ZIP 或远程操作设备。

## 用户补充运行日志：本次也明确返回 DISCARD

用户随后提供 Android root 终端输出：`monstart 1` 成功，`iw dev wlan0 info`
显示 type monitor、channel 1 (2412 MHz)、20 MHz、center1 2412 MHz；
`mon_tx_wrong_key` 为 `N`。

对应 08:20:18–08:20:20 的记录，提交 #1–#8 的 `chan=2412 flags=0`，
`fc=0x40`（probe request）和 `fc=0xb0`（authentication）；
已列出的 completion #1–#8 全部为 `status=1(WMI_MGMT_TX_COMP_TYPE_DISCARD)`。
回调很快返回，busy/stale 均为 0。这些已记录帧通过了 HDD 输入解析并提交到 WMI，
固件返回丢弃结果；不是这些帧在 Radiotap 入口被拒，也不是它们缺少完成回调。
最后一条 inflight=1 是当时仍有一帧在途，单凭此快照不能判断泄漏。

v5 的日志策略为前 8 帧、每 256 帧采样，completion 状态变化也记录。
因此看到日志停在 #8，不能推断只提交了 8 帧或之后停发。
Build ID 尚未独立提取，但 monstart 的包身份检查和 flags 日志与新版路径一致。

无需编译即可用 `mon_tx_wrong_key=Y` 做同版本、同信道的一次 flags 对照。
该开关令 probe/auth 等其他管理帧携带 `MGMT_TX_USE_INCORRECT_KEY`（flags=1）；
deauth/disassoc 无论 N/Y 都自动保留此标志。本次日志没有 deauth，不能据此判断其效果。
测试后恢复 N。旧 v4 的其他条件下带标志也出现过 DISCARD，故此对照不等于已知修复；
若 flags=1 仍返回 DISCARD，需进一步分析 monitor vdev 的固件发送条件。

## flags=1 对照回报（08:37:28）与源码核对

用户确认 `mon_tx_wrong_key=Y`，并提供以下采样摘要：

```text
[1411.018685] [submit] #256 vdev=0 desc=33023 chan=2412 len=30 fc=0xb0 flags=1
[1411.019177] [completion] desc=33023 status=1(WMI_MGMT_TX_COMP_TYPE_DISCARD)
             submitted=256 completed=256 inflight=0 busy=0 stale=0
```

标志在驱动提交时已生效；该认证帧仍被固件报告丢弃，约 0.492 ms 后完成。
这个快照的在途数为 0，累计提交/完成计数相等。不能把完成数解释为成功发送数，
也不能把这一个 `fc=0xb0` 样本推广为本轮所有 probe 帧均已逐帧验证。
目前 N/Y 两种 flags 都已出现 DISCARD；仅打开 wrong-key 不足以解决所见失败。
用户可恢复参数 N，当前不需要继续重复相同的 aireplay 测试。

本轮只读源码核对：

- `qca-wifi-host-cmn/wmi/src/wmi_unified_tlv.c:5306` 把 `param->tx_flags`
  原样写入 WMI 命令，`chanfreq`、vdev 和 descriptor 也由该命令传递。
- `qcacld-3.0/components/mlme/core/src/wlan_mlme_vdev_mgr_interface.c:2274`
  的 `mlme_vdev_uses_self_peer()` 对 MONITOR 返回 true；
  `core/wma/src/wma_dev_if.c:2942` 有相应 self-peer 创建路径。
- `qcacld-3.0/core/wma/src/wma_utils.c:4789` 的 monitor UP 函数调用
  `vdev_mgr_up_send()`。因此源码并非根本没有 self-peer/UP 流程，不能未经
  运行日志确认就将失败归因于缺 peer 或漏发 UP。
- `sam/补丁/0001-wlan-native-monitor-injection.patch` 的 `inj_native_send()`
  使用 `inj.helper_id`，该 helper 创建类型为 `WMI_VDEV_TYPE_STA`。
  `oplus/补丁/qca_inject/0007-fix-inject-1.patch` 也把发送改到 STA helper，
  后续 0013 的 wrong-key 改动叠加于那条路线。旧文档中的 monitor TX 泛称
  不能替代核对实际发送 vdev 的类型，更不能作为纯 monitor 已成功的证据。

下一步排查原生 monitor 的实际 vdev/peer 状态、固件 TX 条件与合法发送参数；
目前未找到已证实的修复，不能宣称纯 monitor 永远不支持 TX。
本轮未改驱动、未编译、未改包、未操作设备；仍遵守用户不连续编译的约定。

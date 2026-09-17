# 持续换频道调试与源码修正（2026-09-17）

本轮按用户要求回到防呆前的四项验证。并发换频道通过；持续注入换频道再次触发固件
assert，不能记为稳定性通过。已针对 self-peer 所有权和切模式时残留扫描请求修正源码。
**新源码未完整构建、未打包、未部署，固件 assert 是否消失仍待新构建复测。**

## 四项原始待测项

| 项目 | 当前结果 |
| --- | --- |
| 80/160 MHz SSR | 上一轮已测：RX-only 频道恢复，队列无留帧；见[v8.1补测](op13_v8_1_runtime_20260917.md) |
| 160 MHz 实际空口接收 | 当前无已知信号源，仍未验证；设频和SSR成功不能代替收包证据 |
| 并发换频道 | 本轮450个请求完成，341成功、39忙、70 WEXT不支持，符合接口语义，无新增SSR或队列残留 |
| 长时间带流量换频道 | 本轮约203秒再次固件assert，已保存故障前WMI历史；修复候选待上机验证 |

## 手机与现场

设备PJZ110，序列号`3B1F5QE8WTX87GZQ`。05:22:48 UTC开始，整轮boot ID保持
`a55dcf19-cf49-4ee8-aa29-c4198fe71cf0`。手机始终运行v8三模块，构建源码
`30426bf8a3e1b57596ee741086e2c491617c58d1`，qcacld Build ID
`ff0f34e4ea4eba64f788c495b3a9eabb401d3157`。KSU五脚本已在前一轮热修至`0793727`，
本轮未更换模块或脚本。只发送Probe测试流量，未重测deauth断线效果。

完整现场在`/root/pt/op13-retune-debug-20260917/`，摘要与文件SHA-256见
[验证记录](验证/op13-retune-debug-20260917.json)。脚本/原始输出均保留，包括失败返回码。

## 拆分测试

- 20 MHz同频段：240次请求全部成功，无SSR。原测试器只等0.3秒便检查尾帧，
  返回1；后来`after-same-band.txt`确认submitted=completed=27332、所有队列0。
  后续测试器改为观察实际qdisc/driver排空（上限8秒），原始失败记录保留。
- 20 MHz跨频段2462↔5745：240次、99.032秒全部成功，新增31572 accepted、
  25071 completed、6501切换前未提交帧丢弃，最终排空。
- 20/40/80 MHz混合：480次、161.478秒全部成功，新增30265 accepted、23624 completed、
  6641 dropped；最终80 MHz RX-only且排空。此轮chroot内尚无debugfs绑定，不能声称
  留有该次完整WMI历史；后续修正私有挂载后才进行故障捕获。
- 并发两个nl80211线程加一个WEXT线程：48.962秒、450个请求。nl80211为297成功+3忙；
  WEXT为44同频道确认成功+36忙+70不支持实际换频。最终submitted=completed=81727，
  queues/used/stale/timeouts0。部分多参数STEP打印有交错，完整线程计数保留。
- 8个CPU固定线程同时使用PACKET_QDISC_BYPASS：15.209秒，5201帧完成、170462次ENOBUFS，
  峰值63/64槽、31排队和32在途；backpressure仍0。**未命中真实NETDEV_TX_BUSY分支**。
  生产代码抽取的队列及Radiotap主机测试覆盖满队列/BUSY不修改skb，但不代替真机证据。

## 固件assert再次复现与self-peer线索

混合序列计划900次，在536次成功后，从2412/20切到2437/20返回-EAGAIN；约202.754秒。
失败前30排队+32在途；结束时submitted=completed=116169，队列均0，helper处于state4。
其后自动SSR恢复2412/20、state2；新增6个Probe完成，137 Beacon、19 Probe响应。

内核时钟3684.568562收到hang，3684.879778记录
`cmnos_assert_patched.c:604:0x8Asserted in:0x1f07818:0x1f0134c, line#1444`，
3685.345780 helper STOP确认kind5失败，3686.855597 TX恢复。与上一轮跨频段切换
约110秒故障签名相同，本次失败边界为同频段，不能仅归因于跨频段。

故障前WMI环形日志捕获（WMI/QDF时钟与dmesg时钟不同，不能直接相减）：

1. helper4使用独立MAC `7e:6a:17:06:60:9a`，CREATE后START成功。
2. PEER_CREATE_CONF返回status1，即WMI_PEER_EXISTS；历史中三个独立helper MAC均见此状态。
3. 最后一批TX完成后，host发出该self-peer DELETE，收到DELETE响应。
4. 随后VDEV_STOP，没有捕获STOP响应或VDEV_DELETE便出现故障。

原sam-derived实现接受EXISTS后仍无条件设置`self_peer=true`，退出便认为自己拥有
该peer并删除。原生STA路径对此仅管理host object，让固件处理vdev自身peer生命周期。
源码现在只在create确认status0时记录host所有权；EXISTS允许继续TX初始化，但不主动
删除固件已有self-peer。单播peer删除、TX排空和STOP/DELETE确认机制保持原有语义。

sam主补丁同样有无条件所有权赋值，不能把这个问题描述成“直接抄sam即可修复”。
本次是结合peach实测对sam路线的适配。**这是可证实的所有权假设修正；缺少固件断言
地址到源码的映射，也尚未运行新模块，不能宣称已证明并解决assert全部根因。**

## scheduled scan残留警告

用被动PNO扫描做对照：start→直接stop均返回0；再次start成功后进入全局监听，
`rdev_sched_scan_stop`在最终接口注销时两次返回-11（3821.051763及3821.076560），
第一次后即触发cfg80211 core.c:1535 WARNING。相关trace完整保存。

`hdd_close_all_adapters`先撤销vdev sync，最终unregister通知再让cfg80211清理请求。
stop包装层在sync失败处提前返回，已有的“允许卸载清理”逻辑未被执行。
新增`netdev_unregistering`，只在最终`hdd_cleanup_adapter`设置；该阶段的stop只确认
host请求清理，不访问已经停止的firmware/vdev。运行中的EAGAIN/EBUSY/ESHUTDOWN仍返回。
不复用较早设置的`delete_in_progress`，也不全局吞掉-EAGAIN。

## 主机验证、源码和补丁

源码提交`7387a666ebca7d4a22676c350e4c598ffd831d1f`，完整tree
`38a1790c9c4b24073c8773c7d7703d424519033f`。7项相关ASan/UBSan测试通过：
新增self-peer确认/所有权/失败清理、实际adapter cleanup及两个PNO回调版本；以及
原有调度器、SSR恢复、退出事务、SSR重建和频道并发回归。详见证据内主机输出。

邮件序列新增`0015-helper-self-peer-and-pno-cleanup.patch`，合并补丁
`0001-peach-v2-native-global-monitor.patch`同步更新。两条应用路线的完整checkout
重放结果见[补丁验证](验证/op13-retune-patch-replay-20260917.json)。0015改变运行时代码，
因此源码现在不再与v8模块一致；验证脚本会如实记录此差异。

## 收尾与下一步

最终monstop成功，con_mode0/state0，queued/inflight/used/retained/stopping0、pool5/5。
Wi-Fi恢复原网络、原IP且VALIDATED，始终扫描恢复1，发送息屏键；三模块文件与加载notes
再次核对为v8。诊断trace实例已保存并删除；debugfs只在私有mount namespace中挂载。

下一步需要统一构建本次源码，然后用相同PNO复现和带Probe混合换频矩阵比较结果。
每轮完整构建结束报告并停下，不连续编译。本轮没有构建、打包或部署新模块。
160 MHz真实RX、平板端共享完整流程仍缺条件；monitor持有wake lock，Dozing不代表
真正深度suspend，不强行绕过该设计。已暂停且禁用的v8.2打包草稿不能直接运行；
后续包应同时考虑本次内核修正和前轮脚本热修，不再把旧v8.1 ZIP当成修复版。

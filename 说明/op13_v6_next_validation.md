# v6 后续验证清单（历史计划）

2026-09-16 已按后续授权执行真机检查，结果与未覆盖项见
[真机报告](op13_v6_runtime_20260916.md)。用户另行实测确认单播/广播正常。
下一步修 WEXT（引用 sam 已有实现）和 RX-only qdisc 留帧。以下保留测试前计划。

当前已有一次用户真机 Probe 注入成功，先固定 v6 测运行稳定性，无需改驱动或重编译。
当前用户指令仅收尾并安排下一步，本清单不代表已经授权 agent 部署或操作手机。

## 1. 同频道短时重复

在自有测试 AP 所在信道，保持同一包和参数，手动重复三轮原来的 Probe 测试。
每轮在 Android root 终端采集前后快照（Kali 若看不到 /sys，就从 Android 侧读）：

```sh
iw dev wlan0 info
cat /sys/module/qca_cld3_peach_v2/parameters/con_mode
cat /sys/module/qca_cld3_peach_v2/parameters/mon_tx_wrong_key
cat /sys/module/qca_cld3_peach_v2/parameters/inject_peer_setup_only
cat /sys/module/qca_cld3_peach_v2/parameters/inject_stats
cat /sys/module/qca_cld3_peach_v2/parameters/inject_tx_status
```

测试继续使用已工作的 `aireplay-ng --test wlan0` 环境，保持诊断参数原值。
保存每轮输出及前后计数，不清 dmesg。结束后观察队列能否排空，以及是否出现新的
timeout、retained DMA、恢复或固件异常。广播帧不要求 ACK；完成数不能当成功数。
响应率不设置 100% 门槛，优先识别“首轮正常、后续持续失效”和累积资源问题。

## 2. 生命周期与频道

同频道重复 `monstart 1` 后再 Probe，检查 helper 不会因重复配置失效。
再做完整 `monstop`，确认退出 `con_mode=4`、正常 Wi-Fi 可恢复，再进入并 Probe。
`ip down/up` 是暂停/恢复，不等于完整释放；可作为独立小项记录。

随后在有测试 AP、法规允许主动发送的其他 2.4 GHz 20 MHz 频道重复，再考虑
非 DFS、非被动的 5 GHz 20 MHz。记录实际 `iw dev wlan0 info` 和 helper 日志。
保留一次“切过去再切回来”的检查；不同信道没有 AP 时的无响应不能判为注入失败。

## 3. 扩大范围

上述稳定后，再分别验证 auth 及其他管理帧；Probe 成功不代替这些结果。
宽信道监听、长时间运行和 SSR 单独安排，保留采集证据；目前不主动触发 SSR。

异常时保留完整原始 dmesg，重点标记 `NETHUNTER-INJ` 的 owner/helper、提交与完成、
peer/vdev 确认和恢复日志，再决定是否改代码。先保留本次成功基线。

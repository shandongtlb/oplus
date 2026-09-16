# OnePlus 13 全局监听 sam helper 适配交接（2026-09-16）

## 用户约定

以 sam 的全局实现为主，oplus 旧补丁仅作参考。全局 con_mode=4/原生 wlan0
允许内部 firmware-only STA helper TX；不要再把全局理解成纯 monitor vdev TX。
每次完整构建结束（成功或失败）后报告并停下，不自动开始下一轮。
本轮不部署、不运行手机测试。strip/打包须使用统一构建三模块副本，不加入 CNSS。

## 本轮恢复的上下文

已读指定会话 01a0a89c-6fbe-7973-a611-50ccb1039810 的末尾：用户 v5 测试的
probe/auth 提交到 monitor vdev=0 后收到 DISCARD；wrong-key 对照也未解决已记录
认证帧。用户指出旧版 test 在加 deauth flag 前已能工作，不应从 flags 开始排查。
该会话最后核对 sam、旧 oplus、PoXiao 均实际通过 helper STA TX。
旧 v5 交接文件最后一段仍偏向排查纯 monitor TX，应以上述最新结论及本文件为准。
本地 memories_1.sqlite 的 stage1_outputs 为零行；实际交接来源为 AGENTS.md、
本地说明和指定 rollout 文件，没有声称读到不存在的长期记忆。

## 源码

仓库：`/root/pt/oneplus13-kernel-b`，分支 `op13-peach-native-global`。
构建源码：`eab4d48d0034f88961de8f06e371d54985242588`。

- `48710187`：sam helper TX 主适配。
- `eab4d48d`：WMI payload 保持 uint8_t 指针视图（pdata 原类型是 void *）。

移植 sam 的 WMA 队列/worker、native mgmt descriptor 所有权、coherent DMA、
peer/vdev 确认回调、频道序列化、退出事务、SSR 恢复与 stop latch。
保持 peach 的全局 RX 入口、Radiotap 输入/严格管理帧限制、同频道幂等处理、
probe/auth 默认 flags=0 及 deauth/disassoc wrong-key 规则。
保留原有全局模式禁止新接口的检查，无需添加 sam 的并发模式/LPC 等无关改动。

helper 动态选取固件范围内空闲 ID，创建 STA，等待 START 后创建 self-peer；
单播队首换目标前等旧 TX 完成，再删除/创建目标 peer；START/peer/STOP/DELETE
均等待确认，不用固定睡眠代替固件结果。
TX 限制为允许主动发送的 2.4/5 GHz 20 MHz；宽信道为 RX-only。
日志包含 owner/helper，新增 inject_stats、inject_tx_status 参数区分提交/完成/状态。

九项主机 ASan/UBSan 测试通过（不是手机测试）：Radiotap、TX worker/queue 故障、
固件状态分类、SSR、退出事务、频道读取/设置失败/并发/恢复结果。
证据：`/root/pt/op13-sam-global-20260916/host-tests.json` 与各测试日志。
构建时尚无 helper 固件及空口验证；之后收到用户 Probe 成功回报，见文末。
完整回调/DMA 生命周期与其他场景仍待验证。

已导出 0008、0009 邮件补丁并更新合并补丁与 README。
九个邮件补丁及两项合并应用方案均从 4d69a3ed 重放到相同完整 tree：
`864b886f3ca7ae6d8c2924aaf3359906a92ca9d2`。
证据：`/root/pt/op13-sam-global-20260916/patch-replay.json`。
上述为构建前补丁记录；随后包目录更新至 v6，收尾增加文档补丁 0010，见文末。

## 本轮唯一完整构建

2026-09-16 09:22:42 UTC 已启动：
`RECOMPILE_KERNEL=1 ./kernel_platform/oplus/build/oplus_build_kernel.sh sun perf`

执行/证据目录：`/root/pt/op13-sam-global-20260916`。
日志 `build.log`，起始 `build-start.json`，结束后 `build-result.json`。
外层脚本 tee 可能掩盖内部错误，务必检查 kernel、WLAN platform、qcacld、安装及
DT 合并各阶段；不以 wrapper 返回 0 单独判断成功。
不自动重试。完整构建结束后报告并停下；后续已按明确指令直接使用本轮 dist
完成三模块副本 strip/打包，不重复编译。

## 构建最终结果

本轮唯一完整构建成功，09:22:42–09:34:07 UTC，11 分 25 秒。
wrapper 返回 0；全部必要阶段齐全，日志未发现编译失败；34 个变更文件构建前后哈希一致。
新的 `qca_cld3_peach_v2.ko` 为 513,179,424 字节（未 strip），
Build ID `cc13d725ff0b78cb272c54643bc9d88187862483`，
已从产物符号表确认包含 `wma_inject_ensure_tx_vdev`。
`cfg80211`、`mac80211` 的未变动构建产物由统一构建缓存复用，Build ID 与 v5 相同，
不能把它们的旧 mtime 解释为本轮 qcacld 未更新。

按用户约定在完整构建后报告并停下。本轮未重复构建，也未部署或运行手机测试。

## v6 strip/打包结果

使用统一构建 dist 的三模块副本执行 `/usr/bin/llvm-strip --strip-debug`，并完成
架构、debug section、Build ID、模块元数据/导入 CRC 存在性、ZIP 条目和完整性校验。
这不等于覆盖所有依赖的跨模块 CRC 比较。未加入 CNSS。

- 包：`/root/pt/oplus/ksu/op13_nethunter_ksu-peach-native-global-v6-integrated.zip`
- SHA-256：`0ce6a9200601feba5ae9e92006bf2235d264cabd97b361011c19cbbc8899308a`
- `cfg80211.ko`：2,070,456 bytes，SHA-256 `488c2a9d2d737c3ccb3168b96a55a9a145b619a0185f759a1948a30f18f3c626`
- `mac80211.ko`：1,963,888 bytes，SHA-256 `6a519c28239e0c209963372fc9b45368e146928f26c2b21de134c63fbae5c66d`
- `qca_cld3_peach_v2.ko`：19,776,432 bytes，SHA-256 `61266594e59947b8f1d5bc7830d90542685ad0f1fb46149efb35ef845606c83f`

证据：`/root/pt/op13-sam-global-20260916/package-v6.json`。v6 使用 sam-derived
internal STA TX helper 的全局实现说明；旧 v5 ZIP 保留但不代表当前实现。

## 用户真机验证收尾（2026-09-16）

用户在 v6 包上运行：

```text
aireplay-ng --test wlan0
Injection is working!
Found 3 APs
channel 1: 29/30 (96%), 25/30 (83%), 11/30 (36%)
```

这是本轮第一条明确的空口证据：全局 `wlan0` 在 2.4 GHz 信道 1 上，广播及定向
Probe 请求/响应链路已工作。三台 AP 的响应率不同，不能单凭此输出归因于驱动故障。
该结果尚未覆盖 auth/deauth/disassoc、其他频道/频段、重复启停、长时间灌帧或 SSR。
用户输出未附已加载模块 Build ID、`inject_stats`、`inject_tx_status` 或独立抓包；
本次没有由 agent 远程操作设备。

下一步以 v6 为固定基线，先做短时重复 Probe，并在前后采集：

```sh
cat /sys/module/qca_cld3_peach_v2/parameters/inject_stats
cat /sys/module/qca_cld3_peach_v2/parameters/inject_tx_status
```

然后验证同频道重复 `monstart`、`monstop` 后重进，以及切到另一允许的 20 MHz 频道
再 Probe；这些结果稳定后再扩大到 auth/deauth，并保留原始 dmesg。无需先改驱动或
重新编译。

## 收尾提交与产物状态

`cd811a615772f4c144118f6215ab0d8972544959` 仅更新内核文档的真机验证记录，
运行时代码保持 v6 构建提交 `eab4d48d`。已导出
`exported/0010-v6-device-probe-validation.patch` 并更新合并补丁。
十封邮件补丁和两项合并方案经独立临时 index 重放，完整 tree 都等于
`34ce32b2deb9ea48195477ef764c877498b72cb8`，与当前源码 HEAD 一致。
证据：`op13-sam-global-20260916/patch-replay-closeout.json`。

工作区长期记录存于 `MEMORY.md`，由 `AGENTS.md` 引导读取；原始用户输出在
`oplus/说明/验证/op13-v6-probe-20260916.txt`，后续安排在
`oplus/说明/op13_v6_next_validation.md`。没有改 Codex 内部记忆数据库。

收尾只读检查发现：原目录 v6 ZIP 已不存在，原因未知；同名 SHA 文件及三模块副本
仍在。没有重新构建、打包或操作手机，交付哈希沿用已存的打包证据。
内核仓库已有的 `.repo`、构建缓存、子仓库状态和 `oplus_modules_variant.bzl`
差异保留在工作区，未纳入本次文档提交。

## v6 后续真机检查与用户确认

用户后来明确授权连接手机测试，之前仅打包阶段“不操作手机”的记录属于历史。
已核对 v6 三模块文件哈希和加载 Build ID，完成 1/6/11/149 频道 Probe、40/80 MHz
Beacon RX、重复启动、down/up、完整退出重进、普通 Wi-Fi 连接/扫描与输入格式检查。
授权热点 Redmi K20 Pro 在 161 频道 Probe 30/30，认证收到 AP status 0 回复。
最终 accepted/submitted/completed=1134，DISCARD=0，NO_ACK=552；无超时/在途残留，
DMA 池分配/释放 5/5。结束时 con_mode=0、Wi-Fi 关闭，模块仍匹配 v6。

agent 的三帧单播 deauth/disassoc 分别得到 NO_ACK，三帧广播 deauth 得到 OK；
没有独立观察客户端断线。用户随后自行测试并确认“单播和广播都没问题”，记录为
用户另行实测通过，不将其混作 agent 当时抓包的结论。
完整结果见 [真机报告](op13_v6_runtime_20260916.md)，原始证据在
`/root/pt/op13-v6-runtime-20260916/`。本轮没有修改驱动、重新编译或重打包。

下一步两项问题：WEXT 查询得到 channel -1；宽信道 RX-only 下 qdisc 留帧，切回
20 MHz 后旧帧被提交到新频道（复现 1057→1058，无新发包）。需修主机队列边界。

WEXT 修复已有明确来源：[sam 主补丁](../../sam/补丁/0001-wlan-native-monitor-injection.patch) 中的
`hdd_mon_wext_giwname/giwmode/siwmode/giwfreq/siwfreq/giwrange`、
`hdd_mon_wext_handler_def`，以及 `hdd_mon_mode_ether_setup()` 的
`dev->wireless_handlers` 接线；`wlan_hdd_mon_wext_set_freq()` 负责频道并发语义。
当前 peach v6 尚未移植这段；sam 的同频道确认不会等待固件，实际换频道走 nl80211。
另参考 oplus 原补丁 [0011](../补丁/qca_inject/0011-fix-wext-for-qcamonitor.patch) /
[0012](../补丁/qca_inject/0012-fix-wext+waittime.patch)，当前路线仍以 sam 为主。

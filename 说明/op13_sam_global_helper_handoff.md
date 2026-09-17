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

## v6 后续源码修改（未完整构建）

用户随后要求盘点入记忆并开始修改源码。内核仓库 `cd811a61` 之上的工作区已实现：

- 按 sam 接入 WEXT handlers/接线，支持模式、名称、频道、频率表查询及同频道
  20 MHz 确认。查询复用 peach 的已确认频道读取，并与 nl80211 共用频道锁；
  实际换频道仍只走 nl80211，WEXT 不在 RTNL 下等待固件。
- RX-only/不可发状态让主机队列消费丢弃；运行中的 helper 满队列继续使用背压。
  真正换频道及失败 helper 重试前，以 RTNL trylock 获得一个短主机队列事务，
  通过内核 `dev_deactivate()` 等待并清空 qdisc，carrier-off 保持停用状态。
  WMA 的 host_blocked 阻止切换期间 reopen 或绕过 qdisc 的发送；固件等待前
  已释放 RTNL。成功/失败出口均解除 gate，carrier-on 由 linkwatch 恢复空队列。
  RTNL 争用在改变 helper 前返回 EBUSY；已经工作的同频道确认保留 helper/队列。

11 项主机 ASan/UBSan 检查通过，含新加 WEXT、主机 qdisc 场景与已有回归。
主机 qdisc 测试执行生产 HDD/WMA 函数，内核网络原语使用模型；尚不证明手机上
实际调度及空口行为。日志在 `/root/pt/op13-wext-qdisc-20260916/`。
仍需下一次构建后复测 WEXT 不加 `--ignore-negative-one`、80 MHz 留帧复现场景、
普通背压和频道启停；SSR/长时间压力/160 MHz 仍未完成真机验收。
5 GHz 149/161 Probe 已有成功证据，之前回复将整个 5 GHz TX 列为未验收不准确。

本次未启动统一完整构建、未操作手机、未重打包。源码改动尚未提交，正式导出补丁
仍为 v6 的十封补丁（至 0010）；不能用旧补丁重放来声称包含本次工作区修复。

## v7 完整构建与 strip/打包

用户随后授权完整构建，2026-09-16 14:47:27–14:59:02 UTC 唯一一轮 `sun perf`
统一构建成功，历时 11 分 35 秒；构建结束已报告并停止，没有连续构建。
核对所记录的 11 个源码/测试/说明文件，构建前后哈希一致。
用户再授权 strip/打包，已对本轮 dist 的三模块副本执行 `llvm-strip --strip-debug`。
cfg80211/mac80211 由统一构建缓存复用，qcacld 更新为下列 Build ID。

- 包：`oplus/ksu/op13_nethunter_ksu-peach-native-global-v7-integrated.zip`
- 大小：7,061,780 bytes
- SHA-256：`3a32b8975076861d43285b0bab25c7a8f92e79cefe6da7e614eab851e12401f2`
- qcacld Build ID：`6f765b5dc0aeaafd1b5c71d23b95ca612ca153dd`
- strip 后三模块大小：cfg80211 2,070,456；mac80211 1,963,888；qcacld 19,784,112 bytes。

验证 ARM64 relocatable ELF、无 debug section、所有已分配 ELF 段/模块元数据/
导入 CRC section 保持原值；Build ID note 与原件及包内 `.note` 二进制逐字节一致。
确认 WEXT 和 host_blocked 等新增符号存在；ZIP CRC、逐文件内容及脚本执行权限
检查通过，恰含 cfg80211/mac80211/qca_cld3_peach_v2 三模块，不含 CNSS。
常规包目录也已更新至 v7。原始构建模块未 strip。

证据：`/root/pt/op13-wext-qdisc-20260916/package-v7.json`、`build-result.json`。
v7 尚未部署或真机验证；源码仍为 `cd811a61` 加未提交工作补丁，正式邮件补丁集
仍至 0010，不能将旧导出补丁当作 v7 源码。没有启动第二轮构建。

## v7 用户安装后的真机回归

用户随后明确授权测试，2026-09-16 15:47:59–15:57:49 UTC 完成。已安装文件及
加载三模块 notes 均匹配 v7。两项针对性修复通过：WEXT 正确读出频道，aireplay
不加 `--ignore-negative-one` 三轮均 30/30；40/80 MHz 各送 17 帧后 qdisc 为空，
回切 20 MHz 没有旧帧补发，另发一帧能准确 +1。40/80 MHz 保存了 224/63 个 Beacon。

1/6/11/149 收到 Probe 回应；36 无空口证据，161 本轮只有 Beacon。重复启动、
down/up、完整退出重进通过；普通 Wi-Fi 自动连接/IP/扫描正常。128 帧短突发全部
完成，峰值62后排空，没有证明 NETDEV_TX_BUSY 分支或长期稳定性。
最终 accepted/submitted/completed343、OK253、NO_ACK90、DISCARD0，超时/在途/
残留0，池2/2。已恢复初始 con_mode0、Wi-Fi关闭，v7三模块留载。

首轮直接 chroot 缺少 sys/proc/dev 挂载，aireplay 被驱动按错误 Radiotap 拒绝；
独立 mount namespace 补齐环境后原命令30/30。后续测试复用证据目录的 `mounted.py`，
不要直接进入未准备好的 chroot 就作驱动结论。完整结果与限制见
[v7 真机报告](op13_v7_runtime_20260916.md)，原始证据在
`/root/pt/op13-v7-runtime-20260916/`。本轮未修改驱动/构建/重打包，v7源码提交和
正式补丁仍待整理；SSR、长期跳频压力及160 MHz监听仍未验收。

## v7 源码与补丁收尾完成

用户要求继续后，核对 v7 构建快照的 11 个文件全部逐字节一致，原样提交为
`c79b6f6541583b148354b731691dc92caeac6adb`。随后只更新源码验证文档，提交为
`524a92c084f36b8301bac24ae3920c610b53fac0`。五项受影响的独立主机检查再次通过，
没有重新构建、操作手机或重打包。

正式补丁新增 `exported/0011-monitor-wext-and-host-queue.patch` 与
`0012-v7-device-regression-results.patch`，合并补丁和 series/README 已同步。
从基线 `4d69a3ed` 分别重放十二封邮件补丁以及“构建接入+合并补丁”，完整 tree
均为 `422e8a00abf0521a986311b445c014a946a822ef`，与源码 HEAD 相同。
证据为 `/root/pt/op13-wext-qdisc-20260916/patch-replay-v7.json` 及
`closeout-source-match.json`。之前“源码未提交/补丁仅至0010”均为历史状态。

v7 ZIP 保持原 SHA-256；包内 BUILD_INFO 是打包时快照，后续提交及真机结果以
本交接和 v7 真机报告为准。下一步可安排 SSR、长时间跳频压力及 160 MHz 接收
专项；当前基础功能回归已完成，无需为本次提交再编译。

## v7 专项验证：跳频通过，SSR 自动恢复失败

用户随后明确授权“做吧”，2026-09-16 16:44:46–17:08:00 UTC 完成扩展验证。
601.3 秒、517 个频道阶段、6864 帧全部完成；40/80/160 MHz 共送入1768帧，
qdisc 保持空、回到20 MHz无旧帧补发。最大completion312 ms、used峰值62，
无超时/残留，backpressure0；这是10分钟排空后跳频，未覆盖并发换频/长时间耐久。
160 MHz在36/40/44/48主频道中心5250设置成功，均未抓到帧，RX仍不能验收。

一次空闲SSR未通过：CNSS DIAG触发firmware assert，固件重新ready，但
`hdd_start_all_adapters()`报monitor restart -22，60秒后helper仍state0。
手动重新设频只恢复TX completion，没有RX；完整monstop→monstart后抓到
271个Beacon、3个Probe回应。没有再触发带流量SSR，也没有重启整机。

对照sam/实际源码和v7 ELF DWARF，发现monitor重建走station初始化，union中的
monitor.center_freq1(offset16)会被station.roam_profile.SSIDs.SSIDList覆盖；
另SSR monitor分支漏了正常启动中的hdd_enable_monitor_mode/DP启用。
前者与-22、后者与只恢复TX无RX吻合；尚无运行中context/具体失败分支的直接观测，
修复仍待实施。下一步优先修完整monitor SSR重建，补union/恢复链回归，不能只重试helper。

普通Wi-Fi自动连接/IP/VALIDATED/扫描通过，最后con_mode0、Wi-Fi关闭，三模块
仍v7；6876帧完成/固件OK，池3/3，无残留，关闭后超过两分钟复查正常。
开测时曾发现系统在上轮结束后卸载qcacld，本轮重新加载已安装v7并等待接口就绪。
完整报告见[v7专项结果](op13_v7_extended_20260916.md)，
持久证据见[摘要](验证/op13-v7-extended-20260916.json)，原始证据在
`/root/pt/op13-v7-extended-20260916/`。本轮未改驱动、构建或重打包；
内核HEAD仍524a92c0，正式邮件补丁仍至0012。

## SSR 源码修复完成，待完整构建和真机验证

用户随后要求“继续修ssr”，源码已提交为`30426bf8a3e1b57596ee741086e2c491617c58d1`。
继续保留sam的helper/队列/回调与DMA生命周期，修正其前面的peach监听重建：

- monitor context从station/AP union独立出来，保留所有link的freq/width/center/PHY。
- 全局SSR重建依次创建vdev、关闭idle PS/PS/WoW、注册RX、启用DP monitor、恢复
  频道及总线策略。分阶段报错，全部成功才允许后续TX restore；中心频率也需匹配。
- STA共用初始化不覆盖monitor WEXT handlers；宽信道恢复消费丢弃路径，不创建TX
  helper；IFF_UP原本关闭时保留主机暂停状态。
- FW down时不等不可能返回的monitor UP/STOP确认，保留SME会话清理、引用与正常
  vdev销毁。发送请求入队失败也不等待；没有放宽DMA回收边界。

13项主机ASan/UBSan检查通过。新增回归提取生产context结构与STA初始化，旧union
负向对照实际触发频道参数断言；还覆盖两link、20/40/80/160、无频道、恢复各阶段
失败、WEXT、固件停止/活动/请求失败，以及TX恢复门槛与暂停接口。固件/DP为桩，
不能替代上机。运行记录在`/root/pt/op13-ssr-fix-20260916/`。

正式补丁新增`0013-monitor-ssr-rebuild.patch`，series及合并补丁同步。两条路线
从4d69a3ed重放后完整tree都为`a3215426a531edd58dd9636b262da0296bac76e4`，
等于源码HEAD。持久证据见[SSR修复校验](验证/op13-ssr-fix-20260916.json)。
本轮没有完整构建、打包、部署或手机操作，已交付v7 ZIP哈希不变且不含修复。
下一步经用户明确启动后仅进行一轮统一构建；结束先报告并停下。之后再strip/打包、
上机先验空闲SSR，再验带流量SSR、WEXT/RX/宽信道队列和普通Wi-Fi恢复。

## v8 SSR 修复统一构建与打包完成

用户随后明确要求“构建吧，构建完打包”：已完成一轮统一sun perf构建并交付v8，
包含`30426bf8`的0013 SSR重建修复。构建2026-09-16T18:10:43+00:00至
2026-09-16T18:22:15+00:00，耗时692.45秒，全部阶段完成；
源码前后哈希一致，WLAN工作区干净。三模块副本strip-debug，原始产物保留，未加CNSS。
包：`oplus/ksu/op13_nethunter_ksu-peach-native-global-v8-integrated.zip`，7064244字节，SHA-256：
`ec6361da53d4a14c89c98492b5f3bbe84796d7b6abed57f39b625276cd2dff3a`。
qcacld Build ID：`ff0f34e4ea4eba64f788c495b3a9eabb401d3157`。
ELF装载段/元数据/CRC/Build ID与raw一致、ZIP完整性/权限/三模块范围均通过。
之前13项主机检查对应源码哈希未变；v8尚未部署/上机，SSR修复效果仍待真机验收。
证据`op13-ssr-build-20260916/`和`oplus/说明/验证/op13-v8-build-20260916.json`。
本轮没有启动第二次构建；下一步先验空闲SSR，再验带流量SSR与RX/WEXT/普通Wi-Fi。
下方“等待构建”和“v7为最新包”为历史状态。
本次用户同时授权构建和打包，因此单轮成功后接着strip/打包，没有重新构建。

## v8 SSR 真机验证及用户补测收尾（2026-09-17）

开测三模块文件及加载notes与v8一致。四次SSR（20 MHz空闲、发包期间、40 MHz
RX-only、管理员down）均恢复，四次boot ID不变。空闲及发包期间恢复后有Beacon/
Probe回应，WEXT正常；故障时32帧在途、30帧排队，保留池在reset后回收，
reset_reclaims=1。40 MHz收到207 Beacon，无qdisc留帧或切回20 MHz补发。
管理员down标志保留，up后频道恢复。普通Wi-Fi连接/IP/VALIDATED/扫描及退出重进
通过，重进后定向Probe20/30。

用户主动拔线导致最后down/up命令未执行，不能据此判断设备崩溃。用户要求仅自己
补这一项，并回报频道1/20、WEXT正常、tdgcxh Probe23/30；按用户补测结果记录通过。
粘贴未含down/up命令或身份复核。最新state2，207/177/145，queued/inflight/used/
retained/timeouts/stale全0；dropped30、drained32是SSR累计清理，pool6/5是活动池。
failed60中先前30对应NO_ACK，新增30缺TX状态明细，不能归因为SSR失败。

最终仍是用户的监听会话，未执行monstop/最终身份复核。本轮不再加测，不改源码、
补丁内容或ZIP，也未编译。80/160 MHz SSR、160 MHz RX、并发换频和长期耐久性
不在本轮结论内。完整结果见[v8报告](op13_v8_runtime_20260917.md)及
[证据摘要](验证/op13-v8-runtime-20260917.json)。历史“v8待真机验证”以本节为准。

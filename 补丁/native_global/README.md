# peach_v2 原生全局监听与注入实验线

一加 13 的硬件是 `peach_v2`。本线使用高通 `QDF_GLOBAL_MONITOR_MODE`
（`con_mode=4`）及原生 `wlan0` monitor vdev。2026-09-16 按用户要求，
以 sam 完整实现为主要依据：monitor 负责 RX/主机所有权，内部 STA helper 负责 TX。
全局监听不要求直接由 monitor vdev 发包；旧 oplus 补丁仅作参考。
2026-09-16 v6 已有用户真机证据：`aireplay-ng --test wlan0` 在 2.4 GHz
信道 1 报告 Injection working，三个 AP 的定向 Probe 响应为 29/30、25/30、11/30。
这确认该次 Probe 空口链路工作；其他管理帧、频道切换、长时间稳定性及 SSR 仍待验证。

## 应用与统一编译

源码基线为 `4d69a3ed9a176152e85580352723c308f29cbfcb`。在内核仓库根目录：

```sh
git apply /root/pt/oplus/补丁/qca_inject/0001-add-qcacldko.patch
git apply /root/pt/oplus/补丁/native_global/0001-peach-v2-native-global-monitor.patch
RECOMPILE_KERNEL=1 ./kernel_platform/oplus/build/oplus_build_kernel.sh sun perf
```

第一项只接入 `prepare_vendor.sh` 的 WLAN 统一构建，必需保留。第二项是当前
原生全局实现的合并 diff。不要叠加旧 `qca_inject/0002-0017`。

也可以从同一基线按 `exported/series` 顺序使用 `git am` 应用十个邮件补丁。
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

v6 的实际构建源码仍是 `eab4d48d`。当前十封邮件补丁和两项合并应用方案已从
基线重放，完整 tree 均为 `34ce32b2deb9ea48195477ef764c877498b72cb8`，与
`cd811a61` 一致。证据见 `op13-sam-global-20260916/patch-replay-closeout.json`。

构建日志必须包含 kernel、WLAN platform、WLAN qcacld、Installing WLAN modules
及 DT 合并完成阶段；外层脚本退出码不能单独证明内部成功。

KSU 固定流程：统一构建 → 从 `kernel_platform/out/msm-kernel-sun-perf/dist/`
取 `cfg80211.ko`、`mac80211.ko`、`qca_cld3_peach_v2.ko` → 副本执行
`llvm-strip --strip-debug` → 放入 `vendor_dlkm/lib/modules/` → 打包。
v6 已完成一次用户侧真机 Probe 验证；agent 不自动部署或重复运行手机测试。每次完整
构建结束后先报告并停下，不自动二次构建。
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

九项主机 ASan/UBSan 检查通过，详见
`/root/pt/op13-sam-global-20260916/host-tests.json`。
源码文档 `qcacld-3.0/docs/peach-native-injection.md` 列出全部测试与限制。
本轮成功构建结果见 `/root/pt/op13-sam-global-20260916/build-result.json`。
当前 KSU v6 ZIP 使用 helper 版实现；旧 v5 ZIP 属于直接 monitor TX，不能作为当前基线。
已交付 v6 SHA-256 为 `0ce6a9200601feba5ae9e92006bf2235d264cabd97b361011c19cbbc8899308a`。
收尾时本地 ZIP 已不在原目录，模块副本和校验文件仍在；本轮未重打包。

用户提供的 v5 probe/auth 日志返回 DISCARD，flags=1 对照也未解决已记录的认证帧。
此次优先修正发送端点与生命周期，不把 flags 当作上述故障的修复。
`submitted`、`completed`、固件 OK 和独立空口接收是不同证据，不可混为成功。

后续设备验证优先顺序：固定 v6 包，短时重复 Probe 并采集 `inject_stats` /
`inject_tx_status`；验证 `monstop`/重进及允许的 20 MHz 换频道后再 Probe；最后再扩大
到 auth/deauth，并保留原始 dmesg。暂不改驱动或重新编译。

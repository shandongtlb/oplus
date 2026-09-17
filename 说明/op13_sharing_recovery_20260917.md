# OPPO 平板共享退出恢复修复（2026-09-17）

用户报告的 `monstart → 开启与平板网络共享 → monstop → 再开启共享仍失败` 已在
旧脚本上完整复现，修复后同一手机、同一 OPPO Pad Mini 的完整顺序通过。退出后
持续观察超过 8 分钟，P2P 接口没有重建，网关 ping 18/18 成功。手机已安装三个
控制脚本热修，仍运行 v8.2 的三个模块。没有改内核、重新构建或重打 ZIP。

## 故障证据

以下时间为 UTC，手机日志为 UTC+8。原始记录在
`/root/pt/op13-sharing-debug-20260917/`，含设备私有日志，仅留本地；入库摘要及
文件哈希见 [验证记录](验证/op13-sharing-recovery-20260917.json)。

- 12:30 故障现场：cfg80211/mac80211 为 payload，qcacld 已消失，没有 WLAN 接口。
  用户确认“切内核”指 KSU 切回 stock；12:32 用户再次手动热切，不能算作我们的
  最小恢复成功。随后记录正常共享基线，平板网关 ping 3/3。
- 12:39:49 旧 monstart 进入全局模式，但始终扫描仍开启。原 STA_SCAN 接口被
  驱动模式切换注销，Android 记录接口掉线和 WifiSelfRecovery。
- 12:43:24 用户在监听中请求共享，supplicant 连续建立 P2P 接口失败。
- 12:44:39 旧 monstop 已返回 managed；12:44:43 ColorOS 却报告 driverReady=false、
  ERROR_DRIVER 并安排延迟恢复。12:45:40 共享重试实际上完成关联/握手/建组，
  12:45:43 延迟 wifiDriverReload 又卸载 qcacld，重新加载失败、服务 exit 1。
  因此单看 monstop 成功或短暂 P2P 建组都会漏掉故障。

绑定到 vendor 路径的三个 payload 模块文件带 `system_file` 标签，bind 保留源 inode
标签。手机实际 SELinux 策略中，`vendor_modprobe` 对 `system_file` 没有 read/module_load
许可，对 `vendor_file` 则有。stock 模块使用 `vendor_file`；系统恢复服务正以
`vendor_modprobe` 执行卸载/加载脚本。这解释了为何 KSU 能加载、系统恢复却失败。

12:48 在 qcacld 已卸载的故障状态，仅修正三个模块文件标签为 `vendor_file`，再启动
系统原有 wifiDriverReload：服务 exit 0，加载的 Build ID 与 v8.2 相符，接口恢复。
这是实际服务的验证，未切 stock、未改 SELinux 策略。此前 runcon 尝试在执行 shell
前即失败，不作为 loader 成功证据。旧 coldreset 路径另有 init exec Permission denied，
不能把该脚本当成已成功执行；实际掉驱动链路由延迟 DriverReLoad 日志确认。

## 修复

主要参考 sam `ksu/s25u_oneui8_nethunter/global_monitor_control.sh` 的首次状态保存、
进入前关闭、退出后恢复生命周期，并针对 ColorOS 的实际接口所有权和恢复流程适配。
旧 oplus 的接口/复位防护作参考；保留现有驱动的全局模式建接口拒绝逻辑。

- `monitor_control.sh` 首次进入前原子保存 boot ID、实际 Wi-Fi 开关与始终扫描；
  关闭并等待 Android 的 NumActiveModeManagers=0，再进入 con_mode=4。运行时开关
  优先于可能过期的 wifi_on。重复 monstart 保留首次快照。
- monstop 及启动失败回滚在 managed 就绪后重新交接并恢复原设置，确认框架状态。
  失败保留记录，monstatus 显示 RESTORE PENDING，可重试 monstop；新启动不会覆盖
  未恢复快照。旧 boot 的快照不会应用到新 boot。
- 安装和 bind 前给三个模块文件设置 `vendor_file`，让系统原生恢复服务也能读入。
  标签准备失败保留当前 bind；热切遇到 bind 准备失败则在卸载 WLAN 栈前返回错误。

手机替换 monitor/bind/stack 三个脚本，在已有控制锁内原子安装；原件保存在
`/data/local/tmp/op13-sharing-backup-20260917/`。customize 安装脚本只改本地源码，
下次打包安装时生效。手机当前 module.prop 仍标 v8.2，不能据此认为它与旧 ZIP
脚本逐字节相等。

## 修复后验收

12:55:13 新 monstart 保存原状态“Wi-Fi 关、始终扫描开”，扫描关闭、Android 所有者
归零，信道 1 / state=2。12:57:01 用户再次在监听中请求共享，P2P 请求被拒绝。
12:58:05 新 monstop 正常返回，恢复扫描=1、Wi-Fi 关闭、Android active manager=1，
恢复记录移除。12:58:07 平板 P2P 连接成功。

至 13:06:06：p2p0 ifindex 始终为 64，实际收发增长，四轮 ping 12/12、重新 apply
bind 后 3/3、共享占用入口拦截后 3/3，合计 18/18。新 bind 脚本应用没有卸载模块或
打断共享；共享运行时 monstart 正确拒绝且模式、ifindex、扫描设置不变。没有再次
出现本次关注的 WifiSelfRecovery、ERROR_DRIVER、PlanExecute、DriverReLoad 日志。
修复后这段启停未发生 SSR/模块卸载；boot ID 整轮未变。

最终 con_mode=0、state=0，queued/inflight/used/retained/stopping/timeouts 全为 0，
pool_allocs=pool_frees=1，三模块加载 notes 和文件哈希仍匹配 v8.2。日志采集停止，
未遗留本次 logcat/发包/抓包进程；保留用户已开启的正常平板共享。

主机 20 项 monitor 测试通过，覆盖四组 Wi-Fi/扫描开关、重复进入保存、恢复失败重试、
框架不交出接口时拒绝切模式；身份/标签/卸载边界测试通过。变更脚本 sh 语法及
monitor/bind 的 ShellCheck warning 及以上检查通过，git diff --check 通过。stack/customize 仍有原先
的 ShellCheck 提示，不宣称所有脚本零告警。

本次真机只覆盖原设置 Wi-Fi 关/扫描开的一轮完整复现与恢复、8 分钟观察和真实
P2P 数据通路；没有把主机四组设置测试当作四组真机验收，也没有重新验证注入、
深度休眠、长期共享或重启安装。监听期间共享不能建立是全局模式约束，退出后
应可恢复。后续若打包，只需带入这些脚本及现有三模块，无需为本修复重编内核。

## 产物边界

内核 HEAD `7387a666ebca7d4a22676c350e4c598ffd831d1f`，源码补丁至 0015 不变。
旧 v8.2 ZIP SHA-256 `51d2b905dd351cb31d740ed6fd13bc5d34b60393e08e0515b8b108e85fd3f76c`
未变，**不含此次共享修复**。脚本提交和完整重放记录见
[脚本补丁说明](../补丁/ksu_scripts/README.md)。

# KSU 脚本补丁与共享恢复修复

2026-09-17 已完成本轮干净基线完整重放及当前源码核对，见
[最终审计报告](../../说明/op13_patch_closeout_20260917.md)。

此目录应用到 `oplus` 仓库，不能应用到内核仓库。本次修复 Android Wi-Fi/扫描交接及
vendor loader 读取绑定模块所需的文件标签。手机已热修；真实 OPPO Pad Mini 共享
完整复测通过，退出后观察超过 8 分钟、ping 18/18。报告见
[共享恢复记录](../../说明/op13_sharing_recovery_20260917.md)。

内核仍为 `7387a666`，源码补丁至 0015，三个运行模块来自 v8.2 统一构建。
**现存 v8.2 ZIP 未重打，不含本次共享修复。**

基线：`af83a9622345530317a8c4b3cde61131477a292d`
目标实现/实测提交：`1df6bcae8d4e5827a56bcde78512f37bb022d8b6`
目标完整 tree：`ebd7174b74e7acbd5d5956e870d9de463877dbb2`

从干净基线按 `series` 依次应用 0001–0009：

```sh
git am /path/to/ksu_scripts/000[1-9]-*.patch
```

已有此前脚本目标 `0793727` 时只应用 0005–0009；已有本轮开始前
`d4f61418db866ca2bbd9fa1e97ee69b6495bb78f` 时只应用
`0009-fix-sharing-framework-and-vendor-labels.patch`。

另一种方式是在同一干净基线应用 `combined-monitor-control.patch`；不要与邮件序列
叠加。两种方式均覆盖完整 `oplus` tree，包含中间导出记录、源码补丁及包元数据，
不只是生产脚本。内核源码需另按 `../native_global/README.md` 的步骤应用。

九封邮件已逐个实际 git am，每个完整 tree 与原提交相等，重放工作区干净；合并
补丁另从基线应用到独立临时 index，完整 tree 同样相等。证据在
[重放校验](verification-sharing-recovery.json)。合并 diff 内含历史邮件补丁的上下文
空行，git apply 会报告这些嵌套补丁的空白提示；没有使用 --whitespace=fix，以保留
原目标字节。完整 tree 一致性由 Git 对象哈希验证。

本 README、本轮新导出文件和重放记录属于后续导出提交；为避免补丁递归包含自身，
目标 tree 明确止于上述实现/实测提交。它们不改变目标脚本、内核或模块。
`verification.json`、`verification-runtime-fixes.json` 保留为早期目标的历史记录，
当前目标以 `verification-sharing-recovery.json` 为准。

# OnePlus 13 当前补丁入口

当前使用 peach_v2 原生全局路线，以 sam 为主要实现依据。内核与 KSU 脚本属于
两个仓库，需要分别处理；不要把旧并发路线补丁混入当前全局路线。

| 仓库 | 干净基线 | 正式实现目标 | 应用说明 |
| --- | --- | --- | --- |
| oneplus13-kernel-b | `4d69a3ed` | `7387a666` | [内核补丁](native_global/README.md) |
| oplus | `af83a962` | `1df6bca` | [KSU 控制脚本补丁](ksu_scripts/README.md) |

内核从基线应用 qca_inject/0001（统一构建接入），再应用
native_global/0001-peach-v2-native-global-monitor.patch；或按 exported/series
使用十五封邮件，二选一。不要叠加 qca_inject/0002–0017。

KSU 从其基线应用 ksu_scripts/series 的九封邮件；或使用
ksu_scripts/combined-monitor-control.patch，二选一。已有 d4f6141 只需 0009。
最新的 Android Wi-Fi/扫描交接及共享恢复修复在 KSU 0009 内，内核不需要新补丁。

2026-09-17 最终审计已实际重放上述四条路线，完整 tree 一致、重放工作区干净，
并核对当前受控源码及所有子项目版本。[核对报告](../说明/op13_patch_closeout_20260917.md)
解释了构建残留的备份/还原和验证范围。

如果要求 oplus 连最后的说明、补丁导出记录也与收尾 HEAD 完全相等，请使用仓库外
[完整快照](../../op13-final-audit-20260917/delivery/README.md)。其 verification.json
固定最终提交和 tree，SHA256SUMS 校验文件；它覆盖完整受控仓库，不与正式 KSU
实现序列重复应用。快照外置是为了避免递归包含自身。

本次没有改内核功能，没有重新构建或生成安装 ZIP。旧 v8.2 ZIP 不含共享热修，
源码、手机热修脚本和旧安装包应按各自的提交/哈希区分。

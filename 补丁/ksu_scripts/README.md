# KSU 脚本补丁与真机修复

此目录应用到 `oplus` 仓库，不能应用到内核仓库。内核仍为3b8463c2，
三个运行模块仍来自v8统一构建。现存v8.1 ZIP不含本轮mksh/ColorOS脚本修复。

基线：`af83a9622345530317a8c4b3cde61131477a292d`
目标提交：`079372701e03382d9e968f8751b0d02333e431a8`
目标完整tree：`a4aa77c02f267330645a6c06fc6b681ffc63543b`

从基线依次应用四封补丁（两个中间提交保存此前导出记录和v8.1包元数据）：

```sh
git am /path/to/0001-monitor-control-guards.patch \
       /path/to/0002-record-control-guard-export.patch \
       /path/to/0003-record-v8.1-package.patch \
       /path/to/0004-fix-mksh-lock-and-wifi-state.patch
```

已有v8.1打包提交 `0b9e13ade8cb5a1c4857c8c9e0de9e527dfe7701` 时只应用0004。
也可从同一基线应用 `combined-monitor-control.patch`；不要与四封序列叠加。

四封逐个实际git am，每个完整tree与原提交相等，重放工作区干净；合并补丁
另从基线应用到临时索引，最终完整tree相等。证据 `verification-runtime-fixes.json`。
当前导出文件及此README属于后续导出记录，避免补丁递归包含自身，目标tree明确
止于上述实现/实测提交。原 `verification.json` 仅是0001的历史验证。

报告 `../../说明/op13_v8_1_runtime_20260917.md`：两处脚本修复已部署并验证；
压力换频固件assert与scheduled-scan警告仍待查，不能称为全功能无故障。

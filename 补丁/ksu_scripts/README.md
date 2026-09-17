# KSU 脚本保护补丁

此目录属于 `/root/pt/oplus` 脚本仓库，不应用到内核仓库，也不叠加到
`native_global/0001-peach-v2-native-global-monitor.patch`。

- 基线：`af83a9622345530317a8c4b3cde61131477a292d`
- 脚本提交：`3bfce6641c35b490adfddc0cba47bb19007c4639`
- 目标完整 tree：`d11cce5f9ded3789719670b24388a5d68bc86de6`

从上述脚本仓库基线应用：

```sh
git am /path/to/0001-monitor-control-guards.patch
```

补丁包含脚本、17项主机回归和相关说明。临时索引从基线应用后完整tree与脚本提交相同，
详见 `verification.json`。本目录自身的导出记录是后续文档提交，不属于补丁目标tree。

内核源码/模块未变，不需要重编；新脚本尚未打包或部署，现有v8 ZIP保持原样。

# 2026-09-16 调试与 v5 打包状态

前一会话在 OnePlus 13 上复现了 aireplay 能发现 AP、但没有成功探测回复的问题。
安装目录的 v4 与内存里实际加载的模块最初不一致；重载并核对 Build ID 后，
又发现 Kali 缺少 `/sys` 挂载，aireplay 因驱动识别失败而发送裸帧。
补挂 `/sys` 后，Radiotap 管理帧到达 WMI，但固件返回 DISCARD。
这些结果不能证明空口注入成功。

v5 包含实际监听频道查询、重复设同频道跳过重启、TX flags 对照参数、
deauth/disassoc 保留 wrong-key flag，以及 ARM64 `current` 宏冲突的编译修复。
KSU 切换通过三模块的 Build ID notes 验证运行版本，卸载失败会直接报错。
`aireplay_test.sh` 在需要时为 Kali 临时挂载 `/sys`，结束后清理该次挂载。

源码提交：`2cbfb99ff1848517870b7cf2b3e6d8a8a7a82014`。
统一构建于 2026-09-16 05:29:46–05:35:45 UTC 完成。v5 只完成副本 strip、
静态校验与打包；本轮按用户最新要求没有推送、安装、切换或真机测试。
静态校验结果及模块哈希见 `BUILD_INFO.txt`。

后续需要验证实际模块版本、频道查询、probe flags 对照与退出监听的恢复行为。
看到 AP 仅证明接收；不能把 WMI 提交或主机发出帧的本地抓包当成独立空口证据。

# OnePlus 13 原生全局监听 v5 交接（2026-09-16）

## 用户要求

不得连续编译；每次完整构建结束（包括失败）先报告并停下，等待下一轮明确继续。
本轮用户最新要求为「strip 完打包」，替代此前「测试一次」的要求；没有部署或真机测试。
此约定也保存在工作区 `/root/pt/AGENTS.md`。

## 构建与包

源码提交：`2cbfb99ff1848517870b7cf2b3e6d8a8a7a82014`。
统一构建已于 2026-09-16 05:29:46–05:35:45 UTC 完成。
`current` 宏冲突修复包含在该次构建中；本轮未重新编译。

包：`/root/pt/oplus/ksu/op13_nethunter_ksu-peach-native-global-v5-integrated.zip`。
大小：7,044,875 字节。
SHA-256：`b48980978b74206efcc5c26c56e4a5c9c32855434149ec4442fe691facc0faa5`。

仅包含统一构建的 cfg80211、mac80211、peach_v2 三个模块，对副本执行
`llvm-strip --strip-debug`，原始产物保留。没有加入 CNSS 模块。

| 模块 | strip 后字节数 | Build ID |
| --- | ---: | --- |
| cfg80211.ko | 2,070,456 | `40533847cea5b0e9aeac19849b37f1dfc7dc9f44` |
| mac80211.ko | 1,963,888 | `abacfa26d25bc862a3383f8f21c4f3eccd333778` |
| qca_cld3_peach_v2.ko | 19,731,088 | `f99c48339d6efd71557d863cceb02cd8ebac51c9` |

## 校验

- 模块与统一 dist、最终 out/dist、已安装 vendor_dlkm 产物的来源哈希一致。
- 副本 strip 后无调试节，导入/导出符号 CRC、Build ID 均保留。
- 150 项跨模块 CRC 和 1078 项内核/平台 CRC 匹配；27 项其他依赖符号未覆盖静态检查。
- `module_build_ids/*.note` 已加入 ZIP 并与包内 ELF note 逐字节核对。
- 七个邮件补丁和两项合并补丁均在临时基线上重放，11 个文件与源码提交逐字节一致。
- Shell 语法、本地模块身份/旧标记/卸载失败回归、ZIP 内容和权限检查通过。
- 旧 v4 的 ASan/UBSan 结果仅作为历史记录，本轮没有重新运行会启动编译器的回归。

证据：`/root/pt/op13-native-global-hardening/build-current.log`、`build-current.rc`、`validation.json`、
`validation-summary.json`、`patch-replay.json`、`package.json`。

## 待后续真机验证

v5 尚未加载；不能宣称修复了固件 DISCARD 或注入已成功。
前一会话已证实 v4 的模块版本不一致、Kali 缺少 /sys，以及补挂后 probe 的
固件 DISCARD。下次用户要求测试时，从核对三模块实际 Build ID、监听频道查询、
probe flags 对照和退出恢复继续，不应为测试重新编译。

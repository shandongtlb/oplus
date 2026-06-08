# inject 补丁集

本目录包含基于「Initial kernel source import」(`a22d7e3fc`) 之后的全部改动历史，
由 `git format-patch` 导出，共 12 个补丁，按编号顺序应用。

## 应用方法

在内核源码根目录（与 `kernel_platform/`、`vendor/` 同级）执行：

```sh
# 方式一：保留提交历史
git am oplus/补丁/inject/*.patch

# 方式二：仅打补丁，不产生提交
git apply oplus/补丁/inject/*.patch
```

> 已验证：从 `a22d7e3fc` 基线按序应用全部补丁后，生成的代码树与当前 `HEAD`
> (`61a76083e`) 完全一致。

## 补丁清单

补丁文件名即「序号-提交信息」：

| 序号 | 提交信息（即文件名） |
| --- | --- |
| 0001 | 添加 WLAN 平台和 qcacld 模块构建及安装功能 |
| 0002 | 第一阶段（监听模式使能） |
| 0003 | 修复监听口子1 |
| 0004 | 修复监听口子2 |
| 0005 | 修复监听口子3 |
| 0006 | 添加注入功能v1 |
| 0007 | 添加注入功能v2 |
| 0008 | 添加注入功能v3 |
| 0009 | qcacld: fix monitor channel reporting for aireplay-ng |
| 0010 | qcacld: improve injection debugging - reset counters per session |
| 0011 | 修复wext |
| 0012 | 修复wext+竞态窗口收窄 |

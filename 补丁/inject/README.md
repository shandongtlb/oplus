# inject 补丁集

本目录包含基于「Initial kernel source import」(`a22d7e3fc`) 之后的全部改动历史，
由 `git format-patch` 导出，共 10 个补丁，按编号顺序应用。

## 应用方法

在内核源码根目录（与 `kernel_platform/`、`vendor/` 同级）执行：

```sh
# 方式一：保留提交历史
git am oplus/补丁/inject/*.patch

# 方式二：仅打补丁，不产生提交
git apply oplus/补丁/inject/*.patch
```

> 已验证：从 `a22d7e3fc` 基线按序应用全部补丁后，生成的代码树与原始 `main`
> (`139505246`) 完全一致。

## 补丁清单

| 序号 | 文件 | 原始提交信息 |
| --- | --- | --- |
| 0001 | add-wlan-platform-qcacld-build-install.patch | 添加 WLAN 平台和 qcacld 模块构建及安装功能 |
| 0002 | phase1-enable-monitor-mode.patch | 第一阶段（监听模式使能） |
| 0003 | fix-monitor-1.patch | 修复监听口子1 |
| 0004 | fix-monitor-2.patch | 修复监听口子2 |
| 0005 | fix-monitor-3.patch | 修复监听口子3 |
| 0006 | add-injection-v1.patch | 添加注入功能v1 |
| 0007 | add-injection-v2.patch | 添加注入功能v2 |
| 0008 | add-injection-v3.patch | 添加注入功能v3 |
| 0009 | fix-monitor-channel-reporting-aireplay.patch | qcacld: fix monitor channel reporting for aireplay-ng |
| 0010 | improve-injection-debugging-reset-counters.patch | qcacld: improve injection debugging - reset counters per session |

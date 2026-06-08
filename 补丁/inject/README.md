# inject 补丁集

本目录包含基于「Initial kernel source import」(`a22d7e3fc`) 之后的全部改动历史，
由 `git format-patch` 导出，共 13 个补丁，按编号顺序应用。

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

| 序号 | 文件名 |
| --- | --- |
| 0001 | add-qcacldko.patch |
| 0002 | add-monitor.patch |
| 0003 | fix-monitor-1.patch |
| 0004 | fix-monitor-2.patch |
| 0005 | fix-monitor-3.patch |
| 0006 | add-inject.patch |
| 0007 | fix-inject-1.patch |
| 0008 | fix-inject-2.patch |
| 0009 | fix-monitor-channel.patch |
| 0010 | improve-injection.patch |
| 0011 | fix-wext-for-qcamonitor.patch |
| 0012 | fix-wext+waittime.patch |
| 0013 | NETHUNTER: Enable broadcast deauth injection via WMI test flag.patch |

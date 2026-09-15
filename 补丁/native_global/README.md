# peach_v2 原生全局监听 v1

这是一套从 OnePlus 13 `peach_v2` 源码重新开始的实验补丁，目标是使用高通
`QDF_GLOBAL_MONITOR_MODE`（`con_mode=4`）。全局模式下驱动直接创建 `wlan0`
monitor adapter；补丁没有隐藏 STA，也没有 helper vdev 或 vdev 槽位分配。

## 应用和统一编译

补丁基于当前 OnePlus 13 `peach_v2` 同步源码（本地验证基线为 `4d69a3ed`）：

在内核源码根目录按 `series` 中的顺序应用：

```sh
git apply /root/pt/oplus/补丁/qca_inject/0001-add-qcacldko.patch
git apply /root/pt/oplus/补丁/native_global/0001-peach-v2-native-global-monitor.patch
RECOMPILE_KERNEL=1 ./kernel_platform/oplus/build/oplus_build_kernel.sh sun perf
```

旧 `qca_inject/0001-add-qcacldko.patch` 是必需的构建接入补丁，只修改
`prepare_vendor.sh`，与虚拟 STA/helper 无关。它通过主构建的 `KERNEL_KIT`、
`build_opts.txt` 和 WLAN 平台符号表构建 qcacld，并归集到同一次构建的 dist。
不要应用旧 `qca_inject/0002-0017`。已有 Image 时总脚本可能跳过主内核生成，
因此重做整包时设置 `RECOMPILE_KERNEL=1`。

日志必须出现 WLAN platform、WLAN qcacld、Installing WLAN modules 的完成阶段。
外层脚本通过 `tee` 输出，退出码不能单独证明内部构建成功；还要检查日志中的
错误、阶段完成标记和三模块产物。不要用另外手写的 Bazel 命令补齐缺失产物后打包。

KSU 发布流程固定为：统一构建成功 → 从
`kernel_platform/out/msm-kernel-sun-perf/dist/` 取下面三个 4K 模块 → 在副本上
执行 `llvm-strip --strip-debug` → 放进 KSU 的 `vendor_dlkm/lib/modules/` → 打包
→ 真机调试：

- `cfg80211.ko`
- `mac80211.ko`
- `qca_cld3_peach_v2.ko`

检查三者的 vermagic、符号 CRC 和 SHA256，记录到包内 `docs/BUILD_INFO.txt`。
CNSS 可作为构建依赖生成，但不放入 KSU，不替换手机的 CNSS 平台栈。

KSU 模块中的 `monitor_control.sh` 已改为写入
`/sys/module/qca_cld3_peach_v2/parameters/con_mode`，并通过 `wlan0` 操作频道，
不再创建 `wlan0mon`。

## 当前实现

- `con_mode=4` 下给原生 monitor adapter 打开 TX 队列。
- 发送入口解析基本 Radiotap；也暂时接受裸 802.11 帧。
- WMI 管理帧使用私有 descriptor 区间并从完成事件回收 DMA buffer。
- 64 个槽位全部占用时向网络栈返回 `NETDEV_TX_BUSY`，不按超时猜测固件已经停止 DMA。
- 发送只尝试当前 monitor vdev；不会创建、选择、重启或销毁任何额外 vdev。

## 尚未验证

这是 v1 实验实现，必须在 peach_v2 真机上确认：

1. `con_mode=4` 的 RX filter 和 Radiotap 收包；
2. monitor vdev 上 WMI TX 的 completion 状态及空口效果；
3. firmware 丢 completion 后的背压和完整 WLAN 重启恢复；
4. 退出全局模式后 Wi-Fi、热点和 P2P 的恢复。

如果 peach_v2 固件对 monitor-vdev TX 返回 DISCARD，这套设计会保留该事实，
不会偷偷退回虚拟 STA；下一步应研究 firmware 已支持的全局 monitor 发送入口。

## 已导出的邮件补丁

从 peach_v2 源码提交精确导出、可用于审阅和移植：

- `exported/0001-build-integrate-wlan-qcacld.patch`
- `exported/0002-peach-v2-native-global-monitor.patch`

源码提交为 `d20c69af` 和 `2fa5ca62`。`series` 保持与旧补丁目录兼容；新导出文件反映实际提交内容。

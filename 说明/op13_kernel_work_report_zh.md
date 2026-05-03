# OnePlus 13 内核改动工作报告

## 1. 任务背景

本轮工作围绕远端 NUC 上的 `/root/oneplus13-kernel-b` 源码树展开，目标包括：

1. 连接并验证远端编译环境。
2. 分析并验证 OnePlus 13 `sun perf` 内核编译链。
3. 将 `vendor/qcom/opensource/wlan` 的 Bazel 构建接入主构建流程。
4. 将运行机实际使用的 `peach_v2` 对应 `qcacld3` 模块纳入 `vendor_dlkm` 产物链。
5. 研究并应用 Nethunter 的 wifi injection 补丁。
6. 启用 `rt3070l` 对应的 `rt2800usb/rt2x00usb` USB 无线网卡支持。
7. 导出补丁、提交 git、回退局部尝试改动，并做多轮编译验证。

本文按时间顺序整理全过程，并总结关键结论。

---

## 2. 远端连接与环境确认

### 2.1 连接信息

- 主机：`39.99.33.163`
- 端口：`7222`
- 用户：`root`
- 私钥文件：`key2.pem`
- 私钥口令：`wangyang19980416`

### 2.2 遇到的问题
---

## 3. 源码树与编译链分析

### 3.1 源码树结构结论

这份树不是单一 kernel 仓，而是 OnePlus 在 Qualcomm/Kleaf 基础上的完整工程：

- `kernel_platform/common`
- `kernel_platform/msm-kernel`
- `vendor/oplus/...`
- `vendor/qcom/...`

Manifest 指向：

- `oneplus_13_b`
- `oneplus/sm8750_b_16.0.0_oneplus_13`

内核版本：

- `Linux 6.6.89`

### 3.2 构建命令解析

用户给出的命令：

```bash
./kernel_platform/oplus/build/oplus_build_kernel.sh sun perf
```

实际流程：

1. `oplus_build_kernel.sh`
2. `oplus_setup.sh`
3. `kernel_platform/build/android/prepare_vendor.sh sun perf`
4. `build_with_bazel.py`
5. Kleaf/Bazel 产出 `dist`
6. 复制到 `device/qcom/sun-kernel`

### 3.3 `sun perf` 含义

- `sun`：目标平台
- `perf`：用户向、量产/性能测试构建
- 跟 `consolidate` 不同，`perf` 更接近正式产物

---

## 4. 首次完整编译验证

### 4.1 防断线方案

由于 SSH 连接不稳定，所有完整编译均通过远端 `tmux` 启动：

- 编译脚本写到远端 `LOGDIR/*.sh`
- 运行于独立 `tmux` session
- 标准输出写入 `LOGDIR/*.log`
- 退出码写入 `LOGDIR/*.status`

这样即使本地连接断开，远端编译仍会继续。

### 4.2 第一次完整编译结果

最早的 `sun perf` 完整编译成功，状态文件最终写出：

- `EXIT_CODE:0`

产物落盘包括：

- `Image`
- `dtbo.img`
- `vendor_dlkm.img`
- `device/qcom/sun-kernel/*`

这证明基础编译链是通的。

---

## 5. WLAN Bazel 构建接入

### 5.1 目标

希望在编译 `msm` 内核时，顺带编译：

- `vendor/qcom/opensource/wlan/platform`
- `vendor/qcom/opensource/wlan/qcacld-3.0`

### 5.2 调查结论

现有树中已经自带 Bazel 目标，不需要额外新建规则：

- `//vendor/qcom/opensource/wlan/platform:sun_perf_modules_dist`
- `//vendor/qcom/opensource/wlan/qcacld-3.0:sun_perf_all_modules_dist`

### 5.3 接入方式

修改了：

- `kernel_platform/build/android/prepare_vendor.sh`

在模块准备阶段后新增：

1. `wlan/platform` Bazel 构建
2. `wlan/qcacld-3.0` Bazel 构建
3. 将产出拷贝到：
   - `kernel_platform/out/msm-kernel-sun-perf/dist`
   - `device/qcom/sun-kernel/vendor_dlkm`

### 5.4 中途踩到的问题

#### 问题 1：第一次脚本插入重复块

由于远端脚本替换过程中有一次半成功插入，`prepare_vendor.sh` 出现了重复片段。

#### 解决办法

- 重新读取目标行号。
- 清理错误插入块。
- 保留一份语法正确的最终版本。
- 用 `bash -n` 校验脚本。

### 5.5 手工验证

手工跑 `build_module.sh` 发现：

- 不带 `TARGET_BOARD_PLATFORM=sun` 时，容易回退到 legacy make
- 带上 `ENABLE_DDK_BUILD=true` 和 `TARGET_BOARD_PLATFORM=sun` 后，WLAN Bazel 目标可以成功编译

### 5.6 `peach_v2` 机型收敛修正

`qcacld-3.0` 一次会产出多个 SoC/射频变体：

- `qca_cld3_peach.ko`
- `qca_cld3_peach_v2.ko`
- `qca_cld3_qca6750.ko`
- `qca_cld3_wcn7750.ko`
- `qca_cld3_kiwi_v2.ko`

初始安装补丁曾假设当前目标为：

- `kiwi_v2`

但设备端后续运行时检查确认：

- `/proc/modules` 实际加载的是 `qca_cld3_peach_v2`
- `/vendor_dlkm/lib/modules` 同时存在 `peach` / `peach_v2` / `kiwi_v2`
- `modules.load` 中也列入了多个 `qca_cld3_*` 变体

因此后续修正为：

1. 安装阶段只保留：
   - `qca_cld3_peach_v2.ko`
2. 安装前清理旧的 `qca_cld3_*.ko`
3. 在 `vendor_dlkm.modules.load` 中移除旧的 `qca_cld3_*` 项后，只追加：
   - `vendor/qcom/opensource/wlan/qcacld-3.0/qca_cld3_peach_v2.ko`

### 5.7 最终结果

完整重编后确认：

- `cnss2.ko`
- `icnss2.ko`
- `cnss_nl.ko`
- `cnss_prealloc.ko`
- `cnss_utils.ko`
- `cnss_plat_ipc_qmi_svc.ko`
- `wlan_firmware_service.ko`
- `qca_cld3_peach_v2.ko`

都进入了：

- `kernel_platform/out/msm-kernel-sun-perf/dist`
- `device/qcom/sun-kernel/vendor_dlkm`

对应补丁：

- `op13_wlan_peach_v2.patch`

---

## 6. Nethunter wifi injection 补丁研究与应用

### 6.1 原始参考

参考补丁：

- `add-wifi-injection-4.14.patch`

来源：

- Kali Nethunter kernel builder

### 6.2 对比当前 6.6 树的结论

原补丁相关内容分两类：

#### 已经在当前树中存在的逻辑

以下 4 处，当前 `msm-kernel` 实际已经自带或等价存在：

1. `net/mac80211/cfg.c`
   - monitor 允许改信道
2. `net/mac80211/tx.c`
   - injected frame 不重写 seq / no-ack
3. `net/mac80211/tx.c`
   - monitor 模式不覆盖 QoS
4. `net/wireless/chan.c`
   - monitor channel 设置放宽

#### 仍需补的驱动 hunk

原补丁里的 USB 驱动部分在当前树中未应用：

1. `drivers/net/wireless/zydas/zd1211rw/zd_mac.c`
2. `drivers/net/wireless/realtek/rtl818x/rtl8187/dev.c`

### 6.3 实际应用的内容

#### `zd1211rw`

修改内容：

1. `set_rx_filter()` 改为使用：
   - `CR_RX_FILTER`
   - `CR_SNIFFER_ON`

2. RX 错误判断放宽：

```c
if ((status->frame_status & ZD_RX_ERROR) ||
    (status->frame_status & ~0x21))
```

3. `SIGNAL_UNSPEC` 改为：

```c
SIGNAL_DBM
```

#### `rtl8187`

修改内容：

- 在 monitor 场景下不再无条件打 `RTL818X_TX_DESC_FLAG_MOREFRAG`

### 6.4 编译验证

完整编译通过，状态文件最终：

- `EXIT_CODE:0`

### 6.5 提交

在 `kernel_platform/msm-kernel` 子仓中提交：

- commit: `056bfd3eaf88`
- message: `wireless: add usb wifi injection driver tweaks`

### 6.6 导出补丁

导出两类补丁：

1. 汇总补丁：
   - `op13_wifi_injection_bundle.patch`

2. 仅“尝试给 GKI/KMI 增加 LED 符号可见性”的临时补丁：
   - `op13_rt3070_ledsym_only.patch`

---

## 7. `rt3070l` USB 网卡支持启用

### 7.1 目标

启用 `rt3070l` 对应的 Ralink `rt2800usb/rt2x00usb` 驱动。

用户给出的参考提交：

- `ebd67fe4a91f0053ce2bd1ec022b40c295a74783`

以及后续修复参考：

- `c2cb5a0837f6149f29c984c6ad152998b39a5514`

### 7.2 首轮修改

修改文件：

1. `arch/arm64/configs/vendor/sun_perf.config`
2. `drivers/net/wireless/ralink/rt2x00/Kconfig`
3. `sun.bzl`

#### 配置项新增

在 `sun_perf.config` 中加入：

- `CONFIG_WLAN_VENDOR_RALINK=y`
- `CONFIG_RT2X00=m`
- `CONFIG_RT2800USB=m`
- `CONFIG_RT2800USB_RT33XX=y`
- `CONFIG_RT2800USB_RT35XX=y`
- `CONFIG_RT2800USB_RT3573=y`
- `CONFIG_RT2800USB_RT53XX=y`
- `CONFIG_RT2800USB_RT55XX=y`
- `CONFIG_RT2800USB_UNKNOWN=y`

#### 模块清单新增

在 `sun.bzl` 中加入：

- `rt2800lib.ko`
- `rt2800usb.ko`
- `rt2x00lib.ko`
- `rt2x00usb.ko`

### 7.3 首轮失败

第一次编译报错：

```text
modpost: "led_classdev_suspend" [rt2x00lib.ko] undefined!
modpost: "led_classdev_resume" [rt2x00lib.ko] undefined!
```

### 7.4 第一种解决方案：关掉 `RT2X00_LIB_LEDS`

参考三星做法，将：

- `drivers/net/wireless/ralink/rt2x00/Kconfig`

中的：

```config
config RT2X00_LIB_LEDS
    bool
    default y if ...
```

改为：

```config
default n
```

#### 中间踩到的问题

把

```config
# CONFIG_RT2X00_LIB_LEDS is not set
```

写进 `sun_perf.config` 后，`olddefconfig` / `check_merged_defconfig()` 报：

```text
ERROR! Defconfig fragment did not apply as expected
-RT2X00_LIB_LEDS n
```

#### 原因

`RT2X00_LIB_LEDS` 是隐藏符号，靠 defconfig 强行写 `# ... is not set` 不稳定。

#### 解决办法

- 不在 `sun_perf.config` 写这个隐藏项。
- 直接修改 `rt2x00/Kconfig` 默认值。

### 7.5 第二轮成功

清理产物、清理 Bazel 缓存后重新完整编译，最终：

- `EXIT_CODE:0`

且真正产出：

- `rt2x00lib.ko`
- `rt2x00usb.ko`
- `rt2800lib.ko`
- `rt2800usb.ko`

同时进入：

- `kernel_platform/out/msm-kernel-sun-perf/dist`
- `device/qcom/sun-kernel/vendor_dlkm`

### 7.6 导出补丁与提交

导出补丁：

- `op13_rt3070l_enable.patch`

提交：

- commit: `bb0d8f037ce5`
- message: `wireless: enable rt3070 usb support`

---

## 8. 关于 `led_classdev_suspend/resume` 的进一步调查

### 8.1 用户提出疑问

用户指出：

- `msm` 模块编译时可能获取的是 `common/GKI` 符号
- 即使 `msm` 源码里有符号，mixed build 下仍可能报 undefined

### 8.2 调查结果

这个判断是对的。

#### 证据 1：这是 GKI-based mixed build

`build.config.msm.perf` 中有：

- `GKI_BUILD_CONFIG=common/build.config.gki.aarch64`

#### 证据 2：源码里函数存在且导出

`drivers/leds/led-class.c` 中：

- `led_classdev_suspend`
- `EXPORT_SYMBOL_GPL(led_classdev_suspend);`
- `led_classdev_resume`
- `EXPORT_SYMBOL_GPL(led_classdev_resume);`

#### 证据 3：最终 `Module.symvers` 里没有这两个符号

检查：

- `dist/Module.symvers`
- `device/qcom/sun-kernel/Module.symvers`
- `common` 侧 `Module.symvers`

均没有：

- `led_classdev_suspend`
- `led_classdev_resume`

#### 证据 4：`common` LED 配置是开的

`common` 侧 `.config` 中有：

- `CONFIG_NEW_LEDS=y`
- `CONFIG_LEDS_CLASS=y`
- `CONFIG_LEDS_TRIGGERS=y`

所以：

- 不是 LED 子系统没开
- 而是 mixed build 给模块可见的符号集合里没有这两个 LED 符号

### 8.3 第二种解决方案：尝试把 LED 符号加入 ABI 列表

尝试在：

- `android/abi_gki_aarch64_qcom`

中加入：

- `led_classdev_resume`
- `led_classdev_suspend`

同时恢复：

- `RT2X00_LIB_LEDS` 的默认自动开启逻辑

### 8.4 验证结果

完整编译通过，最终：

- `EXIT_CODE:0`

这说明：

- 正确做法不是重复 `EXPORT_SYMBOL`
- 而是让这两个符号进入 mixed build 可见的 ABI/KMI 列表

### 8.5 最终状态处理

用户后来提出：

- 不想换内核
- 只想加载模块

基于这一点，最终更保守、兼容的做法是：

- 导出“仅 ABI/LED 尝试”的补丁留档
- 回退这次未提交的 ABI/LED 额外尝试
- 保留已经提交且可稳定工作的 `rt3070 usb support`

保留下来的留档补丁：

- `op13_rt3070_ledsym_only.patch`

---

## 9. 关键文件清单

### 9.1 WLAN / `peach_v2` 接入

- `kernel_platform/build/android/prepare_vendor.sh`
- `op13_wlan_peach_v2.patch`

### 9.2 wifi injection

- `kernel_platform/msm-kernel/drivers/net/wireless/zydas/zd1211rw/zd_mac.c`
- `kernel_platform/msm-kernel/drivers/net/wireless/realtek/rtl818x/rtl8187/dev.c`
- `op13_wifi_injection_bundle.patch`

### 9.3 rt3070l

- `kernel_platform/msm-kernel/arch/arm64/configs/vendor/sun_perf.config`
- `kernel_platform/msm-kernel/drivers/net/wireless/ralink/rt2x00/Kconfig`
- `kernel_platform/msm-kernel/sun.bzl`
- `op13_rt3070l_enable.patch`
- `op13_rt3070_ledsym_only.patch`

---

## 10. 最终结论

### 10.1 已稳定完成的部分

1. 远端编译环境已打通
2. `sun perf` 基础内核编译可稳定成功
3. WLAN Bazel 构建已接入主流程
4. 运行机实际使用的 `peach_v2` 对应 `qcacld3` 模块已正确纳入 `vendor_dlkm` 方案
5. Nethunter wifi injection 驱动补丁已应用并通过完整编译
6. `rt3070l` 对应 `rt2800usb/rt2x00usb` 模块已成功编译并产出

### 10.2 关于 `RT2X00_LIB_LEDS`

如果目标是：

- 不换内核
- 只挂模块

那么更稳的方案是：

- 维持 `RT2X00_LIB_LEDS=default n`

原因：

- mixed build 实际模块符号可见性受 GKI/KMI 限制
- 即使源码里有函数，也不代表当前运行内核可解析模块依赖

### 10.3 关于 LED 符号可见性

已经验证：

- 把 `led_classdev_suspend/resume` 加入 ABI 列表确实可能让编译通过

但如果不刷入对应运行内核，只保留模块，不一定对最终设备加载有帮助。

所以：

- 只挂模块：建议保守方案，关 LED 依赖
- 全量换内核/boot：可考虑保留 ABI 符号修复路线

---

## 11. 当前建议

如果后续继续推进，建议按以下优先级：

1. 若目标是设备实用性：
   - 保持 `rt3070l` 当前已提交方案
   - 不启用 `RT2X00_LIB_LEDS`

2. 若目标是进一步完善：
   - 单独验证 `rt3070l` 模块在设备端 `insmod/modprobe` 的实际行为
   - 检查 `vendor_dlkm.img` 是否已打包包含对应模块
   - 再决定是否保留 ABI/LED 额外导出路线

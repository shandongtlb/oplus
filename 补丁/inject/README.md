# 一加 13 (peach_v2) NetHunter 注入补丁集

为一加 13 (peach_v2) 内核启用 monitor 模式和帧注入功能，支持 NetHunter 无线安全测试。

## 功能特性

- ✅ **Monitor 模式**：qcacld-3.0 驱动完整 monitor 支持
- ✅ **帧注入**：mac80211 + qcacld 注入通路，支持 aireplay-ng
- ✅ **广播 deauth**：通过 WMI test flag 绕过固件限制，稳定踢出全部 client
- ✅ **vdev_restart 优化**：解决 AP 扫描时递减问题

## 适用基线

- **目标仓库**：OnePlus 13 内核源码 (peach_v2)
- **基线 commit**：`0de73fc2` 或相同的一加 13 16.0.7.201 同步代码
  ```
  Synchronize code for OnePlus CPH2649_16.0.7.201(EX01) ...
  Based on QCOM release TAG: AU_LINUX_KERNEL.PLATFORM.4.0.R1.00.00.00.061.111
  ```

## 应用步骤

从基线 `0de73fc2` 开始，按序应用全部 15 个补丁：

```bash
cd /path/to/oneplus13-kernel
git checkout 0de73fc2   # 或你的基线 commit

# 应用 0001-0015（完整功能 + 稳定性修复）
for i in $(seq 1 15); do
  git am /path/to/补丁/inject/$(printf "%04d" $i)-*.patch
done
```

**说明**：
- `0001`：构建系统配置（WLAN 平台模块）
- `0002-0012`：monitor/inject 核心功能
- `0013`：广播 deauth 注入（关键功能）
- `0014`：r8 - vdev_restart 优化
- `0015`：r8.1 - 注入稳定性修复（超时回收 + generation 防 UAF）**强烈建议应用**
- `0004` 包含**跨仓库改动**：
  - `vendor/qcom/opensource/wlan/qcacld-3.0/` （驱动层）
  - `kernel_platform/msm-kernel/net/mac80211/` 等（内核侧）
  
  这些改动会一起通过 `git am` 应用。如果你的 msm-kernel 是独立仓库，需要手动提取 0004 里的内核部分单独打补丁。

## 验证

应用完成后，最终 HEAD 应该是：

```bash
git log --oneline -5
# (0015) peach_v2: r8.1 - 注入稳定性修复(超时回收 + generation 防 UAF)
# ae508b19 peach_v2: r8 - vdev_restart优化解决AP递减问题
# ca172e31 NETHUNTER: Enable broadcast deauth injection via WMI test flag
# (0002-0012 的提交)
# 2f347c6e 临时
```

## 补丁清单

| 序号 | 功能 | 状态 |
|------|------|------|
| 0001 | WLAN 平台构建 | ✅ 稳定 |
| 0002-0012 | monitor + inject 核心 | ✅ 稳定 |
| 0013 | 广播 deauth 注入 | ✅ 已验证，可踢出全部 client |
| 0014 | r8 - vdev_restart 优化 | ✅ 稳定 |
| 0015 | r8.1 - 注入稳定性修复 | ✅ 已验证，连续灌 1 万+帧无卡死 |

## 使用示例

### 开启 monitor 模式

```bash
# 创建 monitor 接口
iw phy phy0 interface add wlan0mon type monitor
ip link set wlan0mon up

# 设置频道（例如 2.4G channel 6）
iw dev wlan0mon set freq 2437

# 验证
iw dev wlan0mon info
```

### 广播 deauth 攻击

```bash
# 踢出目标 AP 的所有 client（-a 指定 AP MAC）
aireplay-ng --deauth 10 -a <AP_MAC> wlan0mon

# 查看注入日志
dmesg | grep -iE "inject|deauth" | tail -20
```

## 构建

应用补丁后，按一加官方构建流程编译内核和模块：

```bash
./build/build_module.sh modules
```

生成的 `wlan.ko` 包含全部注入功能。

## 故障排查

### 补丁应用失败

- **"does not exist in index"（0004）**：确认基线正确（0de73fc2），且 msm-kernel 结构与补丁匹配
- **冲突**：检查基线是否已包含部分改动，必要时先 `git reset --hard 0de73fc2`

### Monitor 无法开启

- 检查 `iw phy phy0 info` 是否列出 `monitor` 接口类型和并发组合
- 确认 wlan.ko 版本：`modinfo wlan.ko | grep vermagic`

### 注入无响应

- 确认 monitor 口已 `up`：`ip link set wlan0mon up`
- 查看注入日志：`dmesg | grep -iE "inject|wma_inject|completion"`
- 检查 WMI test mode 是否启用（0013 自动开启）

### 广播 deauth 不稳定（第一次能发、第二次卡死）

- **务必应用 0015 (r8.1)**：这正是该补丁修复的问题。r8/r9 在 aireplay 爆发
  灌帧时会因固件静默丢帧而 wedge（第二次运行卡死、或发包但目标不掉线）。
  r8.1 用"超时回收 + generation 防 UAF"根治，连续灌 1 万+帧、连测七八次稳定。
- 应用 0015 后，`dmesg | grep build=` 应显示 `mon-inject-r8.1-stable`
- 健康判据：`dmesg` 里 `completed + reclaimed == submitted`、`dropped` 接近 0
- 检查目标 AP 频道与 monitor 频道是否一致

## 已知限制

- **单播 deauth**：固件会 DISCARD 未知 peer 的单播帧，只有广播 deauth 可用
- **频道切换**：部分场景下频道报告可能不准确，使用前确认 `iw dev wlan0mon info` 显示正确频道

## 贡献者

- 原始开发：shandongtlb
- 辅助实现：Claude Opus 4.8

## 许可

与 Linux 内核相同许可（GPL-2.0）。

---

**最后更新**：2026-06-11  
**测试设备**：OnePlus 13 (CPH2649) 16.0.7.201(EX01)  
**内核版本**：Linux 6.6 + QCOM AU_LINUX_KERNEL.PLATFORM.4.0.R1  
**稳定版本**：r8.1 (0015) - 广播 deauth 稳定性已根治，连续灌 1 万+帧、连测七八次无卡死

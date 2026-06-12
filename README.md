# OnePlus 13 NetHunter 开发记录

一加 13 内核的 NetHunter monitor 模式和帧注入功能实现记录。

## 项目结构

```
oplus/
├── 补丁/                 # 内核补丁
│   ├── qca_inject/           # 【主线】内置 WiFi monitor + 注入补丁集（0001-0015）
│   │   ├── 0001-0015.patch   # monitor + inject + 稳定性修复
│   │   └── README.md         # 补丁应用说明
│   ├── 1.op13_bt_arsenal_msm_only.patch    # 蓝牙 arsenal 工具支持
│   ├── 2.op13_usb_arsenal_gki.patch        # USB arsenal 通用支持
│   ├── 3.op13_rt3070l_enable.patch         # 启用 RT3070L 外置 USB 网卡
│   ├── 4.op13_add-wext-for-rt3070l.patch   # 外置卡 wext shim（aireplay/iwconfig 兼容）
│   └── 5.op13_usb_zd1201_msm.patch         # 启用 ZD1201 外置 USB 网卡
├── 说明/                 # 详细技术文档（实战记录、突破分析等）
├── ksu/                  # KernelSU 模块包相关
└── README.md             # 本文件
```

> **两条线**：`qca_inject/` 是**内置 WiFi**（peach_v2 qcacld-3.0）的 monitor + 注入主线成果；
> 顶层 `1~5.*.patch` 是**外置 USB 网卡 / 蓝牙**支持（RT3070L、ZD1201、BT/USB arsenal），互相独立、按需应用。

## 功能实现

### ✅ 已完成并稳定

1. **Monitor 模式**
   - qcacld-3.0 驱动层完整支持
   - 接口创建：`iw phy phy0 interface add wlan0mon type monitor`
   - 频道设置、RX 捕获正常

2. **帧注入**
   - mac80211 内核侧注入支持（修改 tx.c、cfg.c 等）
   - qcacld WMI 注入通路（wma_mgmt.c）
   - aireplay-ng 完全兼容

3. **广播 Deauth 攻击**（0013 补丁）
   - 通过 WMI test flag 绕过固件广播限制
   - 稳定踢出目标 AP 的所有 client
   - 实战验证可用

4. **vdev_restart 优化**（0014 r8）
   - 解决 AP 扫描时 vdev 递减问题
   - 提升注入稳定性

5. **广播 Deauth 高频灌帧稳定性根治**（0015 r8.1）
   - 修复"第一次能发、第二次卡死"的注入卡死问题
   - 根因：固件静默丢弃约 3-6% 注入帧（不回完成事件）
   - 方案：超时回收（timeout-reclaim）+ desc_id 内嵌 generation 防 UAF
   - 实战验证：连续灌 2.8 万+帧无卡死，连测七八次稳定，发包后 0-4s 必断

### ⚠️ 已验证但未采用

以下功能开发过程中测试过，但因不稳定或固件限制未纳入最终版本：

1. **单播 Deauth**（r10 动态 peer）
   - 尝试在注入时动态创建 peer 让固件放行单播帧
   - 失败原因：softirq 上下文限制 + 固件仍 DISCARD 未知 peer
   - 结论：只有广播 deauth 可用，但已足够实战

2. **STA+Monitor 并存**（r11）
   - 成功解锁驱动层软件限制（policy_mgr、cfg80211）
   - 同频道下可连 WiFi + 开 monitor
   - 未采用原因：引入不稳定因素，且实战不需要（可以断 WiFi 后注入）

## 实战记录

### 测试环境

- **设备**：OnePlus 13 (CPH2649)
- **系统**：ColorOS 16.0.7.201(EX01) 
- **内核**：Linux 6.6 + QCOM AU_LINUX_KERNEL.PLATFORM.4.0.R1
- **芯片**：Qualcomm peach_v2 (可能是 SM8750)

### 成功案例

#### 1. 广播 Deauth 踢全场

```bash
# 目标：踢出 AP "Mate 60 Pro" (d6:59:e2:**:**:cd) 的所有 client
iw phy phy0 interface add wlan0mon type monitor
iw dev wlan0mon set freq 2437  # AP 所在频道
ip link set wlan0mon up
aireplay-ng --deauth 10 -a d6:59:e2:**:**:cd wlan0mon

# 结果：
# - 所有连接该 AP 的设备断开
# - dmesg 显示 completion status=0 (OK)
# - 固件成功发送广播 deauth 帧
```

#### 2. Monitor 模式接口并发验证

成功验证的接口组合（iw phy phy0 info 显示）：
- `#{ managed } <= 1, #{ monitor } <= 1` ✅
- `#{ monitor } <= 2` ✅
- 同时支持双频道 `#channels <= 2`

#### 3. STA+Monitor 同频道并存测试

```bash
# 先连 WiFi（2.4G channel 6）
# 再开 monitor 设到同频道
iw dev wlan0mon set freq 2437
ip link set wlan0mon up
# ✅ wlan0 保持连接，wlan0mon 正常工作
```

**注意**：此功能未纳入最终补丁（r11 未发布），但验证了固件支持同频道并发。

### 失败/受限案例

#### 1. 单播 Deauth 对未知 Peer

```bash
# 尝试：对特定 client 发单播 deauth
aireplay-ng --deauth 3 -a <AP> -c <CLIENT> wlan0mon

# 结果：
# - dmesg 显示 completion status=1 (DISCARD)
# - 固件拒绝发送（peer 未在固件表中）
# - 即使 r10 动态建 peer 也无效
```

**结论**：只有广播 deauth 可用，但已足够实战（踢全场）。

#### 2. 双频道 STA+Monitor 并发

```bash
# WiFi 在 2.4G channel 6 (2437MHz)
# Monitor 在 5G channel 36 (5180MHz)
# 尝试连接 WiFi → 失败，reason 8 (leaving BSS)
```

**原因**：固件不支持双频道并发，STA 连接被踢掉。实战无影响（monitor 本就跟 AP 同频道）。

## 开发时间线

- **2026-06-08**：完成基础 monitor 模式和注入功能（0001-0012）
- **2026-06-09**：实现广播 deauth（0013）、vdev_restart 优化（0014 r8）
- **2026-06-09**：探索单播 deauth（r10），验证失败
- **2026-06-10**：解锁 STA+Monitor 并存（r11），因不稳定未采用
- **2026-06-10**：回退到 r8，发布稳定版补丁集 0001-0014
- **2026-06-11**：实战暴露广播 deauth 高频灌帧卡死，根治后发布 r8.1（0015），补丁集更新为 0001-0015

## 技术细节

### 驱动层改动

- **qcacld-3.0/core/hdd/**：monitor 接口创建、配置
- **qcacld-3.0/core/wma/**：WMI 注入通路、test flag
- **qca-wifi-host-cmn/policy_mgr/**：并发策略管理

### 内核层改动

- **net/mac80211/tx.c**：尊重 IEEE80211_TX_CTL_INJECTED 标志，跳过 QoS 重写
- **net/mac80211/cfg.c**：允许 monitor 频道变更
- **drivers/net/wireless/**：rtl8187、zd1211rw 注入适配

### 关键突破点

1. **WMI test flag**（0013）：注入时设 `mgmt_params.tx_flags = 0x00000001`（`WMI_TX_SEND_FLAG_SET_WRONG_KEY`，WFA PMF 测试标志）让固件放行 monitor vdev 的广播 deauth
2. **vdev_restart 时机**（0014 r8）：在 BSS 开始前调用，避免 vdev id 递减
3. **接口组合表**：修改 cfg80211 iface_combinations 白名单
4. **超时回收 + generation**（0015 r8.1）：注入槽位池按时效区分"真背压丢弃"与"固件已丢弃回收"，desc_id 高位编入 generation 防止迟到完成误删在途 nbuf（DMA-UAF）

## 构建和使用

见 `补丁/qca_inject/README.md` 完整说明。

## 下一步可能方向

- [ ] 探索其他芯片平台（如 MT7921）的注入实现
- [ ] 研究固件逆向，寻找单播放行的可能性（见 说明/ 中的单播修复方向）

## 贡献者

- 主要开发：shandongtlb
- 技术支持：Claude Opus 4.8

---

**最后更新**：2026-06-11  
**当前稳定版本**：r8.1（广播 deauth 高频灌帧卡死已根治）  
**补丁集版本**：0001-0015

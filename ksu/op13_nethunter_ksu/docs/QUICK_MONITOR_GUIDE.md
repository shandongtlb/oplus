# Monitor Mode + Injection — 快速指南

## 使用流程
```bash
# 1. KSU 里点 Action 按钮 → nethunter (切换到打补丁的 ko)
# 2. 终端(adb shell 或 Termux root)
monstart 149        # 进 monitor + 锁 ch149(5G) → 可注入
# 或
monstart 6          # 锁 ch6(2.4G)
# 或
monstart            # 不锁频 → airodump 全频扫描

# 3. 抓包/注入
airodump-ng wlan0mon              # 抓包/扫描
aireplay-ng -9 -a <BSSID> wlan0mon   # 注入测试
tcpdump -i wlan0mon -nn           # 原始抓包

# 4. 退出
monstop             # 恢复正常 WiFi
# 5. (可选) KSU 点 Action → stock (切回原厂栈)
```

## 注入原理(OnePlus 13 特殊性)
- 不像外置 USB 网卡"开 monitor 即可注入",OnePlus 13 内置 qcacld FullMAC 固件**拒绝在 monitor vdev 上发包**(每帧 DISCARD)。
- **必须锁定信道**(`monstart <freq>`),驱动会在该信道上自动建一个**隐藏 STA helper vdev** 借道发送。
- 不锁频(`monstart` 无参数)= 只能抓包/扫描,注入无效(无 helper vdev)。

验证注入是否成功:
```bash
dmesg | grep NETHUNTER-INJ
# 看 [completion] status=0(...COMPLETE_OK) [submitted=X completed=X] 
# submitted == completed && status=0 = 注入成功
```

## 前置条件
- **关闭 P2P/Wi-Fi Direct**(手机→平板网络共享/跨设备互联/投屏),否则驱动策略禁止开 monitor。

## 信道参考
**简写(推荐)**:
- 2.4G: `1` `2` `3` `6` `9` `10` `11`
- 5G: `36` `40` `44` `48` `149` `153` `157` `161` `165`

或直接用频率 MHz:
- 2.4G: `2412`(ch1), `2437`(ch6), `2462`(ch11)
- 5G: `5180`(ch36), `5745`(ch149), `5825`(ch165)

详细文档: `MONITOR_INJECTION_USAGE.md`

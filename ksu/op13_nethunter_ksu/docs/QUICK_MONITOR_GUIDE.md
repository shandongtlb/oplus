# Monitor Mode + Injection — 快速指南

## 使用流程
```bash
# 1. KSU 里点 Action 按钮 → nethunter (切换到打补丁的 ko)
# 2. 终端(adb shell 或 Termux root)
monstart 149        # 进全局 monitor + 锁 ch149(5G)，等待真机验证
# 或
monstart 6          # 锁 ch6(2.4G)
# 或
monstart            # 不锁频 → airodump 全频扫描

# 3. 抓包/注入
airodump-ng wlan0              # 抓包/扫描
aireplay-ng -9 -a <BSSID> wlan0   # 注入测试
tcpdump -i wlan0 -nn           # 原始抓包

# 4. 退出
monstop             # 恢复正常 WiFi
# 5. (可选) KSU 点 Action → stock (切回原厂栈)
```

## 注入原理(OnePlus 13 特殊性)
- 当前实现向 peach_v2 的全局 monitor vdev 直接提交 WMI TX；固件是否接受以及实际空口发送情况尚未验证。
- 注入测试前锁定信道(`monstart <freq>`)。
- 不锁频(`monstart` 无参数)可抓包/扫描；注入需要先锁定信道。
- 这是 `peach_v2` 原生 `con_mode=4`，不会创建 `wlan0mon` 或隐藏 STA/helper vdev。

验证注入是否成功:
```bash
dmesg | grep NETHUNTER-INJ
# 对照 [submit] 与 [completion] 的 desc 和 status。
# status=0 是固件报告成功；还需要独立接收端确认空口帧。
# submitted == completed 只说明完成事件数量一致，不能单独证明发送成功。
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

构建来源和验证范围见 `BUILD_INFO.txt`。

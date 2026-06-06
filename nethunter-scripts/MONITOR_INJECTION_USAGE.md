# OnePlus 13 (peach_v2) — Monitor Mode + Packet Injection 使用说明

driver: `qca_cld3_peach_v2.ko` (build marker `mon-inject-probe-r8`, grep `dmesg | grep NETHUNTER`)

## 前置条件(重要)
开监听前必须**关闭任何活跃的 Wi-Fi Direct / P2P**,否则驱动策略会拒绝监听
(`policy_mgr_check_mon_concurrency: P2P CLIENT concurrency`, monstart 会报错并提示):
- 关闭【手机 → 平板 的网络连接共享 / OPLUS 跨设备互联】
- 关闭投屏 / Miracast / Wi-Fi 直连传输

监听期间 STA WiFi 是关闭的(由 monstart 自动 `svc wifi disable`),这是预期行为。

## 命令
```
monstart <freq_MHz>     # 进入监听并锁定信道, e.g. monstart 5745 (ch149), monstart 2437 (ch6)
monstop                 # 退出监听, 恢复正常 WiFi (无需重载模块)
```
固化在 KernelSU 模块 `system/bin/`(重启后为全局命令);也在 `/data/local/tmp/` 留有副本。

## 抓包
```
airodump-ng wlan0mon
tcpdump -i wlan0mon -nn
```
2.4G / 5G 均可(已测 ch6 / ch36 / ch149)。固定信道抓包最佳;airodump 跳频也可,
但跳频时每次换信道会重建注入 helper(~0.4s),建议注入场景锁定单信道。

## 注入
监听口设好信道后,驱动会自动在该信道上创建一个**隐藏 STA helper vdev** 作为发送端
(固件不允许直接在 monitor vdev 上发包)。之后任何经 wlan0mon 的原始帧注入都会经它发出:
```
aireplay-ng -9 -a <BSSID> wlan0mon      # 注入测试
aireplay-ng -0 5 -a <BSSID> wlan0mon    # deauth (授权测试自己的 AP)
# 或 AF_PACKET 原始套接字直接发 radiotap + 802.11 帧
```
验证注入是否被固件真正发出:
```
dmesg | grep NETHUNTER-INJ
# [submit] #N ... -> 帧已下发固件
# [completion] #N status=0(...COMPLETE_OK) [submitted=X completed=Y] -> 固件已发送 (OK=已发, DISCARD=被拒)
```
注意:`[submit]/[completion]` 日志只打前 8 帧 + 每 256 帧一次(避免刷屏),计数器跨
monstop 不清零。要看某一轮的量,猛发 >256 帧看 `[submitted=X completed=Y reclaimed=Z]` 心跳:
`submitted==completed && reclaimed==0` 即注入健康。

## 验证正常 WiFi 已恢复 (monstop 之后)
```
dumpsys connectivity | grep -i "Transports: WIFI"     # 应见 VALIDATED
dmesg | grep -c "MSDU DONE failure"                   # 应为 0
```

## 已知范围 / 限制
- 监听 + 注入 与 P2P/SoftAP 不能并存(by-policy);日常 WiFi/投屏在 monstop 后正常。
- 第一版注入为固定信道;airodump 跳频注入未优化。
- aireplay-ng 直接用可能遇到 `channel -1`(信道回读缺口),原始套接字注入不受影响。

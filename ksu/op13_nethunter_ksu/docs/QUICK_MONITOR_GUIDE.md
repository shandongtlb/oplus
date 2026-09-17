# peach_v2 全局监听与管理帧注入

先在 KSU Action 中切到本包 WLAN 栈，再从 Android root shell 执行：

```sh
monstart 149        # 原生 wlan0，全局监听，频道 149 / 20 MHz
monstart 6          # 切到频道 6 / 20 MHz
monstart            # 进入监听，不主动设置频道；重复执行保留当前频道
```

在已正确挂载 `/sys`、`/proc`、`/dev` 的 Kali 环境使用：

```sh
iw dev wlan0 info
iwconfig wlan0
airodump-ng wlan0
aireplay-ng --test -a <自有测试AP的BSSID> wlan0
```

退出和查看状态：

```sh
monstop            # 退出 con_mode=4，等待 managed 接口；不等于 Wi-Fi 已连接
sh /data/adb/modules/op13_coloros16_nethunter/monitor_control.sh status
# 模块实际安装目录不同时，请替换上述路径。
```

TX 使用 sam 方案的内部 firmware-only STA helper，RX 和主机接口仍是原生 `wlan0`；
不会创建 `wlan0mon` 或额外 STA netdev。v8 的 Probe、针对性 SSR 恢复与普通 Wi-Fi
回归已有记录；完整验证范围见源码文档和工作区 `说明/op13_v8_runtime_20260917.md`。
`BUILD_INFO.txt` 是已构建模块的身份快照，不代表后续脚本修改已经上机。

## 脚本保护

- 参数格式、频道是否由当前网卡提供且未禁用，在切换模式前检查；不接受多余参数。
  请求频道按 20 MHz 设置，设置成功后回读主频道和带宽。监管与固件最终检查仍由驱动执行。
- 新进入监听后若接口 UP、设频或回读失败，尝试退出本次新会话并返回失败。
  已经处于监听时的换频失败不会自动关闭原会话；请查询实际频道。
- monstart、monstop、reset、KSU Action、模块热切和 bind 修改共用文件锁。
  争用立即报忙；子脚本继承同一把锁，进程结束由内核释放，不靠固定 sleep 解锁。
  不要删除 `.wlan_control.lock`；存在空锁文件不代表正在忙。
  需要系统 `flock` 或 KSU/Magisk 的 BusyBox `flock`。
- 热切先正常退出监听，再卸载模块；退出或重载失败会返回失败，不伪报完成。
- 状态区分接口未就绪、未确认频道、管理员暂停、20 MHz TX READY、宽信道 RX ONLY、
  TX 不可用和需要恢复。状态是查询时快照，READY 不证明实际空口发送成功。

`monreset` 仍用于请求完整 WLAN 栈重载，失败不会强制卸载模块或释放不确定的 DMA。
若驱动仍处于恢复中或拒绝退出，应先查看状态与日志。

## OPPO 与平板网络共享

全局模式切换会停止、关闭普通模式的接口，并拒绝新增虚接口；普通 Wi-Fi、热点、
P2P 共享不能与当前全局监听一起工作。为了避免误中断现有共享，启动监听或热切前
检查同一无线网卡的 AP/P2P-GO/P2P-client 接口，并在可用时读取当前 `wifip2p` 状态。
发现占用会提示先关闭个人热点、与平板网络共享或 Wi-Fi Direct 投屏。

空闲 P2P-device、其他无线网卡、历史事件与持久组列表不算当前占用。P2P 服务不可读
或状态格式未知时，仅依据可读取的接口检查，不因可选信息缺失锁死入口。已经处于
全局监听且没有实际 AP/P2P 接口时，不用 Android 过期的组状态阻止重复启动/reset。
退出监听不受共享检查阻挡。

这是脚本入口提示，不覆盖 Android 后续并发请求。监听期间点击共享、框架强制恢复
等场景尚未做专项真机验证；旧并发监听方案的三处驱动守卫没有直接移植到本版。

## 支持范围

- TX：启用的非被动、非 DFS 的 2.4/5 GHz 20 MHz 频道，排除频道 14；输入必须带
  Radiotap，目前支持管理帧，不支持数据帧、控制帧与 DATAPAD。
- 40/80/160 MHz：RX-only；160 MHz 实际接收仍缺已知信号源验证。
- 速率、NOACK、NOSEQ 等 Radiotap 提示不保证由固件执行。
- `inject_stats` 记录队列/完成/恢复；`inject_tx_status` 区分固件 OK、NO_ACK 等。
  completion 不等于 ACK，固件 OK 也不能代替独立接收证据。
- 丢失 completion 时保留不确定 DMA；只有确认的新固件启动等既有恢复边界才能回收。

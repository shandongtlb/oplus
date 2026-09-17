# 全局监听脚本保护与 OPPO 共享核查（2026-09-17）

本轮只修改 KSU 脚本、说明和主机回归；不修改内核、不完整构建、不部署、不操作手机、
不重打 v8 ZIP。源码仍为 `3b8463c2`，运行时代码仍为 v8 的 `30426bf8`，十四封源码
邮件补丁与“构建接入 + 合并补丁”的重放结论不变。新的脚本不在已交付 ZIP/手机内。

## 已实现

`monitor_control.sh` 在改变 `con_mode` 前拒绝错参数、额外参数、网卡未提供/禁用的
频道；设频后核对实际主频和 20 MHz 带宽。UP/设频/回读失败准确返回；仅对本次从
模式0新进入的监听尝试退回 managed，不把原有监听会话当作失败回滚目标。
monstop 等待并核实 managed 接口，reset 保留子进程错误码。

新增 `wlan_control_common.sh`：由 flock 锁住同一 inode，FD 9 跨子脚本继承；
同时校验环境标记、FD与文件身份，并实际取锁，不凭环境变量绕过互斥。主进程和
子进程关闭描述符后内核释放锁，空文件保留。不存在 flock 时明确报错，不无锁执行。
monstart/stop/reset、KSU Action、模块热切和 bind 修改共用；查询不取锁。
热切在卸载前通过同锁子脚本正常退出监听，退出失败则不进入卸载。

状态同时查看模式、接口类型、IFF_UP、频道带宽、TX helper 状态和模块身份；区分
未就绪、频道未确认、暂停、20 MHz TX READY、宽信道 RX ONLY、TX不可用及恢复需要。
`show_status` 的运行状态输出也包含该快照，不再只显示一个 ON。

## OPPO“与平板网络共享”

旧 `说明/op13_monitor_injection_全程实战记录.md` 的 §11.7 与后续段落记录了该功能
通过 P2P 工作、旧 helper 槽位冲突、以及复用已有 p2p0 绕过新增接口守卫的经历。
旧 `补丁/qca_inject/0016-*` 的三个守卫是新增 AP/GO 接口、STA connect、吞掉框架
WLAN 状态控制；它们并不是当前全局实现已经完整继承的功能。

当前源码核查：

- `wlan_hdd_main.c:hdd_stop_present_mode/hdd_cleanup_present_mode` 在全局切换时
  停止、反初始化、关闭原模式适配器；`hdd_open_adapters_for_monitor_mode` 建监听口。
- `wlan_hdd_p2p.c:__wlan_hdd_add_virtual_intf` 明确拒绝全局监听下新增虚接口。
- `wlan_hdd_cm_connect.c:wlan_hdd_cm_connect` 只允许 STA/P2P-client 类型连接，
  正常的 monitor adapter 不属于可连接类型。
- `wlan_hdd_main.c:wlan_hdd_state_ctrl_param_write` 仍保留原始 OFF/DISABLE/
  FORCE_DISABLE 语义，没有旧版“吞掉框架复位”逻辑。sam 主补丁的
  `docs/monitor-wifi-notifications.md` 同样强调保留实际卸载生命周期，不能照搬旧守卫。
- `wma_inject.c` 在当前空闲 vdev ID 中从高向低选择 helper；这是 firmware-only
  helper，不是额外公开 STA netdev，也不能说 objmgr 已为其建立普通 STA 接口。

因此全局模式正常建立后，旧并发监听场景的多数守卫不再适用。仍不能由“新增接口
被拒绝”推出框架强制恢复、接口改型、监听中点共享等所有路径都经过专项验证。
旧记录的“一根天线物理上绝不可能”“永不需重启”等绝对断言不是本轮依据。

脚本新增的是避免误中断已有共享的入口检查：同一 phy 的 AP/P2P-GO/P2P-client，
以及可读取的当前 P2P 建组/连接状态。忽略空闲 P2P-device、其他 phy、历史事件和
持久组列表。wifip2p 缺失/格式未知不作为硬阻塞；全局模式已有实际 monitor 且无
冲突接口时跳过可能过期的框架组状态。monstop 不受该检查阻挡。
这不能代替驱动互斥，也没有声称 Android 在检查后不可能再发起共享。

## 验证及边界

`python3 tests/test_monitor_control.py` 执行复制后的生产脚本，只替换 sysfs 路径与
Android 命令，不写手机。覆盖参数/禁用频道的零模式变更、重复启动、UP/设频/回读
失败回退、保留既有会话、不同状态输出、退出超时、reset 错误透传、真实父子文件锁、
跨入口竞争、伪造锁标记、持锁进程被杀后的释放、共享占用/空闲/历史状态、以及监听
退出失败阻止热切。原 `tests/test_wlan_identity.py` 继续检查 Build ID/卸载失败边界。

ShellCheck 对新公共脚本和监听脚本无 warning/error；所有改动 shell 文件语法检查。
主机环境用 Linux sh/flock 和模拟 Android 输出，不证明手机 mksh/BusyBox、ColorOS
具体 dumpsys 格式或真实模块重载行为。下一次脚本交付后再验收这些设备差异。

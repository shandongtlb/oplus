# airodump-ng AP数量递减问题及解决方案

## 问题现象

1. `monstart` 后首次运行 `airodump-ng wlan0mon`，搜到的AP数量**远少于** `scanap` 能看到的
2. `ctrl+c` 退出后再次运行 `airodump-ng`，搜到的AP**更少**
3. 重复几次后，最后甚至**搜不到任何AP**
4. 需要**重新热切模块**才能恢复

## 根本原因

### qcacld-3.0 FullMAC monitor模式的状态管理问题

1. **airodump-ng的channel hopping机制**
   - airodump-ng会快速切换信道扫描（2.4G + 5G全频段跳频）
   - 每次切换信道会调用 `iw dev wlan0mon set freq <freq>`
   - 这会触发驱动的 `__wlan_hdd_cfg80211_set_mon_ch()` 函数

2. **helper vdev的频繁重建**
   - 每次 `set freq` 都会：
     - 销毁旧的helper STA vdev（如果存在）
     - 在新信道上创建新的helper STA vdev
   - 频繁的vdev创建/销毁会累积驱动状态残留

3. **状态残留导致的接收能力下降**
   - monitor vdev的RX ring状态可能未完全清理
   - helper vdev的残留peer信息可能干扰新vdev
   - 固件侧的vdev slot可能出现状态不一致
   - 多次ctrl+c可能让驱动的vdev lifecycle进入异常状态

4. **为什么scanap能看到很多AP**
   - `scanap` 使用的是**正常的STA模式**（`iw dev wlan0 scan`）
   - 走的是完全不同的代码路径，没有monitor vdev的状态问题
   - 固件的scan功能是独立的，非常稳定

## 解决方案

### 方案1: monreset（推荐，快速）

新增 `monreset [channel]` 命令，可以在**不退出monitor模式**的情况下重置vdev：

```bash
# airodump跑完后，如果发现AP变少
monreset 6          # 重置monitor vdev，并锁定ch6
airodump-ng wlan0mon   # 重新开始扫描，AP数量恢复

# 或者不锁信道（让airodump自己跳频）
monreset
airodump-ng wlan0mon
```

**原理**：
```bash
ip link set wlan0mon down
iw dev wlan0mon del          # 删除monitor iface
iw phy0 interface add wlan0mon type monitor   # 重建
ip link set wlan0mon up
iw dev wlan0mon set freq <freq>   # 可选：锁定信道
```

**优点**：
- 快（~3秒），不需要等待WiFi重启
- 保持在monitor模式，不影响其他工具
- 清理了monitor vdev + helper vdev的所有状态

### 方案2: monstop + monstart（最彻底）

如果 `monreset` 还是解决不了，完全退出并重新进入：

```bash
monstop             # 完全退出monitor，恢复正常WiFi（~17秒）
monstart 6          # 重新进入monitor + 锁ch6
airodump-ng wlan0mon
```

**优点**：
- 最彻底，连带清理WiFi stack的所有状态
- 会触发driver的idle shutdown机制，完全重置DP ring

**缺点**：
- 慢（~20秒总耗时）
- 会断开当前WiFi连接（如果有的话）

### 方案3: 热切模块（最后手段）

如果上述方案都不行（极少见），说明驱动本身可能有bug或进入了死锁状态：

```bash
# 在电脑端SSH会话里执行（会断开WiFi）
su
rmmod qca_cld3_peach_v2
modprobe qca_cld3_peach_v2
monstart 6
```

## 最佳实践

### 日常使用建议

1. **扫描前先scanap确认目标**
   ```bash
   scanap              # 用STA模式扫一遍，看看有哪些AP
   monstart 6          # 锁定目标信道
   airodump-ng wlan0mon --channel 6   # 只监听单信道，不跳频
   ```

2. **避免让airodump跳频**
   - airodump的全频段跳频是导致状态混乱的主因
   - 用 `--channel` 参数锁定单信道可以大幅减少问题

3. **长时间监听定期reset**
   ```bash
   monstart 6
   airodump-ng wlan0mon --channel 6   # 监听一段时间
   # ctrl+c退出后
   monreset 6          # 重置一下，保证状态干净
   aireplay-ng -0 10 -a <BSSID> wlan0mon   # 注入攻击
   ```

4. **切换信道前reset**
   ```bash
   monstart 6          # 在ch6监听
   airodump-ng wlan0mon --channel 6
   # 想切到ch36
   monreset 36         # 直接reset到新信道
   airodump-ng wlan0mon --channel 36
   ```

### 注入前的信道锁定

```bash
# 错误做法（跳频后注入）
monstart               # 没锁信道
airodump-ng wlan0mon   # 跳频扫描
# ctrl+c
aireplay-ng -0 10 -a <BSSID> wlan0mon   # 注入可能失败（信道不对）

# 正确做法
scanap                 # 先确认目标AP在ch6
monstart 6             # 锁定ch6
airodump-ng wlan0mon --channel 6        # 只监听ch6
# ctrl+c
aireplay-ng -0 10 -a <BSSID> wlan0mon   # 注入成功（信道已锁定）
```

## 技术细节

### monitor_control.sh的reset实现

```bash
mon_reset() {
  ch_or_freq="$1"
  if [ ! -f "$MON_FLAG" ]; then
    log_i "[monitor] not in monitor mode, use 'monstart' first"
    return 1
  fi
  log_i "[monitor] resetting wlan0mon (down->del->add->up)..."
  PHY=$(get_phy)
  [ -z "$PHY" ] && PHY=$(cat /sys/class/net/wlan0mon/phy80211/name 2>/dev/null)
  [ -z "$PHY" ] && { log_i "[monitor] cannot find phy"; return 1; }

  ip link set wlan0mon down 2>/dev/null
  sleep 1
  iw dev wlan0mon del 2>/dev/null
  sleep 1

  ADD=$(iw "$PHY" interface add wlan0mon type monitor 2>&1)
  if [ $? -ne 0 ] || ! iw dev wlan0mon info >/dev/null 2>&1; then
    log_i "[monitor] reset FAILED: $ADD"
    rm -f "$MON_FLAG"
    return 1
  fi
  ip link set wlan0mon up

  if [ -n "$ch_or_freq" ]; then
    freq=$(chan_to_freq "$ch_or_freq") || return 1
    iw dev wlan0mon set freq "$freq" && log_i "[monitor] reset OK, locked ch/freq: $ch_or_freq -> $freq MHz" \
      || log_i "[monitor] warn: set freq $freq failed"
  else
    log_i "[monitor] reset OK (no channel lock, capture-only mode)"
  fi
  return 0
}
```

### 调用路径对比

**scanap (STA模式)**:
```
iw dev wlan0 scan
  → cfg80211_scan()
  → wlan_cfg80211_scan()
  → 固件scan engine（独立状态机）
  → 返回scan results
```

**airodump-ng (monitor模式)**:
```
打开wlan0mon设备
  → 设置promiscuous mode
  → 循环：
      for each channel:
        iw dev wlan0mon set freq <freq>
          → __wlan_hdd_cfg80211_set_mon_ch()
          → wma_vdev_set_param(channel)
          → 如果信道变了：
              wma_mon_destroy_helper_sta_vdev()   # 销毁旧vdev
              wma_mon_create_helper_sta_vdev()    # 创建新vdev（on new channel）
          → WMI_VDEV_SET_PARAM_CMDID
        接收该信道的包（RX ring）
        sleep 一小段时间
```

**问题点**：频繁的 helper vdev 创建/销毁 + channel切换，可能导致：
- WMI command queue堆积
- vdev slot状态不一致
- RX ring descriptor残留
- peer表未完全清理

### 为什么reset有效

1. **完全重建monitor vdev**
   - `iw dev wlan0mon del` 会触发 `hdd_disable_monitor_mode()`
   - 销毁所有相关的vdev（包括helper STA vdev）
   - 清理RX/TX ring
   - 释放固件侧的vdev slot

2. **新的vdev实例**
   - `iw interface add wlan0mon type monitor` 创建全新的vdev
   - 新的vdev ID、新的RX ring、全新的状态机
   - 没有历史包袱

3. **信道锁定可选**
   - 如果只是capture，可以不锁信道（让airodump跳频）
   - 但建议锁定单信道，减少vdev重建次数

## 更新记录

- **2026-06-09**: 添加 `monreset` 命令解决airodump-ng多次运行后AP递减问题
- 安装方式：模块会在boot时自动在 `/data/adb/ksu/bin/` 安装 `monreset` 命令

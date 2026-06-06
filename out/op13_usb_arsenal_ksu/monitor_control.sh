#!/system/bin/sh
# monitor_control.sh — enter/leave monitor mode for the patched qcacld stack.
# Requires the nethunter wlan stack to be active (wlan_stack_control.sh nethunter).
#
# Usage:
#   monitor_control.sh on  [channel]   # enter monitor; with channel -> lock+inject helper vdev
#   monitor_control.sh off             # leave monitor, restore normal WiFi
#   monitor_control.sh status
#
# Channel can be:
#   - short form: 1, 6, 11 (2.4G), 36, 149, 165 (5G)  <- recommended
#   - freq MHz: 2412, 2437, 5180, 5745, etc.
#
# NOTE on injection (OnePlus13 built-in qcacld / FullMAC):
#   - capture/scan works with NO channel (airodump can hop all channels);
#   - INJECTION needs a locked channel: pass channel so the driver builds the
#     hidden STA helper TX vdev on that channel (FW DISCARDs TX on the monitor
#     vdev itself). aireplay/raw-socket then transmit via that helper vdev.

MODDIR=${0%/*}
LOGTAG=op13_monitor
MON_FLAG=$MODDIR/.monitor_enabled

log_i() { log -t "$LOGTAG" "$*" 2>/dev/null; echo "$*"; }

# channel short form -> freq MHz
chan_to_freq() {
  case "$1" in
    # 2.4G common
    1)   echo 2412 ;;
    2)   echo 2417 ;;
    3)   echo 2422 ;;
    6)   echo 2437 ;;
    9)   echo 2452 ;;
    10)  echo 2457 ;;
    11)  echo 2462 ;;
    # 5G common
    36)  echo 5180 ;;
    40)  echo 5200 ;;
    44)  echo 5220 ;;
    48)  echo 5240 ;;
    149) echo 5745 ;;
    153) echo 5765 ;;
    157) echo 5785 ;;
    161) echo 5805 ;;
    165) echo 5825 ;;
    # already freq? pass through if 4-digit
    [0-9][0-9][0-9][0-9]*) echo "$1" ;;
    *) log_i "[monitor] unknown channel '$1' (2.4G: 1-11, 5G: 36,40,44,48,149,153,157,161,165 or freq MHz)"; return 1 ;;
  esac
}

get_phy() {
  p=$(cat /sys/class/net/wlan0/phy80211/name 2>/dev/null)
  [ -z "$p" ] && p=phy$(iw dev wlan0 info 2>/dev/null | awk '/wiphy/{print $2}')
  echo "$p"
}

mon_on() {
  ch_or_freq="$1"
  freq=""
  if [ -n "$ch_or_freq" ]; then
    freq=$(chan_to_freq "$ch_or_freq") || return 1
  fi
  if ! grep -q "^qca_cld3_peach_v2 " /proc/modules 2>/dev/null; then
    log_i "[monitor] nethunter wlan stack not loaded; switch stack first"
    return 1
  fi
  PHY=$(get_phy)
  [ -z "$PHY" ] && { log_i "[monitor] cannot find wlan0 phy"; return 1; }
  log_i "[monitor] using $PHY"

  iw dev wlan0mon del 2>/dev/null
  svc wifi disable
  sleep 2
  settings put global wifi_scan_always_enabled 0
  cmd wifi set-scan-always-available disabled >/dev/null 2>&1 || true
  ip link set wlan0 down 2>/dev/null || true

  ADD=$(iw "$PHY" interface add wlan0mon type monitor 2>&1)
  if [ $? -ne 0 ] || ! iw dev wlan0mon info >/dev/null 2>&1; then
    log_i "[monitor] add wlan0mon FAILED: $ADD"
    if dmesg 2>/dev/null | tail -60 | grep -q "P2P CLIENT concurrency"; then
      log_i "[monitor] >>> 有活跃 P2P/Wi-Fi Direct 占用. 请关闭[手机->平板网络共享/跨设备互联/投屏]后重试."
    fi
    settings put global wifi_scan_always_enabled 1
    cmd wifi set-scan-always-available enabled >/dev/null 2>&1 || true
    svc wifi enable
    return 1
  fi
  ip link set wlan0mon up
  if [ -n "$freq" ]; then
    iw dev wlan0mon set freq "$freq" && log_i "[monitor] locked ch/freq: $ch_or_freq -> $freq MHz (inject helper vdev created)" \
      || log_i "[monitor] warn: set freq $freq failed"
  else
    log_i "[monitor] no channel locked -> capture/scan only (airodump can hop). For injection pass a channel."
  fi
  : > "$MON_FLAG"
  log_i "[monitor] ON. iface=wlan0mon $(iw dev wlan0mon info 2>/dev/null | awk '/channel/{print $0}')"
  log_i "  capture: airodump-ng wlan0mon | tcpdump -i wlan0mon"
  log_i "  inject : aireplay-ng -9 -a <BSSID> wlan0mon  (dmesg|grep NETHUNTER-INJ)"
  return 0
}

mon_off() {
  ip link set wlan0mon down 2>/dev/null || true
  iw dev wlan0mon del 2>/dev/null || true
  sleep 5
  svc wifi enable
  sleep 12
  settings put global wifi_scan_always_enabled 1
  cmd wifi set-scan-always-available enabled >/dev/null 2>&1 || true
  rm -f "$MON_FLAG"
  log_i "[monitor] OFF. normal WiFi restored."
  return 0
}

case "$1" in
  on|enable|start)  shift; mon_on "$1" ;;
  off|disable|stop) mon_off ;;
  status|"")
    if [ -f "$MON_FLAG" ] && iw dev wlan0mon info >/dev/null 2>&1; then
      log_i "[monitor] status: ON"; iw dev wlan0mon info 2>/dev/null | grep -E "Interface|type|channel"
    else
      log_i "[monitor] status: OFF"
    fi
    ;;
  *) echo "usage: $0 [on [freq]|off|status]" >&2; exit 1 ;;
esac

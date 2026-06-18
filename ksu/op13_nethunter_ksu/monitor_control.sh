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
  # Remember the pre-monitor WiFi/scan state so monstop can restore it instead of
  # blindly turning WiFi on (if WiFi was off before monstart, leave it off).
  WIFI_WAS_ON=0
  cmd wifi status 2>/dev/null | grep -qi "Wifi is enabled" && WIFI_WAS_ON=1
  SCAN_WAS_ON=0
  [ "$(settings get global wifi_scan_always_enabled 2>/dev/null)" = "1" ] && SCAN_WAS_ON=1
  svc wifi disable
  sleep 2
  settings put global wifi_scan_always_enabled 0
  cmd wifi set-scan-always-available disabled >/dev/null 2>&1 || true
  ip link set wlan0 down 2>/dev/null || true

  ADD=$(iw "$PHY" interface add wlan0mon type monitor 2>&1)
  if [ $? -ne 0 ] || ! iw dev wlan0mon info >/dev/null 2>&1; then
    log_i "[monitor] add wlan0mon FAILED: $ADD"
    # iw only surfaces a bare -EINVAL (-22); the real reason is logged to dmesg by
    # policy_mgr_check_mon_concurrency(). Map it to a human hint so the user knows
    # WHAT to turn off (hotspot vs tablet-share vs NAN), not just "-22".
    REASON=$(dmesg 2>/dev/null | tail -80 | grep "cannot add monitor mode, due to" | tail -1)
    case "$REASON" in
      *"SAP concurrency"*)
        log_i "[monitor] >>> 个人热点(SoftAP)开着. 请先关闭[设置->个人热点]后重试." ;;
      *"P2P GO concurrency"*|*"P2P CLIENT concurrency"*)
        log_i "[monitor] >>> 有活跃 P2P/Wi-Fi Direct 占用. 请关闭[手机->平板网络共享/跨设备互联/投屏]后重试." ;;
      *"NAN concurrency"*)
        log_i "[monitor] >>> NAN/Wi-Fi 感知占用. 请关闭附近分享/Wi-Fi 感知后重试." ;;
      *)
        log_i "[monitor] >>> 可能有 WiFi 并发占用(SAP/P2P/NAN). 关掉热点/共享/投屏后重试; 详情: dmesg | grep -i 'add monitor mode'" ;;
    esac
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
  printf 'WIFI_WAS_ON=%s\nSCAN_WAS_ON=%s\n' "$WIFI_WAS_ON" "$SCAN_WAS_ON" > "$MON_FLAG"
  log_i "[monitor] ON. iface=wlan0mon $(iw dev wlan0mon info 2>/dev/null | awk '/channel/{print $0}')"
  log_i "  capture: airodump-ng wlan0mon | tcpdump -i wlan0mon"
  log_i "  inject : aireplay-ng -9 -a <BSSID> wlan0mon  (dmesg|grep NETHUNTER-INJ)"
  return 0
}

mon_off() {
  # Fast exit: idle-shutdown path. This cleanly restores STA WiFi and SoftAP
  # hotspot (their DP is reset by the idle-shutdown). It does NOT restore the
  # OPLUS "share to tablet" P2P-GO: during monitor the injection helper vdev
  # grabbed vdev slot 2 (the P2P-GO slot) and that dirty state lives in the
  # kernel driver -- only a full module reload clears it. So if you need the
  # tablet share after monitoring, run 'monreset' (full reload). Keeping monstop
  # fast means you don't pay the ~60s reload on every exit, only when you
  # actually want the share. See mon_reset() below.
  # Restore the pre-monitor state recorded by mon_on (missing/old MON_FLAG ->
  # default to "was on" so behaviour stays backward-compatible).
  WIFI_WAS_ON=$(grep -oE 'WIFI_WAS_ON=[01]' "$MON_FLAG" 2>/dev/null | cut -d= -f2)
  SCAN_WAS_ON=$(grep -oE 'SCAN_WAS_ON=[01]' "$MON_FLAG" 2>/dev/null | cut -d= -f2)
  [ -z "$WIFI_WAS_ON" ] && WIFI_WAS_ON=1
  [ -z "$SCAN_WAS_ON" ] && SCAN_WAS_ON=1

  ip link set wlan0mon down 2>/dev/null || true
  iw dev wlan0mon del 2>/dev/null || true
  # Wait for the forced idle-shutdown to fire + stop_modules to finish. Measured:
  # it triggers ~1s after the del; the hard floor is the 200ms forced-shutdown
  # schedule window -- if 'svc wifi enable' races in before that, it cancels the
  # shutdown and the DP isn't reset. 3s safely covers trigger + stop_modules and
  # is well past the 200ms window.
  sleep 3
  # Only bring WiFi back if it was on before monstart; otherwise leave it off and
  # let the user turn it on themselves.
  if [ "$WIFI_WAS_ON" = "1" ]; then
    svc wifi enable
    # WiFi comes back fast (measured: enabled ~1s, associated ~3s) -- poll
    # instead of a fixed wait.
    i=0
    while [ "$i" -lt 10 ]; do
      cmd wifi status 2>/dev/null | grep -qi "Wifi is enabled" && break
      sleep 1; i=$((i + 1))
    done
    # Small settle before touching scan-always: too early lets the framework open
    # an iface during the idle-restart window (Phase 1c issue).
    sleep 3
  fi
  # Restore scan-always to its pre-monitor value (independent of WiFi on/off).
  if [ "$SCAN_WAS_ON" = "1" ]; then
    settings put global wifi_scan_always_enabled 1
    cmd wifi set-scan-always-available enabled >/dev/null 2>&1 || true
  fi
  rm -f "$MON_FLAG"
  if [ "$WIFI_WAS_ON" = "1" ]; then
    log_i "[monitor] OFF. WiFi + hotspot restored (pre-monitor state)."
  else
    log_i "[monitor] OFF. WiFi left OFF (was off before monstart; turn it on yourself)."
  fi
  log_i "[monitor] 注意: 要用「与平板网络共享」请先运行 monreset (完整复位 P2P, 约60s)."
  return 0
}

mon_reset() {
  # Full WLAN stack reload — recovery / un-wedge command.
  #
  # Use this when WiFi / hotspot / "share to tablet" misbehave after a monitor
  # session, most importantly to make the OPLUS P2P tablet-share work again.
  # Why a full reload (and not just monstop's idle-shutdown): during monitor the
  # raw-WMI injection helper vdev occupies vdev slot 2 — the SAME firmware slot
  # the P2P-GO share uses. After monitoring, that slot's state is left dirty in
  # the KERNEL DRIVER. Tested escalation showed deleting wlan0mon, svc wifi
  # disable/enable, and even restarting wificond/supplicant are all NOT enough;
  # only unloading+reloading the qca/cfg80211/mac80211 modules clears it. That is
  # exactly what the stack switch does. Works in any state (in monitor or not);
  # it will leave monitor mode if active. ~60s (heavy reload + framework settle).
  log_i "[monitor] RESET: full WLAN stack reload (fixes WiFi/hotspot/tablet-share after monitor, ~60s)..."
  ip link set wlan0mon down 2>/dev/null || true
  rm -f "$MON_FLAG"
  sh "$MODDIR/wlan_stack_control.sh" nethunter
  # The reload saw wifi/scan as disabled, so it won't re-enable them. After the
  # heavy reload the framework/HAL needs a long settle window before
  # 'svc wifi enable' takes effect; spamming enable every few seconds keeps
  # resetting its init so it never completes -> enable once, wait patiently, then
  # retry. Usually succeeds on the 1st or 2nd try.
  i=0
  while [ "$i" -lt 5 ]; do
    svc wifi enable
    sleep 15
    if cmd wifi status 2>/dev/null | grep -qi "Wifi is enabled"; then
      break
    fi
    log_i "[monitor] wifi still settling, retry enable ($i)..."
    i=$((i + 1))
  done
  settings put global wifi_scan_always_enabled 1
  cmd wifi set-scan-always-available enabled >/dev/null 2>&1 || true
  if cmd wifi status 2>/dev/null | grep -qi "Wifi is enabled"; then
    log_i "[monitor] RESET done. WiFi + hotspot + tablet-share restored."
  else
    log_i "[monitor] RESET: wifi still down, run 'svc wifi enable' manually."
  fi
  return 0
}

case "$1" in
  on|enable|start)  shift; mon_on "$1" ;;
  off|disable|stop) mon_off ;;
  reset|restart)    mon_reset ;;
  status|"")
    if [ -f "$MON_FLAG" ] && iw dev wlan0mon info >/dev/null 2>&1; then
      log_i "[monitor] status: ON"; iw dev wlan0mon info 2>/dev/null | grep -E "Interface|type|channel"
    else
      log_i "[monitor] status: OFF"
    fi
    ;;
  *) echo "usage: $0 [on [chan/freq]|off|reset|status]" >&2; exit 1 ;;
esac

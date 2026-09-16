#!/system/bin/sh
# OnePlus 13 / peach_v2 native Qualcomm global monitor controller.
# con_mode=4 owns the radio and exposes the monitor adapter as wlan0.
# No wlan0mon interface and no hidden STA/helper vdev are used.

MODDIR=${0%/*}
LOGTAG=op13_global_monitor
MODE=/sys/module/qca_cld3_peach_v2/parameters/con_mode
STATE=$MODDIR/.global_monitor_enabled
. "$MODDIR/module_identity.sh" || exit 1

log_i() { log -t "$LOGTAG" "$*" 2>/dev/null; echo "$*"; }
die() { log_i "[global-monitor] ERROR: $*"; return 1; }

wait_for_iface() {
  want="$1"
  i=0
  while [ "$i" -lt 20 ]; do
    if iw dev wlan0 info 2>/dev/null | grep -q "type $want"; then return 0; fi
    sleep 1
    i=$((i + 1))
  done
  return 1
}

chan_to_freq() {
  case "$1" in
    1) echo 2412;; 2) echo 2417;; 3) echo 2422;; 4) echo 2427;;
    5) echo 2432;; 6) echo 2437;; 7) echo 2442;; 8) echo 2447;;
    9) echo 2452;; 10) echo 2457;; 11) echo 2462;; 12) echo 2467;;
    13) echo 2472;; 14) echo 2484;;
    36) echo 5180;; 40) echo 5200;; 44) echo 5220;; 48) echo 5240;;
    52) echo 5260;; 56) echo 5280;; 60) echo 5300;; 64) echo 5320;;
    100) echo 5500;; 104) echo 5520;; 108) echo 5540;; 112) echo 5560;;
    116) echo 5580;; 120) echo 5600;; 124) echo 5620;; 128) echo 5640;;
    132) echo 5660;; 136) echo 5680;; 140) echo 5700;; 144) echo 5720;;
    149) echo 5745;; 153) echo 5765;; 157) echo 5785;; 161) echo 5805;;
    165) echo 5825;; [0-9][0-9][0-9][0-9]*) echo "$1";; *) return 1;;
  esac
}

mon_on() {
  verify_payload_stack || { die "运行模块与本包不匹配，请先重新切换 WLAN 栈"; return 1; }
  [ -r "$MODE" ] || { die "peach_v2 con_mode 参数不存在，请先加载 nethunter WLAN 栈"; return 1; }
  [ "$(cat "$MODE" 2>/dev/null)" = 4 ] || printf '4\n' > "$MODE" || { die "无法切换 con_mode=4"; return 1; }
  wait_for_iface monitor || { die "全局 monitor 未启动，查看 dmesg | grep -i monitor"; return 1; }
  ip link set wlan0 up 2>/dev/null || true
  if [ -n "$1" ]; then
    freq=$(chan_to_freq "$1") || { die "不支持的频道: $1"; return 1; }
    iw dev wlan0 set freq "$freq" || { die "设置频道失败: $freq MHz"; return 1; }
    log_i "[global-monitor] ON wlan0 channel=$1 freq=$freq MHz"
  else
    log_i "[global-monitor] ON wlan0 (未锁定频道)"
  fi
  : > "$STATE"
}

mon_off() {
  [ -w "$MODE" ] || { die "con_mode 参数不可写"; return 1; }
  printf '0\n' > "$MODE" || { die "无法退出全局 monitor"; return 1; }
  wait_for_iface managed || log_i "[global-monitor] wlan0 尚未恢复 managed，请检查 dmesg"
  rm -f "$STATE"
  log_i "[global-monitor] OFF，已退出 con_mode=4"
}

mon_reset() {
  log_i "[global-monitor] RESET：重载 peach_v2 WLAN 栈"
  printf '0\n' > "$MODE" 2>/dev/null || true
  sh "$MODDIR/wlan_stack_control.sh" nethunter
  rm -f "$STATE"
}

case "$1" in
  on|enable|start) shift; mon_on "$1";;
  off|disable|stop) mon_off;;
  reset|restart) mon_reset;;
  status|"")
    if [ -r "$MODE" ] && [ "$(cat "$MODE" 2>/dev/null)" = 4 ]; then
      log_i "[global-monitor] status: ON"; iw dev wlan0 info 2>/dev/null | grep -E 'Interface|type|channel'
    else
      log_i "[global-monitor] status: OFF"
    fi;;
  *) echo "usage: $0 [on [channel/freq]|off|reset|status]" >&2; exit 1;;
esac

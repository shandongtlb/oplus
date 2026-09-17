#!/system/bin/sh
# Native wlan0 RX; firmware-only STA helper TX follows sam's global design.
MODDIR=${0%/*}
LOGTAG=op13_global_monitor
MODE=/sys/module/qca_cld3_peach_v2/parameters/con_mode
STATS=/sys/module/qca_cld3_peach_v2/parameters/inject_stats
STATE=$MODDIR/.global_monitor_enabled
FW_STATE=$MODDIR/.global_monitor_framework_state
. "$MODDIR/module_identity.sh" || exit 1
. "$MODDIR/wlan_control_common.sh" || exit 1

log_i() { log -t "$LOGTAG" "$*" 2>/dev/null; echo "$*"; }
die() { wlan_error "$*"; return 1; }

wait_for_iface() {
  want=$1
  i=0
  while [ "$i" -lt 20 ]; do
    if iw dev wlan0 info 2>/dev/null | awk -v want="$want" '
      $1 == "type" && $2 == want {ok=1} END {exit !ok}
    '; then return 0; fi
    sleep 1
    i=$((i + 1))
  done
  return 1
}

chan_to_freq() {
  case "$1" in ''|*[!0-9]*) return 1;; esac
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
    165) echo 5825;;
    [245][0-9][0-9][0-9]) echo "$1";;
    *) return 1;;
  esac
}

validate_channel() {
  requested_freq=$(chan_to_freq "$1") || { die "无效的频道或 MHz 频率: $1"; return 1; }
  monitor_phy=$(iw dev wlan0 info 2>/dev/null | awk '$1 == "wiphy" {print "phy" $2; exit}')
  [ -n "$monitor_phy" ] || { die '无法确定 wlan0 的 wiphy，未切换模式。'; return 1; }
  monitor_phy_info=$(iw phy "$monitor_phy" info 2>/dev/null) || {
    die '无法读取网卡频道能力，未切换模式。'; return 1;
  }
  printf '%s\n' "$monitor_phy_info" | awk -v freq="$requested_freq" '
    $1 == "*" && $2 == freq && $3 == "MHz" && !/disabled/ {ok=1}
    END {exit !ok}
  ' || { die "网卡未提供或禁用了 $requested_freq MHz，未切换模式。"; return 1; }
}

mon_status() {
  monitor_mode=$(cat "$MODE" 2>/dev/null)
  if [ "$monitor_mode" != 4 ]; then
    if [ -f "$FW_STATE" ]; then
      log_i '[global-monitor] OFF / RESTORE PENDING：Wi-Fi/扫描状态恢复未完成，请重试 monstop'
      return 0
    fi
    log_i "[global-monitor] OFF (con_mode=${monitor_mode:-不可读})"
    return 0
  fi
  monitor_info=$(iw dev wlan0 info 2>/dev/null)
  if ! printf '%s\n' "$monitor_info" | awk '$1 == "type" && $2 == "monitor" {ok=1} END {exit !ok}'; then
    log_i '[global-monitor] STARTING/UNAVAILABLE：con_mode=4，监听接口尚未就绪'
    return 0
  fi
  printf '%s\n' "$monitor_info" | awk '$1 == "Interface" || $1 == "type" || $1 == "channel"'
  if ! ip -o link show dev wlan0 2>/dev/null | awk '
    {sub(/^[^<]*</, ""); sub(/>.*/, ""); n=split($0, flags, ",")
     for (i=1;i<=n;i++) if (flags[i] == "UP") up=1} END {exit !up}
  '; then
    log_i '[global-monitor] PAUSED：接口未 UP，不能发包'
    return 0
  fi
  monitor_width=$(printf '%s\n' "$monitor_info" | awk '
    $1 == "channel" {for (i=1;i<NF;i++) if ($i == "width:") print $(i+1)}
  ')
  if [ -z "$monitor_width" ]; then
    log_i '[global-monitor] RX INTERFACE READY：频道未确认，请先设置频道'
    return 0
  fi
  monitor_stats=$(cat "$STATS" 2>/dev/null)
  monitor_tx_state=$(printf '%s\n' "$monitor_stats" | awk '{for (i=1;i<=NF;i++) if ($i ~ /^state=/) {sub(/^state=/, "", $i); print $i}}')
  if [ "$monitor_tx_state" = 4 ]; then
    log_i '[global-monitor] RECOVERY REQUIRED：TX 已停用，等待驱动恢复'
  elif [ "$monitor_width" = 40 ] || [ "$monitor_width" = 80 ] || [ "$monitor_width" = 160 ]; then
    log_i "[global-monitor] RX ONLY：$monitor_width MHz 仅接收，不支持注入"
  elif [ "$monitor_width" = 20 ] && [ "$monitor_tx_state" = 2 ] &&
       printf '%s\n' "$monitor_stats" | grep -qE '(^| )stopping=0( |$)' &&
       verify_payload_stack >/dev/null 2>&1; then
    log_i '[global-monitor] TX READY：20 MHz 管理帧注入已就绪（不代表空口发送已验证）'
  else
    log_i "[global-monitor] RX INTERFACE READY / TX UNAVAILABLE：频道已设置，TX helper 未就绪或不可用 (state=${monitor_tx_state:-未知})"
  fi
}

framework_wifi_value() {
  # Runtime state wins over the stale ColorOS wifi_on setting.
  fw_wifi=$(cmd wifi status 2>/dev/null | awk '
    /^Wifi is enabled\r?$/ {print 1; exit}
    /^Wifi is disabled\r?$/ {print 0; exit}')
  case "$fw_wifi" in 0|1) printf '%s\n' "$fw_wifi"; return 0;; esac
  dumpsys -t 3 wifi 2>/dev/null | awk '
    /^Wi-Fi is enabled\r?$/ {value=1; found=1; exit}
    /^Wi-Fi is disabled\r?$/ {value=0; found=1; exit}
    END {if (found) print value; else exit 1}'
}

framework_save() {
  [ ! -e "$FW_STATE" ] || { die '上次 Wi-Fi 状态尚未恢复，请先运行 monstop'; return 1; }
  fw_saved_wifi=$(framework_wifi_value) || { die '无法读取当前 Wi-Fi 状态'; return 1; }
  fw_saved_scan=$(settings get global wifi_scan_always_enabled) || return 1
  case "$fw_saved_scan" in 0|1) ;; *) die '无法读取始终扫描开关'; return 1;; esac
  fw_boot=$(cat /proc/sys/kernel/random/boot_id) || return 1
  fw_tmp=$(mktemp "$FW_STATE.XXXXXX") || return 1
  if ! printf '%s\n%s\n%s\n' "$fw_boot" "$fw_saved_wifi" "$fw_saved_scan" > "$fw_tmp" ||
     ! mv -f "$fw_tmp" "$FW_STATE"; then
    rm -f "$fw_tmp"
    die '无法保存 Wi-Fi/扫描状态，未切换模式'
    return 1
  fi
}

framework_read_saved() {
  fw_boot=$(sed -n '1p' "$FW_STATE") || return 1
  fw_saved_wifi=$(sed -n '2p' "$FW_STATE") || return 1
  fw_saved_scan=$(sed -n '3p' "$FW_STATE") || return 1
  case "$fw_saved_wifi:$fw_saved_scan" in 0:0|0:1|1:0|1:1) ;; *) die '保存的 Wi-Fi 状态无效'; return 1;; esac
  [ "$fw_boot" = "$(cat /proc/sys/kernel/random/boot_id)" ] || {
    # A previous boot's session does not own this boot's preferences.
    rm -f "$FW_STATE"
    die '监听状态来自上次开机，已清除旧记录；本次未改 Wi-Fi 开关'
    return 1
  }
}

framework_scan_set() {
  settings put global wifi_scan_always_enabled "$1" || return 1
  case "$1" in 1) fw_scan_word=enabled;; *) fw_scan_word=disabled;; esac
  cmd wifi set-scan-always-available "$fw_scan_word" >/dev/null 2>&1
}

framework_wait() {
  # NumActiveModeManagers is the live owner count. Other curState lines
  # include the scanner state machine even when there is no STA interface.
  fw_wait_wifi=$1
  fw_wait_active=$2
  fw_wait_count=0
  while [ "$fw_wait_count" -lt 20 ]; do
    fw_active=$(dumpsys -t 3 wifi 2>/dev/null | awk '
      /^NumActiveModeManagers: [0-9]+\r?$/ {print $2; exit}')
    fw_now=$(framework_wifi_value) || fw_now=
    if [ "$fw_now" = "$fw_wait_wifi" ]; then
      case "$fw_wait_active:$fw_active" in
        0:0) return 0;;
        1:*) case "$fw_active" in ''|*[!0-9]*) ;; *) [ "$fw_active" -gt 0 ] && return 0;; esac;;
      esac
    fi
    sleep 1
    fw_wait_count=$((fw_wait_count + 1))
  done
  return 1
}

framework_quiesce() {
  framework_scan_set 0 || return 1
  svc wifi disable >/dev/null 2>&1 || cmd wifi set-wifi-enabled disabled >/dev/null 2>&1 || return 1
  framework_wait 0 0
}

framework_restore() {
  [ -f "$FW_STATE" ] || return 0
  framework_read_saved || return 1
  # Drop any userspace STA owner requested during monitoring before
  # restoring the original settings against the recreated mission interfaces.
  framework_quiesce || { die 'Wi-Fi 框架未停止，保留恢复记录，请重试 monstop'; return 1; }
  framework_scan_set "$fw_saved_scan" || return 1
  if [ "$fw_saved_wifi" = 1 ]; then
    svc wifi enable >/dev/null 2>&1 || cmd wifi set-wifi-enabled enabled >/dev/null 2>&1 || return 1
  fi
  fw_expected_active=0
  [ "$fw_saved_wifi" = 0 ] && [ "$fw_saved_scan" = 0 ] || fw_expected_active=1
  framework_wait "$fw_saved_wifi" "$fw_expected_active" || {
    die 'Wi-Fi/扫描恢复尚未就绪，记录已保留，请重试 monstop'
    return 1
  }
  rm -f "$FW_STATE"
}

rollback_new_monitor() {
  [ "$previous_mode" = 0 ] || return 0
  if printf '0\n' > "$MODE" && wait_for_iface managed; then
    framework_restore || return 1
    rm -f "$STATE"
    log_i '[global-monitor] 本次启动失败，已退回 managed 模式'
  else
    die '本次启动失败，退回 managed 也未完成；请检查当前状态，勿按启动成功继续。'
  fi
}

mon_on() {
  wlan_require_commands iw ip awk cmd settings svc dumpsys mktemp sed || return 1
  requested_freq=
  [ -z "$1" ] || validate_channel "$1" || return 1
  verify_payload_stack || { die '运行模块与本包不匹配，请先重新切换 WLAN 栈'; return 1; }
  [ -w "$MODE" ] || { die 'peach_v2 con_mode 不存在或不可写'; return 1; }
  previous_mode=$(cat "$MODE") || return 1
  case "$previous_mode" in 0|4) ;; *) die "不支持从 con_mode=$previous_mode 启动监听"; return 1;; esac
  wlan_check_sharing || return 1
  if [ "$previous_mode" != 4 ]; then
    framework_save || return 1
    if ! framework_quiesce || ! wlan_check_sharing; then
      die 'Android Wi-Fi/扫描未交出接口，未进入监听'
      framework_restore
      return 1
    fi
    if ! printf '4\n' > "$MODE"; then
      die '无法切换 con_mode=4'
      rollback_new_monitor
      return 1
    fi
  fi
  if ! wait_for_iface monitor || ! ip link set wlan0 up; then
    die '监听接口未就绪或 UP 失败'
    rollback_new_monitor
    return 1
  fi
  if [ -n "$requested_freq" ]; then
    if ! iw dev wlan0 set freq "$requested_freq"; then
      die "设置频道失败: $requested_freq MHz"
      rollback_new_monitor
      return 1
    fi
    if ! iw dev wlan0 info 2>/dev/null | awk -v freq="$requested_freq" '
      $1 == "channel" {
        value=$3; gsub(/[^0-9]/, "", value)
        for (i=1;i<NF;i++) if ($i == "width:" && $(i+1) == 20 && value == freq) ok=1
      } END {exit !ok}
    '; then
      die '设频后的频道/20 MHz 带宽回读不匹配'
      rollback_new_monitor
      return 1
    fi
  fi
  : > "$STATE" || return 1
  mon_status
}

mon_off() {
  wlan_require_commands iw awk || return 1
  [ -w "$MODE" ] || { die 'con_mode 参数不存在或不可写'; return 1; }
  monitor_mode=$(cat "$MODE") || return 1
  case "$monitor_mode" in 0|4) ;; *) die "不支持退出 con_mode=$monitor_mode"; return 1;; esac
  if [ "$monitor_mode" = 4 ]; then
    printf '0\n' > "$MODE" || { die '无法退出全局 monitor'; return 1; }
  fi
  [ "$(cat "$MODE")" = 0 ] || { die 'con_mode 尚未回到 0'; return 1; }
  wait_for_iface managed || { die '已退出监听模式，但 managed 接口尚未就绪'; return 1; }
  framework_restore || return 1
  rm -f "$STATE"
  log_i '[global-monitor] OFF：已退出监听，managed 接口就绪（不代表 Wi-Fi 已连接）'
}

mon_reset() {
  # The stack controller checks sharing, leaves monitor and reloads while
  # retaining this lock. Do not pre-exit and then recheck stale framework P2P.
  log_i '[global-monitor] RESET：重载 peach_v2 WLAN 栈'
  sh "$MODDIR/wlan_stack_control.sh" nethunter
  monitor_reset_rc=$?
  [ "$monitor_reset_rc" -eq 0 ] || { die "WLAN 栈重载失败 ($monitor_reset_rc)"; return "$monitor_reset_rc"; }
  rm -f "$STATE"
}

case "$1" in
  on|enable|start)
    [ "$#" -le 2 ] || { die '用法: monstart [频道或 MHz 频率]'; exit 1; }
    # Validate syntax before taking the lock or changing any state.
    [ "$#" -lt 2 ] || chan_to_freq "$2" >/dev/null || { die "无效频道: $2"; exit 1; }
    wlan_control_lock "$@" || exit 1
    mon_on "${2:-}";;
  off|disable|stop|reset|restart)
    [ "$#" -eq 1 ] || { die '此操作不接受额外参数'; exit 1; }
    wlan_control_lock "$@" || exit 1
    case "$1" in off|disable|stop) mon_off;; *) mon_reset;; esac;;
  status|"") mon_status;;
  *) echo "usage: $0 [on [channel/freq]|off|reset|status]" >&2; exit 1;;
esac

#!/system/bin/sh
# Sourced with MODDIR set. All cooperating writers share an inherited flock.
MODDIR=$(cd "$MODDIR" && pwd -P) || return 1

wlan_error() { echo "[wlan-control] ERROR: $*" >&2; }

wlan_flock() {
  if command -v flock >/dev/null 2>&1; then
    flock "$@"
  elif [ -x /data/adb/ksu/bin/busybox ]; then
    /data/adb/ksu/bin/busybox flock "$@"
  elif [ -x /data/adb/magisk/busybox ]; then
    /data/adb/magisk/busybox flock "$@"
  else
    wlan_error '缺少 flock，无法安全串行启停和热切。'
    return 1
  fi
}

wlan_control_lock() {
  [ "$(id -u)" = 0 ] || { wlan_error '请在 root shell 中执行。'; return 1; }
  wlan_lock_path=$MODDIR/.wlan_control.lock
  # Verify the inherited descriptor as well as the marker. flock on the
  # same open file description is reentrant; an environment marker is not.
  if [ "${OP13_WLAN_LOCK:-}" = "$wlan_lock_path" ] &&
     [ "$wlan_lock_path" -ef "/proc/$$/fd/9" ]; then
    wlan_flock -n 9 || { wlan_error '已有 WLAN 操作进行中，请稍后重试。'; return 1; }
    return 0
  fi
  # Android mksh marks `exec 9>file` descriptors close-on-exec. Open the FD
  # as part of the actual exec instead, so flock and nested scripts inherit it.
  # Re-enter the original command with all arguments before any mutation.
  # Never unlink this file: replacing its inode would allow two owners.
  export OP13_WLAN_LOCK="$wlan_lock_path"
  exec sh "$0" "$@" 9>"$wlan_lock_path"
}

wlan_require_commands() {
  for wlan_cmd in "$@"; do
    command -v "$wlan_cmd" >/dev/null 2>&1 || {
      wlan_error "缺少命令: $wlan_cmd"
      return 1
    }
  done
}

wlan_check_sharing() {
  wlan_require_commands iw awk || return 1
  wlan_interfaces=$(iw dev 2>/dev/null) || {
    wlan_error '无法读取无线接口，未开始操作。'
    return 1
  }
  # Ignore idle P2P-device and other radios when wlan0 identifies our phy.
  wlan_conflicts=$(printf '%s\n' "$wlan_interfaces" | awk '
    /^phy#/ {phy=$1}
    $1 == "Interface" {iface=$2; radios[iface]=phy; if (iface == "wlan0") own=phy}
    $1 == "type" && ($2 == "AP" || $2 == "AP/VLAN" ||
      $2 == "P2P-GO" || $2 == "P2P-client") {conflict[iface]=$2}
    END {for (i in conflict) if (own == "" || radios[i] == own)
      print i " (" conflict[i] ")"}
  ')
  if [ -n "$wlan_conflicts" ]; then
    wlan_error "热点或 P2P 接口占用: $wlan_conflicts；请先关闭个人热点、与平板网络共享或 Wi-Fi Direct 投屏。"
    return 1
  fi
  # Global mode has already closed mission-mode adapters. Android may still
  # report its old group; do not let that stale state block repeat start/reset.
  if [ "$(cat /sys/module/qca_cld3_peach_v2/parameters/con_mode 2>/dev/null)" = 4 ] &&
     printf '%s\n' "$wlan_interfaces" | awk '
       $1 == "Interface" {iface=$2}
       iface == "wlan0" && $1 == "type" && $2 == "monitor" {ok=1}
       END {exit !ok}
     '; then
    return 0
  fi
  # Supplement interface checks with current framework state, when available.
  # Never match history records or saved persistent groups as active sharing.
  if command -v timeout >/dev/null 2>&1 && command -v dumpsys >/dev/null 2>&1; then
    wlan_p2p=$(timeout 5 dumpsys wifip2p 2>/dev/null) || wlan_p2p=
    if printf '%s\n' "$wlan_p2p" | awk '
      /^[ \t]*(curState|mCurrentState)[ \t]*[=:]/ {
        sub(/^[^=:]*[=:][ \t]*/, "")
        if ($0 ~ /^(Group|ProvisionDiscovery|UserAuthorizing|Negotiation|Invitation)/) active=1
      }
      /^[ \t]*mNetworkInfo([ \t]*[=:]|[ \t]+\[)/ && /state: CONNECT(ED|ING)([ \/,}]|$)/ {active=1}
      END {exit !active}
    '; then
      wlan_error 'P2P 正在连接或共享；请先关闭与平板网络共享或 Wi-Fi Direct 投屏。'
      return 1
    fi
  fi
  # This is an entry preflight, not a guarantee against Android starting P2P
  # later. Global-mode exclusion remains the driver's responsibility.
  return 0
}

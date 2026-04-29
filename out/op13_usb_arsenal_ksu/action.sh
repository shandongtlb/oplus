#!/system/bin/sh

MODDIR=${0%/*}
STATE_FLAG=$MODDIR/.nethunter_enabled

log() {
  echo "$*"
}

if [ ! -x "$MODDIR/wlan_stack_control.sh" ]; then
  log "wlan_stack_control.sh missing"
  exit 1
fi

if [ -f "$STATE_FLAG" ]; then
  log "[toggle] current mode: nethunter"
  log "[toggle] switching back to stock"
  if ! sh "$MODDIR/wlan_stack_control.sh" stock; then
    log "stock restore failed"
    exit 1
  fi
  log "stock wlan stack restored"
  exit 0
fi

log "[toggle] current mode: stock"
if [ -x "$MODDIR/bind_mount_control.sh" ]; then
  log "[1/2] enable bind mounts"
  if ! sh "$MODDIR/bind_mount_control.sh" on; then
    log "bind enable failed"
    exit 1
  fi
fi

log "[2/2] switch wlan stack to nethunter"
if ! sh "$MODDIR/wlan_stack_control.sh" nethunter; then
  log "wlan stack switch failed"
  exit 1
fi

log "nethunter stack enabled"
exit 0

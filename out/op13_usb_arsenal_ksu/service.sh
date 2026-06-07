#!/system/bin/sh

MODDIR=${0%/*}
LOGTAG=op13_usb_arsenal
STAGED_FW_DIR=/mnt/vendor/persist/copy
STAGED_FW_FILE=$STAGED_FW_DIR/rt2870.bin

log_i() {
  log -t "$LOGTAG" "$*"
}

log_e() {
  log -t "$LOGTAG" "E: $*"
}

resolve_moddir_file() {
  rel="$1"

  if [ -f "$MODDIR/$rel" ]; then
    echo "$MODDIR/$rel"
    return 0
  fi

  flat_rel=$(printf '%s' "$rel" | tr '/' '\\')
  if [ -f "$MODDIR/$flat_rel" ]; then
    echo "$MODDIR/$flat_rel"
    return 0
  fi

  return 1
}

stage_usb_firmware() {
  src=$(resolve_moddir_file "vendor/firmware/rt2870.bin")

  if [ -z "$src" ] || [ ! -f "$src" ]; then
    log_i "no bundled rt2870.bin in module payload"
    return 0
  fi

  if ! mkdir -p "$STAGED_FW_DIR" 2>/dev/null; then
    log_e "failed to create firmware staging dir $STAGED_FW_DIR"
    return 1
  fi

  if [ -f "$STAGED_FW_FILE" ] && cmp -s "$src" "$STAGED_FW_FILE" 2>/dev/null; then
    log_i "rt2870.bin already staged at $STAGED_FW_FILE"
    return 0
  fi

  if install -m 0644 "$src" "$STAGED_FW_FILE" 2>/dev/null; then
    log_i "staged rt2870.bin -> $STAGED_FW_FILE"
    return 0
  fi

  log_e "failed to stage rt2870.bin -> $STAGED_FW_FILE"
  return 1
}

log_i "boot-time module init: staging firmware only"
stage_usb_firmware || true

# Expose monitor commands as global shell commands. KSU does not always mount
# the module's system/bin into /system/bin on this device (read-only /system),
# so symlink the wrappers into a PATH dir that IS writable. Prefer KSU's own
# bin dir; fall back to /data/local/tmp (also commonly used).
install_cmd_links() {
  for bindir in /data/adb/ksu/bin /data/adb/magisk /system/bin; do
    [ -d "$bindir" ] || continue
    # writability test
    if ( : > "$bindir/.optest" ) 2>/dev/null; then
      rm -f "$bindir/.optest"
      ln -sf "$MODDIR/monstart" "$bindir/monstart" 2>/dev/null
      ln -sf "$MODDIR/monstop"  "$bindir/monstop"  2>/dev/null
      ln -sf "$MODDIR/scanap"   "$bindir/scanap"   2>/dev/null
      log_i "monitor commands linked into $bindir"
      return 0
    fi
  done
  log_i "no writable PATH dir found; use full path or alias for monstart/monstop"
  return 1
}
install_cmd_links || true

if [ -x "$MODDIR/bind_mount_control.sh" ]; then
  if [ -f "$MODDIR/.nethunter_enabled" ]; then
    "$MODDIR/bind_mount_control.sh" apply_if_enabled --quiet || true
  else
    "$MODDIR/bind_mount_control.sh" remove --quiet || true
  fi
fi

if [ -x "$MODDIR/update_runtime_status.sh" ]; then
  "$MODDIR/update_runtime_status.sh" >/dev/null 2>&1 || true
fi

log_i "manual bind control: $MODDIR/bind_mount_control.sh"
log_i "manual wlan stack control: $MODDIR/wlan_stack_control.sh"
exit 0

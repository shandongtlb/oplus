#!/system/bin/sh

MODDIR=${0%/*}
BIND_FLAG=$MODDIR/.bind_mount_enabled
STATE_FLAG=$MODDIR/.nethunter_enabled

cleanup_binds() {
  if [ -x "$MODDIR/bind_mount_control.sh" ]; then
    "$MODDIR/bind_mount_control.sh" remove --quiet || true
  fi
  rm -f "$BIND_FLAG"
  rm -f "$STATE_FLAG"
  rm -f "$MODDIR/runtime_status.txt"
}

cleanup_fw() {
  src="$MODDIR/vendor/firmware/rt2870.bin"

  for dst in \
    /mnt/vendor/persist/copy/rt2870.bin \
    /mnt/vendor/persist/rt2870.bin
  do
    if [ ! -f "$dst" ]; then
      continue
    fi

    if [ -f "$src" ] && cmp -s "$src" "$dst" 2>/dev/null; then
      rm -f "$dst"
    fi
  done
}

cleanup_binds
cleanup_fw

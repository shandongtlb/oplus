#!/system/bin/sh

MODDIR=${0%/*}
LOGTAG=op13_usb_arsenal
BIND_FLAG=$MODDIR/.bind_mount_enabled
QUIET=0
. "$MODDIR/wlan_control_common.sh" || exit 1

log_i() {
  if [ "$QUIET" -ne 1 ]; then
    log -t "$LOGTAG" "$*"
    echo "$*"
  fi
}

log_e() {
  log -t "$LOGTAG" "E: $*"
  echo "E: $*" >&2
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

is_target_bound() {
  target="$1"
  awk -v target="$target" '$2 == target { found = 1 } END { exit(found ? 0 : 1) }' /proc/mounts 2>/dev/null
}

print_pairs() {
  cat <<'EOF'
vendor_dlkm/lib/modules/cfg80211.ko|/vendor_dlkm/lib/modules/cfg80211.ko
vendor_dlkm/lib/modules/mac80211.ko|/vendor_dlkm/lib/modules/mac80211.ko
vendor_dlkm/lib/modules/qca_cld3_peach_v2.ko|/vendor_dlkm/lib/modules/qca_cld3_peach_v2.ko
EOF
}

apply_one() {
  rel="$1"
  target="$2"
  src=$(resolve_moddir_file "$rel")

  if [ -z "$src" ] || [ ! -f "$src" ]; then
    log_e "missing bind source for $rel"
    return 1
  fi

  if [ ! -e "$target" ]; then
    log_e "missing bind target $target"
    return 1
  fi

  # A bind retains the source inode's SELinux label. KSU's default
  # system_file label is not readable/loadable by ColorOS vendor_modprobe;
  # its recovery script can rmmod successfully and then fail to insmod.
  # Match the stock vendor module label before exposing the replacement.
  if ! chcon u:object_r:vendor_file:s0 "$src"; then
    log_e "failed to label vendor module $src; bind left unchanged"
    return 1
  fi

  if is_target_bound "$target"; then
    umount "$target" 2>/dev/null || true
  fi

  if mount -o bind "$src" "$target" 2>/dev/null; then
    log_i "bind-mounted $src -> $target"
    return 0
  fi

  log_e "failed to bind-mount $src -> $target"
  return 1
}

remove_one() {
  target="$1"

  if ! is_target_bound "$target"; then
    return 0
  fi

  if umount "$target" 2>/dev/null; then
    log_i "removed bind mount $target"
    return 0
  fi

  log_e "failed to remove bind mount $target"
  return 1
}

apply_all() {
  rc=0
  while IFS='|' read -r rel target; do
    apply_one "$rel" "$target" || rc=1
  done <<EOF
$(print_pairs)
EOF
  return $rc
}

remove_all() {
  rc=0
  while IFS='|' read -r rel target; do
    remove_one "$target" || rc=1
  done <<EOF
$(print_pairs)
EOF
  return $rc
}

status_all() {
  if [ -f "$BIND_FLAG" ]; then
    log_i "bind switch: enabled"
  else
    log_i "bind switch: disabled"
  fi

  while IFS='|' read -r rel target; do
    if is_target_bound "$target"; then
      log_i "mounted: $target"
    else
      log_i "not mounted: $target"
    fi
  done <<EOF
$(print_pairs)
EOF
}

COMMAND=""
for arg in "$@"; do
  case "$arg" in
    --quiet)
      QUIET=1
      ;;
    *)
      if [ -z "$COMMAND" ]; then
        COMMAND="$arg"
      fi
      ;;
  esac
done

case "$COMMAND" in
  on|off|apply_if_enabled|apply|remove) wlan_control_lock "$@" || exit 1;;
esac

case "$COMMAND" in
  on)
    : > "$BIND_FLAG"
    apply_all
    ;;
  off)
    rm -f "$BIND_FLAG"
    remove_all
    ;;
  apply_if_enabled)
    if [ -f "$BIND_FLAG" ]; then
      apply_all
    else
      log_i "bind switch disabled; skipping bind mounts"
    fi
    ;;
  apply)
    apply_all
    ;;
  remove)
    remove_all
    ;;
  status|"")
    status_all
    ;;
  *)
    echo "usage: $0 [status|on|off|apply_if_enabled|apply|remove] [--quiet]" >&2
    exit 1
    ;;
esac

rc=$?
if [ -x "$MODDIR/update_runtime_status.sh" ]; then
  "$MODDIR/update_runtime_status.sh" >/dev/null 2>&1 || true
fi
exit $rc

#!/system/bin/sh

MODDIR=${0%/*}
STATUS_FILE=$MODDIR/runtime_status.txt
STAGED_FW_FILE=/mnt/vendor/persist/copy/rt2870.bin
BIND_FLAG=$MODDIR/.bind_mount_enabled
STATE_FLAG=$MODDIR/.nethunter_enabled
MODULE_PROP=$MODDIR/module.prop
. "$MODDIR/module_identity.sh" || exit 1

is_loaded() {
  grep -q "^$1 " /proc/modules 2>/dev/null
}

is_bound() {
  target="$1"
  awk -v target="$target" '$2 == target { found = 1 } END { exit(found ? 0 : 1) }' /proc/mounts 2>/dev/null
}

stack_mode=$(payload_stack_mode)
bind_mode="disabled"
fw_mode="missing"

if [ "$stack_mode" = nethunter ] && [ -f "$BIND_FLAG" ]; then
  bind_mode="enabled"
fi

if [ -f "$STAGED_FW_FILE" ]; then
  fw_mode="staged"
fi

update_module_description() {
  if [ ! -f "$MODULE_PROP" ]; then
    return 0
  fi

  desc="mode:$stack_mode | bind:$bind_mode | fw:$fw_mode"
  tmp="$MODULE_PROP.tmp"
  awk -v desc="$desc" '
    BEGIN { done = 0 }
    /^description=/ {
      print "description=" desc
      done = 1
      next
    }
    { print }
    END {
      if (!done) print "description=" desc
    }
  ' "$MODULE_PROP" > "$tmp" && mv "$tmp" "$MODULE_PROP"
  chmod 0644 "$MODULE_PROP" 2>/dev/null || true
}

{
  echo "stack_mode=$stack_mode"
  for identity_name in cfg80211 mac80211 qca_cld3_peach_v2; do
    echo "${identity_name}_identity=$(module_identity "$identity_name")"
  done
  echo "bind_mode=$bind_mode"
  echo "firmware_rt2870=$fw_mode"
  echo "cfg80211_loaded=$(is_loaded cfg80211 && echo yes || echo no)"
  echo "mac80211_loaded=$(is_loaded mac80211 && echo yes || echo no)"
  echo "qca_cld3_peach_v2_loaded=$(is_loaded qca_cld3_peach_v2 && echo yes || echo no)"
  echo "rt2800usb_loaded=$(is_loaded rt2800usb && echo yes || echo no)"
  echo "rt2x00usb_loaded=$(is_loaded rt2x00usb && echo yes || echo no)"
  echo "zd1201_loaded=$(is_loaded zd1201 && echo yes || echo no)"
  echo "cfg80211_bound=$(is_bound /vendor_dlkm/lib/modules/cfg80211.ko && echo yes || echo no)"
  echo "mac80211_bound=$(is_bound /vendor_dlkm/lib/modules/mac80211.ko && echo yes || echo no)"
  echo "qca_cld3_peach_v2_bound=$(is_bound /vendor_dlkm/lib/modules/qca_cld3_peach_v2.ko && echo yes || echo no)"
  if [ -f "$MODDIR/monitor_control.sh" ]; then
    sh "$MODDIR/monitor_control.sh" status
  fi
} > "$STATUS_FILE"

update_module_description

cat "$STATUS_FILE"
exit 0

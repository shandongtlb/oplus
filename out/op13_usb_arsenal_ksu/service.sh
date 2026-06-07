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

# Write the canonical, self-contained scanap implementation to $1.
# It is fully inlined (no forwarding to another file) so the resulting
# command can never become a self-referential infinite loop, regardless of
# what name it is installed under.
write_scanap() {
  cat > "$1" <<'SCANAP_EOF'
#!/system/bin/sh
# scanap — list nearby APs with channel/freq (uses normal wlan0, not monitor)
if ! ip link show wlan0 >/dev/null 2>&1; then
  echo "wlan0 不存在(在 monitor 模式?先 monstop)"
  exit 1
fi
out=$(iw dev wlan0 scan 2>&1)
if [ -z "$out" ]; then
  echo "扫描无结果。确认 wlan0 已 UP 且不在 monitor 模式。"
  exit 1
fi
echo "$out" | awk '
function freq2ch(f) {
  if (f==2412) return 1;  if (f==2417) return 2;  if (f==2422) return 3;
  if (f==2427) return 4;  if (f==2432) return 5;  if (f==2437) return 6;
  if (f==2442) return 7;  if (f==2447) return 8;  if (f==2452) return 9;
  if (f==2457) return 10; if (f==2462) return 11; if (f==2467) return 12;
  if (f==2472) return 13; if (f==2484) return 14;
  if (f==5180) return 36; if (f==5200) return 40; if (f==5220) return 44;
  if (f==5240) return 48; if (f==5260) return 52; if (f==5280) return 56;
  if (f==5300) return 60; if (f==5320) return 64; if (f==5500) return 100;
  if (f==5520) return 104; if (f==5540) return 108; if (f==5560) return 112;
  if (f==5580) return 116; if (f==5660) return 132; if (f==5680) return 136;
  if (f==5700) return 140; if (f==5745) return 149; if (f==5765) return 153;
  if (f==5785) return 157; if (f==5805) return 161; if (f==5825) return 165;
  return "?";
}
function flush() {
  if (mac != "") {
    if (ssid == "") ssid = "(hidden)";
    printf "%-28s  ch%-4s %5s MHz  %8s  %s\n", ssid, freq2ch(freq), freq, sig, mac;
  }
  mac=""; freq=""; sig=""; ssid="";
}
/^BSS/ { flush(); mac=$2; gsub(/\(.*/, "", mac); next }
/^[ \t]*freq:/ { freq=$2; next }
/^[ \t]*signal:/ { sig=$2; next }
/^[ \t]*SSID:/ { ssid=$0; sub(/^[ \t]*SSID: ?/, "", ssid); next }
END { flush() }
'
echo
echo "用法: 记下目标 chXX,再 monstart XX 锁频后注入"
SCANAP_EOF
  chmod 755 "$1"
}

# Self-heal the module-dir scanap in case a previous buggy build left a
# self-referential stub there (the cause of the historical infinite loop).
write_scanap "$MODDIR/scanap"

# Expose monitor commands as global shell commands. KSU does not always mount
# the module's system/bin into /system/bin on this device (read-only /system),
# so create command scripts in a writable PATH dir.
#   - monstart/monstop forward to monitor_control.sh (different name -> no loop)
#   - scanap is fully inlined (no forwarding -> structurally impossible to loop)
install_cmd_links() {
  for bindir in /data/adb/ksu/bin /data/adb/magisk /system/bin; do
    [ -d "$bindir" ] || continue
    # Never write commands back into the module directory itself.
    [ "$bindir" = "$MODDIR" ] && continue
    # writability test
    if ( : > "$bindir/.optest" ) 2>/dev/null; then
      rm -f "$bindir/.optest"

      cat > "$bindir/monstart" <<EOF
#!/system/bin/sh
exec sh "$MODDIR/monitor_control.sh" on "\$@"
EOF
      cat > "$bindir/monstop" <<EOF
#!/system/bin/sh
exec sh "$MODDIR/monitor_control.sh" off
EOF
      # scanap: inline the real implementation, do NOT forward.
      write_scanap "$bindir/scanap"

      chmod 755 "$bindir/monstart" "$bindir/monstop"
      log_i "monitor commands installed into $bindir"
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

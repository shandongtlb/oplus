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

stage_usb_firmware() {
  src="$MODDIR/vendor/firmware/rt2870.bin"

  if [ ! -f "$src" ]; then
    log_i "no bundled rt2870.bin at $src"
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

is_loaded() {
  grep -q "^$1 " /proc/modules 2>/dev/null
}

wait_until_unloaded() {
  name="$1"
  retries="${2:-20}"

  while [ "$retries" -gt 0 ]; do
    if ! is_loaded "$name"; then
      return 0
    fi
    sleep 1
    retries=$((retries - 1))
  done

  return 1
}

resolve_path() {
  leaf="$1"
  shift

  for candidate in "$@"; do
    if [ -n "$candidate" ] && [ -f "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done

  for base in \
    /vendor_dlkm/lib/modules \
    /system_dlkm/lib/modules \
    "$MODDIR/vendor_dlkm/lib/modules" \
    "$MODDIR/system_dlkm/lib/modules"
  do
    if [ -d "$base" ]; then
      found=$(find "$base" -type f -name "$leaf" 2>/dev/null | head -n 1)
      if [ -n "$found" ]; then
        echo "$found"
        return 0
      fi
    fi
  done

  return 1
}

load_module() {
  name="$1"
  shift

  if is_loaded "$name"; then
    log_i "$name already loaded"
    return 0
  fi

  path=$(resolve_path "$name.ko" "$@")
  if [ -z "$path" ]; then
    log_e "missing $name"
    return 1
  fi

  if insmod "$path" 2>/dev/null; then
    log_i "loaded $name from $path"
    return 0
  fi

  log_e "failed to load $name from $path"
  return 1
}

unload_module() {
  name="$1"

  if ! is_loaded "$name"; then
    return 0
  fi

  if rmmod "$name" 2>/dev/null; then
    if wait_until_unloaded "$name" 15; then
      log_i "unloaded $name"
      return 0
    fi
    log_e "$name rmmod returned, but module is still present"
    return 1
  fi

  log_e "failed to unload $name"
  return 1
}

wifi_is_enabled() {
  state=$(settings get global wifi_on 2>/dev/null || true)
  if [ "$state" = "1" ]; then
    return 0
  fi

  if cmd wifi status 2>/dev/null | grep -qi 'enabled'; then
    return 0
  fi

  if dumpsys wifi 2>/dev/null | grep -q 'Wi-Fi is enabled'; then
    return 0
  fi

  return 1
}

wifi_scan_always_available() {
  state=$(settings get global wifi_scan_always_enabled 2>/dev/null || true)
  [ "$state" = "1" ]
}

set_wifi_disabled() {
  svc wifi disable 2>/dev/null || cmd wifi set-wifi-enabled disabled 2>/dev/null || true
}

set_wifi_enabled() {
  svc wifi enable 2>/dev/null || cmd wifi set-wifi-enabled enabled 2>/dev/null || true
}

set_wifi_scan_disabled() {
  settings put global wifi_scan_always_enabled 0 2>/dev/null || true
}

set_wifi_scan_enabled() {
  settings put global wifi_scan_always_enabled 1 2>/dev/null || true
}

process_running() {
  ps -A 2>/dev/null | grep -q "[[:space:]]$1\$"
}

stop_wifi_userspace() {
  for svc in hostapd wpa_supplicant wificond; do
    setprop ctl.stop "$svc" 2>/dev/null || stop "$svc" 2>/dev/null || true
  done
  sleep 1
}

start_wifi_userspace() {
  for svc in wificond; do
    setprop ctl.start "$svc" 2>/dev/null || start "$svc" 2>/dev/null || true
  done
}

wait_for_process() {
  name="$1"
  retries="${2:-10}"

  while [ "$retries" -gt 0 ]; do
    if process_running "$name"; then
      return 0
    fi
    sleep 1
    retries=$((retries - 1))
  done

  return 1
}

wait_for_wifi_to_quiesce() {
  retries=20

  while [ "$retries" -gt 0 ]; do
    if ! process_running wificond && \
       ! process_running wpa_supplicant && \
       ! process_running hostapd && \
       ! is_loaded qca_cld3_peach_v2; then
      return 0
    fi
    sleep 1
    retries=$((retries - 1))
  done

  return 1
}

reload_module_stack() {
  wifi_was_enabled=0
  scan_was_enabled=0

  if wifi_is_enabled; then
    wifi_was_enabled=1
    log_i "wifi is enabled, disabling before module switch"
  else
    log_i "forcing wifi disabled before module switch"
  fi

  if wifi_scan_always_available; then
    scan_was_enabled=1
    log_i "disabling wifi scan always available before module switch"
    set_wifi_scan_disabled
  fi

  set_wifi_disabled
  stop_wifi_userspace
  if ! wait_for_wifi_to_quiesce; then
    log_e "wifi stack did not quiesce after disable request"
  fi
  sleep 2

  unload_module qca_cld3_peach_v2 || true
  unload_module zd1201 || true
  unload_module rt2800usb || true
  unload_module rt2800lib || true
  unload_module rt2x00usb || true
  unload_module rt2x00lib || true
  unload_module mac80211 || true
  unload_module cfg80211 || true

  sleep 2

  load_module cfg80211 "$MODDIR/vendor_dlkm/lib/modules/cfg80211.ko" /vendor_dlkm/lib/modules/cfg80211.ko || return 1
  load_module mac80211 "$MODDIR/vendor_dlkm/lib/modules/mac80211.ko" /vendor_dlkm/lib/modules/mac80211.ko || return 1
  load_module qca_cld3_peach_v2 "$MODDIR/vendor_dlkm/lib/modules/qca_cld3_peach_v2.ko" /vendor_dlkm/lib/modules/qca_cld3_peach_v2.ko || return 1
  load_module zd1201 "$MODDIR/vendor_dlkm/lib/modules/zd1201.ko" /vendor_dlkm/lib/modules/zd1201.ko || true
  load_module rt2x00lib "$MODDIR/vendor_dlkm/lib/modules/rt2x00lib.ko" /vendor_dlkm/lib/modules/rt2x00lib.ko || true
  load_module rt2800lib "$MODDIR/vendor_dlkm/lib/modules/rt2800lib.ko" /vendor_dlkm/lib/modules/rt2800lib.ko || true
  load_module rt2x00usb "$MODDIR/vendor_dlkm/lib/modules/rt2x00usb.ko" /vendor_dlkm/lib/modules/rt2x00usb.ko || true
  load_module rt2800usb "$MODDIR/vendor_dlkm/lib/modules/rt2800usb.ko" /vendor_dlkm/lib/modules/rt2800usb.ko || true

  start_wifi_userspace
  if ! wait_for_process wificond 10; then
    log_e "wificond did not become ready after module switch"
  fi

  if [ "$wifi_was_enabled" -eq 1 ]; then
    sleep 2
    log_i "re-enabling wifi after module switch"
    set_wifi_enabled
  fi

  if [ "$scan_was_enabled" -eq 1 ]; then
    log_i "restoring wifi scan always available"
    set_wifi_scan_enabled
  fi

  return 0
}

for delay in 8 16; do
  sleep "$delay"

  load_module rfkill /system_dlkm/lib/modules/rfkill.ko
  load_module libarc4 /system_dlkm/lib/modules/libarc4.ko
  load_module usbserial /system_dlkm/lib/modules/usbserial.ko

  load_module cfg80211 "$MODDIR/vendor_dlkm/lib/modules/cfg80211.ko" /vendor_dlkm/lib/modules/cfg80211.ko
  load_module mac80211 "$MODDIR/vendor_dlkm/lib/modules/mac80211.ko" /vendor_dlkm/lib/modules/mac80211.ko
  # Keep using the stock cnss platform stack; unloading/replacing cnss_* is not stable.
  load_module wlan_firmware_service "$MODDIR/vendor_dlkm/lib/modules/wlan_firmware_service.ko" /vendor_dlkm/lib/modules/wlan_firmware_service.ko

  stage_usb_firmware

  load_module ch341 "$MODDIR/system_dlkm/lib/modules/ch341.ko"
  load_module pl2303 "$MODDIR/system_dlkm/lib/modules/pl2303.ko"

  reload_module_stack || true

  if is_loaded ch341 && is_loaded pl2303 && is_loaded zd1201 && is_loaded rt2800usb && is_loaded qca_cld3_peach_v2; then
    log_i "all target modules are present"
    exit 0
  fi
done

log_e "some target modules are still not loaded after retry"
exit 0

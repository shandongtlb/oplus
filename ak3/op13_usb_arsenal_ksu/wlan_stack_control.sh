#!/system/bin/sh

MODDIR=${0%/*}
LOGTAG=op13_usb_arsenal
STAGED_FW_DIR=/mnt/vendor/persist/copy
STAGED_FW_FILE=$STAGED_FW_DIR/rt2870.bin
STATE_FLAG=$MODDIR/.nethunter_enabled

log_i() {
  log -t "$LOGTAG" "$*"
  echo "$*"
}

log_e() {
  log -t "$LOGTAG" "E: $*"
  echo "E: $*" >&2
}

is_loaded() {
  grep -q "^$1 " /proc/modules 2>/dev/null
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

resolve_moddir_dir() {
  rel="$1"

  if [ -d "$MODDIR/$rel" ]; then
    echo "$MODDIR/$rel"
    return 0
  fi

  flat_rel=$(printf '%s' "$rel" | tr '/' '\\')
  if [ -d "$MODDIR/$flat_rel" ]; then
    echo "$MODDIR/$flat_rel"
    return 0
  fi

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

    case "$candidate" in
      "$MODDIR"/*)
        rel="${candidate#"$MODDIR"/}"
        flat_rel=$(printf '%s' "$rel" | tr '/' '\\')
        flat_candidate="$MODDIR/$flat_rel"
        if [ "$flat_candidate" != "$candidate" ] && [ -f "$flat_candidate" ]; then
          echo "$flat_candidate"
          return 0
        fi
        ;;
    esac
  done

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

load_module_strict() {
  name="$1"
  rel="$2"

  if is_loaded "$name"; then
    log_i "$name already loaded"
    return 0
  fi

  path=$(resolve_moddir_file "$rel")
  if [ -z "$path" ] || [ ! -f "$path" ]; then
    log_e "missing strict module $name at $rel"
    return 1
  fi

  if insmod "$path" 2>/dev/null; then
    log_i "loaded $name from $path"
    return 0
  fi

  log_e "failed to load $name from $path"
  return 1
}

load_module_relaxed() {
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

module_name_from_path() {
  base="${1##*/}"
  base="${base%.ko}"
  printf '%s' "$base" | tr '-' '_'
}

is_auto_managed_known_module() {
  case "$1" in
    cfg80211|mac80211|qca_cld3_peach_v2|zd1201|rt2x00lib|rt2800lib|rt2x00usb|rt2800usb)
      return 0
      ;;
  esac
  return 1
}

load_extra_modules_from_dir() {
  dir="$1"
  passes="${2:-5}"

  [ -d "$dir" ] || return 0

  pass=1
  while [ "$pass" -le "$passes" ]; do
    progress=0
    pending=0

    for path in "$dir"/*.ko; do
      [ -f "$path" ] || continue
      name=$(module_name_from_path "$path")

      if is_auto_managed_known_module "$name"; then
        continue
      fi

      if is_loaded "$name"; then
        continue
      fi

      pending=1
      if insmod "$path" 2>/dev/null; then
        log_i "loaded extra $name from $path"
        progress=1
      fi
    done

    [ "$pending" -eq 0 ] && return 0
    [ "$progress" -eq 0 ] && break
    pass=$((pass + 1))
  done

  rc=0
  for path in "$dir"/*.ko; do
    [ -f "$path" ] || continue
    name=$(module_name_from_path "$path")

    if is_auto_managed_known_module "$name"; then
      continue
    fi

    if ! is_loaded "$name"; then
      log_e "extra module not loaded: $name from $path"
      rc=1
    fi
  done

  return $rc
}

load_extra_modules_from_rel() {
  rel="$1"
  dir=$(resolve_moddir_dir "$rel")

  if [ -z "$dir" ] || [ ! -d "$dir" ]; then
    return 0
  fi

  load_extra_modules_from_dir "$dir" 5
}

unload_extra_modules_from_dir() {
  dir="$1"
  passes="${2:-5}"

  [ -d "$dir" ] || return 0

  pass=1
  while [ "$pass" -le "$passes" ]; do
    progress=0
    pending=0

    for path in "$dir"/*.ko; do
      [ -f "$path" ] || continue
      name=$(module_name_from_path "$path")

      if is_auto_managed_known_module "$name"; then
        continue
      fi

      if ! is_loaded "$name"; then
        continue
      fi

      pending=1
      if rmmod "$name" 2>/dev/null; then
        if wait_until_unloaded "$name" 10; then
          log_i "unloaded extra $name"
          progress=1
        fi
      fi
    done

    [ "$pending" -eq 0 ] && return 0
    [ "$progress" -eq 0 ] && break
    pass=$((pass + 1))
  done

  rc=0
  for path in "$dir"/*.ko; do
    [ -f "$path" ] || continue
    name=$(module_name_from_path "$path")

    if is_auto_managed_known_module "$name"; then
      continue
    fi

    if is_loaded "$name"; then
      log_e "extra module still loaded: $name"
      rc=1
    fi
  done

  return $rc
}

unload_extra_modules_from_rel() {
  rel="$1"
  dir=$(resolve_moddir_dir "$rel")

  if [ -z "$dir" ] || [ ! -d "$dir" ]; then
    return 0
  fi

  unload_extra_modules_from_dir "$dir" 5
}

load_stock_module() {
  name="$1"
  path="$2"

  if is_loaded "$name"; then
    log_i "$name already loaded"
    return 0
  fi

  if [ ! -f "$path" ]; then
    log_e "missing stock module $name at $path"
    return 1
  fi

  if insmod "$path" 2>/dev/null; then
    log_i "loaded stock $name from $path"
    return 0
  fi

  log_e "failed to load stock $name from $path"
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

prepare_switch() {
  WIFI_WAS_ENABLED=0
  SCAN_WAS_ENABLED=0

  if wifi_is_enabled; then
    WIFI_WAS_ENABLED=1
    log_i "wifi is enabled, disabling before module switch"
  else
    log_i "wifi already disabled before module switch"
  fi

  if wifi_scan_always_available; then
    SCAN_WAS_ENABLED=1
    log_i "disabling wifi scan always available before module switch"
    set_wifi_scan_disabled
  fi

  set_wifi_disabled
  stop_wifi_userspace
  if ! wait_for_wifi_to_quiesce; then
    log_e "wifi stack did not quiesce after disable request"
  fi
  sleep 2

  # Unload add-on drivers first; keep the WLAN core stack until the end.
  unload_extra_modules_from_rel "vendor_dlkm/lib/modules" || true
  unload_extra_modules_from_rel "system_dlkm/lib/modules" || true

  unload_module zd1201 || true
  unload_module rt2800usb || true
  unload_module rt2800lib || true
  unload_module rt2x00usb || true
  unload_module rt2x00lib || true

  unload_module qca_cld3_peach_v2 || true
  unload_module mac80211 || true
  unload_module cfg80211 || true
}

finish_switch() {
  start_wifi_userspace
  if ! wait_for_process wificond 10; then
    log_e "wificond did not become ready after module switch"
  fi

  if [ "${WIFI_WAS_ENABLED:-0}" -eq 1 ]; then
    sleep 2
    log_i "re-enabling wifi after module switch"
    set_wifi_enabled
  fi

  if [ "${SCAN_WAS_ENABLED:-0}" -eq 1 ]; then
    log_i "restoring wifi scan always available"
    set_wifi_scan_enabled
  fi
}

switch_to_nethunter() {
  log_i "switching wlan stack to module payload"
  stage_usb_firmware || true
  if [ -x "$MODDIR/bind_mount_control.sh" ]; then
    "$MODDIR/bind_mount_control.sh" apply_if_enabled || true
  fi
  prepare_switch
  sleep 2

  load_module_relaxed rfkill /system_dlkm/lib/modules/rfkill.ko || true
  load_module_relaxed libarc4 /system_dlkm/lib/modules/libarc4.ko || true
  load_module_relaxed usbserial /system_dlkm/lib/modules/usbserial.ko || true

  load_module_strict cfg80211 "vendor_dlkm/lib/modules/cfg80211.ko" || return 1
  load_module_strict mac80211 "vendor_dlkm/lib/modules/mac80211.ko" || return 1
  load_module_strict qca_cld3_peach_v2 "vendor_dlkm/lib/modules/qca_cld3_peach_v2.ko" || return 1

  # Load known and newly bundled add-on drivers only after WLAN core is ready.
  load_module_relaxed zd1201 "$MODDIR/vendor_dlkm/lib/modules/zd1201.ko" || true
  load_module_relaxed rt2x00lib "$MODDIR/vendor_dlkm/lib/modules/rt2x00lib.ko" || true
  load_module_relaxed rt2800lib "$MODDIR/vendor_dlkm/lib/modules/rt2800lib.ko" || true
  load_module_relaxed rt2x00usb "$MODDIR/vendor_dlkm/lib/modules/rt2x00usb.ko" || true
  load_module_relaxed rt2800usb "$MODDIR/vendor_dlkm/lib/modules/rt2800usb.ko" || true
  load_extra_modules_from_rel "system_dlkm/lib/modules" || true
  load_extra_modules_from_rel "vendor_dlkm/lib/modules" || true

  finish_switch
  : > "$STATE_FLAG"
  if [ -x "$MODDIR/update_runtime_status.sh" ]; then
    "$MODDIR/update_runtime_status.sh" >/dev/null 2>&1 || true
  fi
  log_i "nethunter wlan stack switch complete"
  return 0
}

switch_to_stock() {
  log_i "restoring stock wlan stack"
  prepare_switch
  sleep 2

  if [ -x "$MODDIR/bind_mount_control.sh" ]; then
    "$MODDIR/bind_mount_control.sh" remove || true
  fi

  load_stock_module cfg80211 /vendor_dlkm/lib/modules/cfg80211.ko || return 1
  load_stock_module mac80211 /vendor_dlkm/lib/modules/mac80211.ko || return 1
  load_stock_module qca_cld3_peach_v2 /vendor_dlkm/lib/modules/qca_cld3_peach_v2.ko || return 1

  finish_switch
  rm -f "$STATE_FLAG"
  if [ -x "$MODDIR/update_runtime_status.sh" ]; then
    "$MODDIR/update_runtime_status.sh" >/dev/null 2>&1 || true
  fi
  log_i "stock wlan stack restore complete"
  return 0
}

print_status() {
  if [ -x "$MODDIR/update_runtime_status.sh" ]; then
    "$MODDIR/update_runtime_status.sh" >/dev/null 2>&1 || true
  fi
  if [ -f "$STATE_FLAG" ]; then
    log_i "wlan stack mode: nethunter"
  else
    log_i "wlan stack mode: stock"
  fi
  if is_loaded cfg80211; then
    log_i "cfg80211 loaded"
  else
    log_i "cfg80211 not loaded"
  fi
  if is_loaded mac80211; then
    log_i "mac80211 loaded"
  else
    log_i "mac80211 not loaded"
  fi
  if is_loaded qca_cld3_peach_v2; then
    log_i "qca_cld3_peach_v2 loaded"
  else
    log_i "qca_cld3_peach_v2 not loaded"
  fi
  if [ -x "$MODDIR/bind_mount_control.sh" ]; then
    "$MODDIR/bind_mount_control.sh" status
  fi
}

case "$1" in
  nethunter|on|enable)
    switch_to_nethunter
    ;;
  stock|off|disable|restore)
    switch_to_stock
    ;;
  status|"")
    print_status
    ;;
  *)
    echo "usage: $0 [status|nethunter|stock]" >&2
    exit 1
    ;;
esac

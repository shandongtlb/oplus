#!/system/bin/sh

MODDIR=${0%/*}
LOGTAG=op13_usb_arsenal

log_i() {
  log -t "$LOGTAG" "$*"
}

log_e() {
  log -t "$LOGTAG" "E: $*"
}

is_loaded() {
  grep -q "^$1 " /proc/modules 2>/dev/null
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

for delay in 8 16; do
  sleep "$delay"

  load_module rfkill /system_dlkm/lib/modules/rfkill.ko
  load_module libarc4 /system_dlkm/lib/modules/libarc4.ko
  load_module usbserial /system_dlkm/lib/modules/usbserial.ko

  load_module cfg80211 "$MODDIR/vendor_dlkm/lib/modules/cfg80211.ko" /vendor_dlkm/lib/modules/cfg80211.ko
  load_module mac80211 "$MODDIR/vendor_dlkm/lib/modules/mac80211.ko" /vendor_dlkm/lib/modules/mac80211.ko
  load_module wlan_firmware_service "$MODDIR/vendor_dlkm/lib/modules/wlan_firmware_service.ko" /vendor_dlkm/lib/modules/wlan_firmware_service.ko
  load_module cnss_prealloc "$MODDIR/vendor_dlkm/lib/modules/cnss_prealloc.ko" /vendor_dlkm/lib/modules/cnss_prealloc.ko
  load_module cnss_utils "$MODDIR/vendor_dlkm/lib/modules/cnss_utils.ko" /vendor_dlkm/lib/modules/cnss_utils.ko
  load_module cnss_plat_ipc_qmi_svc "$MODDIR/vendor_dlkm/lib/modules/cnss_plat_ipc_qmi_svc.ko" /vendor_dlkm/lib/modules/cnss_plat_ipc_qmi_svc.ko
  load_module cnss_nl "$MODDIR/vendor_dlkm/lib/modules/cnss_nl.ko" /vendor_dlkm/lib/modules/cnss_nl.ko
  load_module cnss2 "$MODDIR/vendor_dlkm/lib/modules/cnss2.ko" /vendor_dlkm/lib/modules/cnss2.ko
  load_module icnss2 "$MODDIR/vendor_dlkm/lib/modules/icnss2.ko" /vendor_dlkm/lib/modules/icnss2.ko

  load_module ch341 "$MODDIR/system_dlkm/lib/modules/ch341.ko"
  load_module pl2303 "$MODDIR/system_dlkm/lib/modules/pl2303.ko"
  load_module zd1201 "$MODDIR/vendor_dlkm/lib/modules/zd1201.ko" /vendor_dlkm/lib/modules/zd1201.ko
  load_module rt2x00lib "$MODDIR/vendor_dlkm/lib/modules/rt2x00lib.ko" /vendor_dlkm/lib/modules/rt2x00lib.ko
  load_module rt2800lib "$MODDIR/vendor_dlkm/lib/modules/rt2800lib.ko" /vendor_dlkm/lib/modules/rt2800lib.ko
  load_module rt2x00usb "$MODDIR/vendor_dlkm/lib/modules/rt2x00usb.ko" /vendor_dlkm/lib/modules/rt2x00usb.ko
  load_module rt2800usb "$MODDIR/vendor_dlkm/lib/modules/rt2800usb.ko" /vendor_dlkm/lib/modules/rt2800usb.ko
  load_module qca_cld3_kiwi_v2 "$MODDIR/vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko" /vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko

  if is_loaded ch341 && is_loaded pl2303 && is_loaded zd1201 && is_loaded rt2800usb && is_loaded qca_cld3_kiwi_v2; then
    log_i "all target modules are present"
    exit 0
  fi
done

log_e "some target modules are still not loaded after retry"
exit 0

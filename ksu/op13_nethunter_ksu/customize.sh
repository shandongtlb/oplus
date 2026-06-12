SKIPMOUNT=false
PROPFILE=false
POSTFSDATA=true
LATESTARTSERVICE=true

print_modname() {
  ui_print "*******************************"
  ui_print " OnePlus 13 ColorOS16 NH Mod  "
  ui_print "*******************************"
  ui_print "- Installs NetHunter USB add-on modules"
  ui_print "- Firmware staging at boot only"
  ui_print "- Bind and WLAN stack switches are manual"
}

set_permissions() {
  set_perm_recursive "$MODPATH" 0 0 0755 0644
  set_perm "$MODPATH/customize.sh" 0 0 0755
  if [ -f "$MODPATH/action.sh" ]; then
    set_perm "$MODPATH/action.sh" 0 0 0755
  fi
  if [ -f "$MODPATH/post-fs-data.sh" ]; then
    set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
  fi
  if [ -f "$MODPATH/update_runtime_status.sh" ]; then
    set_perm "$MODPATH/update_runtime_status.sh" 0 0 0755
  fi
  if [ -f "$MODPATH/show_status.sh" ]; then
    set_perm "$MODPATH/show_status.sh" 0 0 0755
  fi
  set_perm "$MODPATH/service.sh" 0 0 0755
  if [ -f "$MODPATH/bind_mount_control.sh" ]; then
    set_perm "$MODPATH/bind_mount_control.sh" 0 0 0755
  fi
  if [ -f "$MODPATH/wlan_stack_control.sh" ]; then
    set_perm "$MODPATH/wlan_stack_control.sh" 0 0 0755
  fi
  if [ -f "$MODPATH/enable_nethunter.sh" ]; then
    set_perm "$MODPATH/enable_nethunter.sh" 0 0 0755
  fi
  if [ -f "$MODPATH/restore_stock_wifi.sh" ]; then
    set_perm "$MODPATH/restore_stock_wifi.sh" 0 0 0755
  fi
  if [ -f "$MODPATH/uninstall.sh" ]; then
    set_perm "$MODPATH/uninstall.sh" 0 0 0755
  fi
  if [ -f "$MODPATH/monitor_control.sh" ]; then
    set_perm "$MODPATH/monitor_control.sh" 0 0 0755
  fi
}

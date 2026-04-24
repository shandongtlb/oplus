SKIPMOUNT=false
PROPFILE=false
POSTFSDATA=false
LATESTARTSERVICE=true

print_modname() {
  ui_print "*******************************"
  ui_print "       OP13 USB Arsenal       "
  ui_print "*******************************"
  ui_print "- Installs OP13-built USB add-on modules"
  ui_print "- Loads serial and USB Wi-Fi drivers at boot"
}

set_permissions() {
  set_perm_recursive "$MODPATH" 0 0 0755 0644
  set_perm "$MODPATH/customize.sh" 0 0 0755
  set_perm "$MODPATH/service.sh" 0 0 0755
  if [ -f "$MODPATH/uninstall.sh" ]; then
    set_perm "$MODPATH/uninstall.sh" 0 0 0755
  fi
}

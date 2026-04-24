SKIPMOUNT=false
PROPFILE=false
POSTFSDATA=false
LATESTARTSERVICE=true

print_modname() {
  ui_print "*******************************"
  ui_print " OnePlus 13 ColorOS16 NH Mod  "
  ui_print "*******************************"
  ui_print "- Installs NetHunter USB add-on modules"
  ui_print "- Reloads Wi-Fi stack after boot"
}

set_permissions() {
  set_perm_recursive "$MODPATH" 0 0 0755 0644
  set_perm "$MODPATH/customize.sh" 0 0 0755
  set_perm "$MODPATH/service.sh" 0 0 0755
  if [ -f "$MODPATH/uninstall.sh" ]; then
    set_perm "$MODPATH/uninstall.sh" 0 0 0755
  fi
}

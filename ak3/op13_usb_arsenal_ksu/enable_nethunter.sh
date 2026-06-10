#!/system/bin/sh
MODDIR=${0%/*}
exec sh "$MODDIR/wlan_stack_control.sh" nethunter "$@"

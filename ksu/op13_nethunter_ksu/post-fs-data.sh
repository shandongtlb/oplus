#!/system/bin/sh

MODDIR=${0%/*}

chmod 0755 "$MODDIR"/*.sh 2>/dev/null || true
chmod 0755 "$MODDIR"/monstart "$MODDIR"/monstop "$MODDIR"/scanap 2>/dev/null || true
chmod 0644 "$MODDIR"/module.prop 2>/dev/null || true
chmod 0644 "$MODDIR"/docs/* 2>/dev/null || true
exit 0

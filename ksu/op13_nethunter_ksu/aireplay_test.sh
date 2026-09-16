#!/system/bin/sh
# Run from Android root after monstart <channel>; no helper STA is created.
MODDIR=${0%/*}
KALI_ROOT=${KALI_ROOT:-/data/local/nhsystem/kalifs}
. "$MODDIR/module_identity.sh" || exit 1
verify_payload_stack || exit 1
if [ "$(cat /sys/module/qca_cld3_peach_v2/parameters/con_mode 2>/dev/null)" != 4 ]; then
  echo '先运行 monstart <频道>，再运行本测试。' >&2
  exit 1
fi
[ -x "$KALI_ROOT/usr/sbin/aireplay-ng" ] || {
  echo "Kali aireplay-ng missing: $KALI_ROOT" >&2; exit 1;
}
bound_sys=0
cleanup() {
  if [ "$bound_sys" = 1 ]; then umount "$KALI_ROOT/sys"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Aircrack 1.7 uses this sysfs path to select Radiotap TX headers.
if [ ! -e "$KALI_ROOT/sys/class/net/wlan0/phy80211/subsystem" ]; then
  if awk -v p="$(readlink -f "$KALI_ROOT")/sys" '$2 == p {found=1} END {exit !found}' /proc/mounts; then
    echo 'Kali /sys 已挂载但缺少 phy80211，请检查 chroot 挂载环境。' >&2
    exit 1
  fi
  mount -o bind /sys "$KALI_ROOT/sys" || exit 1
  bound_sys=1
fi
/system/bin/chroot "$KALI_ROOT" /usr/bin/env \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  /usr/bin/timeout 120 /usr/sbin/aireplay-ng -9 --ignore-negative-one wlan0
rc=$?
echo '注：Found APs 仅证明接收；Injection is working / 实际探测响应才是测试结果。'
exit "$rc"

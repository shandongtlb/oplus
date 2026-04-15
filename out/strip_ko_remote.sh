set -e
TOOL=/root/oneplus13-kernel-b/kernel_platform/prebuilts/clang/host/linux-x86/clang-r510928/bin/llvm-objcopy
WORK=/tmp/op13_usb_arsenal_strip
rm -rf "$WORK"
mkdir -p "$WORK/system_dlkm" "$WORK/vendor_dlkm"
cp /root/oneplus13-kernel-b/device/qcom/sun-kernel/system_dlkm/flatten/lib/modules/ch341.ko "$WORK/system_dlkm/"
cp /root/oneplus13-kernel-b/device/qcom/sun-kernel/system_dlkm/flatten/lib/modules/pl2303.ko "$WORK/system_dlkm/"
cp /root/oneplus13-kernel-b/device/qcom/sun-kernel/vendor_dlkm/cfg80211.ko "$WORK/vendor_dlkm/"
cp /root/oneplus13-kernel-b/device/qcom/sun-kernel/vendor_dlkm/cnss_nl.ko "$WORK/vendor_dlkm/"
cp /root/oneplus13-kernel-b/device/qcom/sun-kernel/vendor_dlkm/cnss_plat_ipc_qmi_svc.ko "$WORK/vendor_dlkm/"
cp /root/oneplus13-kernel-b/device/qcom/sun-kernel/vendor_dlkm/cnss_prealloc.ko "$WORK/vendor_dlkm/"
cp /root/oneplus13-kernel-b/device/qcom/sun-kernel/vendor_dlkm/cnss_utils.ko "$WORK/vendor_dlkm/"
cp /root/oneplus13-kernel-b/device/qcom/sun-kernel/vendor_dlkm/cnss2.ko "$WORK/vendor_dlkm/"
cp /root/oneplus13-kernel-b/device/qcom/sun-kernel/vendor_dlkm/icnss2.ko "$WORK/vendor_dlkm/"
cp /root/oneplus13-kernel-b/device/qcom/sun-kernel/vendor_dlkm/mac80211.ko "$WORK/vendor_dlkm/"
cp /root/oneplus13-kernel-b/device/qcom/sun-kernel/vendor_dlkm/qca_cld3_kiwi_v2.ko "$WORK/vendor_dlkm/"
cp /root/oneplus13-kernel-b/device/qcom/sun-kernel/vendor_dlkm/rt2800lib.ko "$WORK/vendor_dlkm/"
cp /root/oneplus13-kernel-b/device/qcom/sun-kernel/vendor_dlkm/rt2800usb.ko "$WORK/vendor_dlkm/"
cp /root/oneplus13-kernel-b/device/qcom/sun-kernel/vendor_dlkm/rt2x00lib.ko "$WORK/vendor_dlkm/"
cp /root/oneplus13-kernel-b/device/qcom/sun-kernel/vendor_dlkm/rt2x00usb.ko "$WORK/vendor_dlkm/"
cp /root/oneplus13-kernel-b/device/qcom/sun-kernel/vendor_dlkm/wlan_firmware_service.ko "$WORK/vendor_dlkm/"
cp /root/oneplus13-kernel-b/device/qcom/sun-kernel/vendor_dlkm/zd1201.ko "$WORK/vendor_dlkm/"
printf 'before\n'
find "$WORK" -type f -name '*.ko' -printf '%P %s\n' | sort
find "$WORK" -type f -name '*.ko' -print0 | xargs -0 -n 1 "$TOOL" --strip-debug
printf 'after\n'
find "$WORK" -type f -name '*.ko' -printf '%P %s\n' | sort
printf 'modinfo\n'
modinfo "$WORK/vendor_dlkm/qca_cld3_kiwi_v2.ko" | sed -n '1,12p'

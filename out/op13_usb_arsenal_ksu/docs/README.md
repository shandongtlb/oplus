# OP13 USB Arsenal KernelSU Module

This package is built from the NUC outputs described in `说明/op13_kernel_work_report_zh.md`.
All bundled `.ko` files were processed with `llvm-objcopy --strip-debug`.

Build markers:
- `vendor_dlkm` modules carry `vermagic: 6.6.89-android15-8-o-gbb0d8f037ce5-4k`
- `system_dlkm` modules carry `vermagic: 6.6.89-android15-8-o-g9f334ee47b7f-4k`

Included modules:
- `system_dlkm`: `ch341.ko`, `pl2303.ko`
- `vendor_dlkm`: `cfg80211.ko`, `mac80211.ko`
- `vendor_dlkm`: `cnss2.ko`, `icnss2.ko`, `cnss_nl.ko`, `cnss_prealloc.ko`, `cnss_utils.ko`, `cnss_plat_ipc_qmi_svc.ko`, `wlan_firmware_service.ko`, `qca_cld3_kiwi_v2.ko`
- `vendor_dlkm`: `zd1201.ko`, `rt2x00lib.ko`, `rt2x00usb.ko`, `rt2800lib.ko`, `rt2800usb.ko`

Boot-time load flow:
- Reuse stock low-level dependency modules when present: `usbserial`, `rfkill`, `libarc4`
- Prefer bundled vendor WLAN modules from this module directory: `cfg80211/mac80211/cnss/qca_cld3`
- Then load the bundled USB add-on drivers

Important limitations:
- This package does not replace `boot.img` or the running kernel.
- Stripping changes the module binary, so any embedded module signature should no longer be treated as valid proof of origin.
- If the stock WLAN stack is already loaded before the module service runs, the running device may still keep using the already-loaded stock modules until a reboot or manual reload.
- Any capability that depends on kernel config or ABI changes outside these `.ko` files is not magically fixed by the module alone.

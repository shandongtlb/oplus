# OnePlus 13 ColorOS16 NetHunter KernelSU Module

This package is built from the NUC outputs described in `说明/op13_kernel_work_report_zh.md`.
All bundled `.ko` files were processed with `llvm-objcopy --strip-debug`.

Build markers:
- `vendor_dlkm` modules carry `vermagic: 6.6.89-android15-8-o-gbb0d8f037ce5-4k`
- `system_dlkm` modules carry `vermagic: 6.6.89-android15-8-o-g9f334ee47b7f-4k`

Included modules:
- `system_dlkm`: `ch341.ko`, `pl2303.ko`
- `vendor_dlkm`: `zd1201.ko`, `rt2x00lib.ko`, `rt2x00usb.ko`, `rt2800lib.ko`, `rt2800usb.ko`

Boot-time load flow:
- Reuse stock low-level dependency modules when present: `usbserial`, `rfkill`, `libarc4`
- Keep the stock `cnss*` platform stack and built-in WLAN stack in place
- Stage `rt2870.bin` into `/mnt/vendor/persist/copy/` from the module's bundled `vendor/firmware`
- Then load the bundled USB add-on drivers

Runtime note:
- Seeing `rt2800*.ko` in `/proc/modules` but not under `/vendor_dlkm/lib/modules` is expected for this package when the ROM does not magic-mount `vendor_dlkm`; the service loads them directly from the module-private path.

Important limitations:
- This package does not replace `boot.img` or the running kernel.
- Stripping changes the module binary, so any embedded module signature should no longer be treated as valid proof of origin.
- If the stock WLAN stack is already loaded before the module service runs, the running device may still keep using the already-loaded stock modules until a reboot or manual reload.
- Any capability that depends on kernel config or ABI changes outside these `.ko` files is not magically fixed by the module alone.

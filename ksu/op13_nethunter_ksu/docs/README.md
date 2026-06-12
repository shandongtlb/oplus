# OnePlus 13 ColorOS16 NetHunter KernelSU Module

This package is built from the NUC outputs described in `说明/op13_kernel_work_report_zh.md`.
All bundled `.ko` files were processed with `llvm-objcopy --strip-debug`.

Build markers:
- `vendor_dlkm` modules carry `vermagic: 6.6.89-android15-8-o-gbb0d8f037ce5-4k`
- `system_dlkm` modules carry `vermagic: 6.6.89-android15-8-o-g9f334ee47b7f-4k`

Included modules:
- `system_dlkm`: `ch341.ko`, `pl2303.ko`
- `vendor_dlkm`: `cfg80211.ko`, `mac80211.ko`, `qca_cld3_peach_v2.ko`, `zd1201.ko`, `rt2x00lib.ko`, `rt2x00usb.ko`, `rt2800lib.ko`, `rt2800usb.ko`
- Additional `.ko` files placed under `system_dlkm/lib/modules/` or `vendor_dlkm/lib/modules/` are auto-loaded after the known WLAN/USB dependency order is applied

Boot-time behavior:
- Keep the stock `cnss*` platform stack and normal WLAN stack in place
- Stage `rt2870.bin` into `/mnt/vendor/persist/copy/` from the bundled `vendor/firmware`
- Do not hot-switch `cfg80211`, `mac80211`, or `qca_cld3_peach_v2` during boot
- `post-fs-data.sh` restores executable bits for module scripts after install and boot

Manual controls:
- `action.sh`
  - KSU Action button: one-click toggle between stock ↔ nethunter WLAN stack
  - if current mode is stock: enable bind mounts, then switch to the NetHunter WLAN stack
  - if current mode is NetHunter: restore the stock WLAN stack and remove bind mounts
- **Monitor mode + injection** (requires nethunter stack active)
  - `monstart [freq_MHz]` — enter monitor mode
    - no freq: capture/scan only (airodump can hop all channels)
    - with freq (e.g. `monstart 5745`): locks channel + builds injection helper vdev
  - `monstop` — leave monitor, restore normal WiFi
  - See `docs/QUICK_MONITOR_GUIDE.md` for usage + injection notes
  - **Note**: OnePlus 13's qcacld FullMAC requires a locked channel for injection (FW rejects TX on monitor vdev); the patched driver auto-creates a hidden STA helper vdev when freq is set
- `runtime_status.txt`
  - generated runtime snapshot in the installed module directory
- `show_status.sh`
  - refresh and print `runtime_status.txt`
- module description
  - `update_runtime_status.sh` rewrites `module.prop` `description=` to only show the current short status
  - format:
    - `mode:stock | bind:disabled | fw:staged`
    - `mode:nethunter | bind:enabled | fw:staged`
  - some module managers cache the description, so you may need to reopen the module page to see the latest value
- `bind_mount_control.sh status`
  - show whether bind mode is enabled
- `bind_mount_control.sh on`
  - enable bind mounts for:
    - `/vendor_dlkm/lib/modules/cfg80211.ko`
    - `/vendor_dlkm/lib/modules/mac80211.ko`
    - `/vendor_dlkm/lib/modules/qca_cld3_peach_v2.ko`
- `bind_mount_control.sh off`
  - remove those bind mounts and disable them for future boots
- bind behavior is coupled to stack mode
  - when stack mode is `stock`, bind is treated as disabled and boot-time service removes any stale bind mounts
  - bind mounts are only auto-applied during boot when stack mode is `nethunter`
- `wlan_stack_control.sh nethunter`
  - switch the running WLAN stack to the bundled module set
- `wlan_stack_control.sh stock`
  - restore the running WLAN stack to stock modules
- `wlan_stack_control.sh status`
  - show current core module, bind state, and current stack mode
- `enable_nethunter.sh`
  - wrapper for `wlan_stack_control.sh nethunter`
- `restore_stock_wifi.sh`
  - wrapper for `wlan_stack_control.sh stock`

Design notes:
- `cfg80211`, `mac80211`, and `qca_cld3_peach_v2` are treated as a matched set
- `cnss*` is never unloaded or replaced
- USB add-on drivers stay optional and are loaded only when the WLAN stack switch is requested
- Extra bundled `.ko` files are loaded with several retry passes so simple dependency ordering issues can resolve without hardcoding every new module name

Important limitations:
- This package does not replace `boot.img` or the running kernel
- Stripping changes the module binary, so any embedded module signature should no longer be treated as valid proof of origin
- Normal Wi‑Fi should work after boot as long as you do not manually switch the WLAN stack
- Any capability that depends on kernel config or firmware behavior outside these `.ko` files is not magically fixed by the module alone

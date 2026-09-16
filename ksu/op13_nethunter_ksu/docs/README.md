# OnePlus 13 ColorOS16 NetHunter KernelSU Module

This package is the OnePlus 13 `peach_v2` native-global rebuild from `补丁/native_global/`.
v4 adds management-frame TX input validation, queue control and DMA ownership protection.
Firmware TX acceptance and RF reception are unverified on this package. Missing
completion at WMA close quarantines buffers and module references until reboot.
See `NATIVE_INJECTION.md` and `BUILD_INFO.txt`.

The three WLAN `.ko` files come from the integrated `sun perf` build with
`qca_inject/0001-add-qcacldko.patch` applied, and are processed with `llvm-strip --strip-debug`.

Build markers:
- `cfg80211/mac80211` release: `6.6.118-android15-8-o-g6028f47fadda-4k`
- `qca_cld3_peach_v2` release: `6.6.118-android15-8-o-4k`
- The SCM suffix differs; module version flags and checked symbol CRCs match. See `BUILD_INFO.txt`.
- `system_dlkm` dependency modules remain ROM-provided and may use a different vermagic

Included modules:
- `vendor_dlkm`: `cfg80211.ko`, `mac80211.ko`, `qca_cld3_peach_v2.ko`
- This native-global package contains only those three `.ko` files. CNSS and other platform dependencies come from the ROM; USB add-on modules are optional and are not included in this build.
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
  - `monstart [freq_MHz]` — switch `wlan0` into native global monitor mode
    - no freq: capture/scan only (airodump can hop all channels)
    - with freq (e.g. `monstart 5745`): locks the global monitor channel for injection
  - `monstop` — leave monitor, restore normal WiFi
  - See `docs/QUICK_MONITOR_GUIDE.md` for usage + injection notes
  - **Note**: the peach_v2 path uses Qualcomm global monitor mode (`con_mode=4`) and submits TX directly on the monitor vdev; no `wlan0mon` or hidden STA/helper vdev is created
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

# OP13 NetHunter `msm`-Only Scope Recheck

## Boundary

This note only keeps items that are realistic when:

- you do **not** modify `kernel_platform/common`
- you do **not** rely on new `system_dlkm` / GKI modules
- you only continue through the current `msm/vendor_dlkm` route

## What Is Already Done

Confirmed completed in the current OP13 work:

- `qcacld3` `kiwi_v2` integration into `vendor_dlkm`
- mac80211 / monitor / injection related porting
- `rtl8187` and `zd1211rw` injection driver tweaks
- `rt2800usb/rt2x00usb` support in `vendor_dlkm`

These are still the correct direction for an `msm`-only workflow.

## What Must Be Excluded

The following are **not** good `msm`-only targets in this tree, because they
belong to the GKI / `system_dlkm` side:

- Bluetooth Arsenal core modules
  - `CONFIG_BT_HCIBTUSB`
  - `CONFIG_BT_HCIVHCI`
  - related `btusb.ko` / `hci_vhci.ko`
- existing GKI Bluetooth stack modules
  - `bluetooth.ko`
  - `hci_uart.ko`
  - `btbcm.ko`
  - `btqca.ko`
- USB Arsenal core `configfs` capability set
  - `CONFIG_USB_CONFIGFS`
  - `CONFIG_USB_CONFIGFS_F_HID`
  - related gadget core options
- USB Ethernet / generic system modules already coming from GKI
  - `CONFIG_USB_RTL8150`
  - `CONFIG_USB_RTL8152`
  - `CONFIG_USB_USBNET`

Reason:

- these are part of the GKI / `system_dlkm` module family in this mixed build
- forcing them from `msm` is the wrong ownership boundary

## Rechecked Findings

### 1. USB Arsenal

Most important USB Arsenal pieces are already present in the final `sun_perf`
config, including:

- `CONFIG_USB_ACM=m`
- `CONFIG_USB_CONFIGFS=y`
- `CONFIG_USB_CONFIGFS_SERIAL=y`
- `CONFIG_USB_CONFIGFS_ACM=y`
- `CONFIG_USB_CONFIGFS_NCM=y`
- `CONFIG_USB_CONFIGFS_ECM=y`
- `CONFIG_USB_CONFIGFS_RNDIS=m`
- `CONFIG_USB_CONFIGFS_EEM=y`
- `CONFIG_USB_CONFIGFS_MASS_STORAGE=y`
- `CONFIG_USB_CONFIGFS_F_FS=y`
- `CONFIG_USB_CONFIGFS_F_HID=y`

Therefore USB Arsenal is **not** the current bottleneck for `msm` work.

### 2. Bluetooth Arsenal

The Bluetooth stack already present in the final config includes:

- `CONFIG_BT=m`
- `CONFIG_BT_RFCOMM=m`
- `CONFIG_BT_HIDP=m`
- `CONFIG_BT_HCIBTSDIO=m`
- `CONFIG_BT_HCIUART=m`
- `CONFIG_BT_HCIUART_LL=y`
- `CONFIG_BT_HCIUART_BCM=y`
- `CONFIG_BT_HCIUART_QCA=y`

But the missing NetHunter-style additions:

- `CONFIG_BT_HCIBTUSB`
- `CONFIG_BT_HCIVHCI`

should be treated as GKI / `system_dlkm` scope, not `msm/vendor_dlkm` scope.

Conclusion:

- do not continue the previous Bluetooth Arsenal patch direction

## What Is Still Feasible From `msm`

The practical remaining NetHunter direction is to continue expanding
**external USB Wi-Fi driver coverage** through `vendor_dlkm`.

The following drivers are present in `kernel_platform/msm-kernel/drivers` and
fit the same overall direction as the already completed `rt3070l` work:

- `ATH6KL_USB`
- `MT7601U`
- `RT2500USB`
- `RT73USB`
- `RTL8192CU`
- `RTL8XXXU`
- `USB_ZD1201`
- `USB_NET_RNDIS_WLAN`

Higher-risk candidates:

- `ATH9K_HTC`
- `CARL9170`

Why higher risk:

- they can pull LED-related paths through mac80211
- that may create the same kind of mixed-build friction already seen with
  `rt2x00` LED support

## Suggested Next Order

Recommended `msm`-only priority:

1. `MT7601U`
2. `RTL8192CU`
3. `RTL8XXXU`
4. `ATH6KL_USB`
5. `RT2500USB` / `RT73USB`
6. `USB_ZD1201`
7. `USB_NET_RNDIS_WLAN`

Defer until later:

- `ATH9K_HTC`
- `CARL9170`

## Bottom Line

After rechecking the tree and build ownership:

- Bluetooth Arsenal is **not** the next correct `msm` patch target
- USB Arsenal is mostly already present
- the clean remaining `msm` path is continued work on external USB Wi-Fi
  driver enablement through `vendor_dlkm`

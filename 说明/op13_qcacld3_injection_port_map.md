# OP13 QCACLD-3.0 Injection Port Map

Base patch:
- Upstream commit: `8f0698bf92abef517980fe9a84615cd8bad16622`
- NetHunter raw patch: identical to the upstream raw patch

Port policy for OP13:
- Port everything from the upstream patch except the pure HDD debug layer.
- Keep tests, integration helpers, security helpers, and WMA completion bookkeeping.
- Do not blindly drop symbols just because they contain `debug` in the name.

Important exception:
- `core/wma/src/wma_frame_inject.c` contains a `debug cache`, but it is not optional debugfs code.
- That cache tracks desc IDs, tx buffers, and completion cleanup.
- Keep it.

## Skip List

Do not port these files:
- `drivers/staging/qcacld-3.0/core/hdd/inc/wlan_hdd_frame_inject_debug.h`
- `drivers/staging/qcacld-3.0/core/hdd/src/wlan_hdd_frame_inject_debug.c`

Do not port these build/config fragments as-is:
- `HDD_OBJS += $(HDD_SRC_DIR)/wlan_hdd_frame_inject_debug.o`
- `DEVELOPER_DISABLE_BUILD_TIMESTAMP := y`
- `CONFIG_FEATURE_MEMDUMP_ENABLE := y`

Do not keep these debugfs/sysfs calls in the final OP13 port:
- `hdd_injection_create_debugfs_entries()`
- `hdd_injection_remove_debugfs_entries()`
- `hdd_injection_init_debug_interfaces()`
- `hdd_injection_deinit_debug_interfaces()`
- `hdd_injection_get_global_config()`
- `hdd_injection_is_globally_enabled()`

## Tree Split

### 1. MSM/Common Kernel Tree

These belong in the common kernel tree, not the vendor WLAN tree:
- `include/net/mac80211.h`
- `net/mac80211/cfg.c`
- `net/mac80211/tx.c`
- `net/wireless/chan.c`

Reason:
- These are mac80211/cfg80211 core changes used by monitor channel switching and injected-frame TX behavior.

### 2. Vendor QCA Host Common Tree

These belong in the vendor QCA host common tree:
- `drivers/staging/qca-wifi-host-cmn/os_if/linux/qca_vendor.h`

Reason:
- Vendor command definitions live with QCA host-common, even if QCACLD is split into a separate vendor module.

### 3. Vendor QCACLD-3.0 Tree

These belong in the vendor QCACLD-3.0 tree:
- `drivers/staging/qcacld-3.0/Kbuild`
- `drivers/staging/qcacld-3.0/configs/default_defconfig`
- `drivers/staging/qcacld-3.0/core/dp/txrx/ol_tx.c`
- `drivers/staging/qcacld-3.0/core/dp/txrx/ol_tx_desc.c`
- `drivers/staging/qcacld-3.0/core/dp/txrx/ol_txrx.c`
- `drivers/staging/qcacld-3.0/core/dp/txrx/ol_txrx_flow_control.c`
- `drivers/staging/qcacld-3.0/core/hdd/inc/wlan_hdd_bcn_recv.h`
- `drivers/staging/qcacld-3.0/core/hdd/inc/wlan_hdd_frame_inject.h`
- `drivers/staging/qcacld-3.0/core/hdd/inc/wlan_hdd_frame_inject_integration.h`
- `drivers/staging/qcacld-3.0/core/hdd/inc/wlan_hdd_frame_inject_security_test.h`
- `drivers/staging/qcacld-3.0/core/hdd/inc/wlan_hdd_frame_inject_test.h`
- `drivers/staging/qcacld-3.0/core/hdd/inc/wlan_hdd_frame_validate.h`
- `drivers/staging/qcacld-3.0/core/hdd/inc/wlan_hdd_frame_validate_test.h`
- `drivers/staging/qcacld-3.0/core/hdd/inc/wlan_hdd_inject_security.h`
- `drivers/staging/qcacld-3.0/core/hdd/inc/wlan_hdd_main.h`
- `drivers/staging/qcacld-3.0/core/hdd/src/wlan_hdd_cfg80211.c`
- `drivers/staging/qcacld-3.0/core/hdd/src/wlan_hdd_frame_inject.c`
- `drivers/staging/qcacld-3.0/core/hdd/src/wlan_hdd_frame_inject_comprehensive_test.c`
- `drivers/staging/qcacld-3.0/core/hdd/src/wlan_hdd_frame_inject_integration.c`
- `drivers/staging/qcacld-3.0/core/hdd/src/wlan_hdd_frame_inject_security_test.c`
- `drivers/staging/qcacld-3.0/core/hdd/src/wlan_hdd_frame_inject_test.c`
- `drivers/staging/qcacld-3.0/core/hdd/src/wlan_hdd_frame_validate.c`
- `drivers/staging/qcacld-3.0/core/hdd/src/wlan_hdd_frame_validate_test.c`
- `drivers/staging/qcacld-3.0/core/hdd/src/wlan_hdd_hostapd.c`
- `drivers/staging/qcacld-3.0/core/hdd/src/wlan_hdd_inject_security.c`
- `drivers/staging/qcacld-3.0/core/hdd/src/wlan_hdd_ioctl.c`
- `drivers/staging/qcacld-3.0/core/hdd/src/wlan_hdd_main.c`
- `drivers/staging/qcacld-3.0/core/hdd/src/wlan_hdd_rx_monitor.c`
- `drivers/staging/qcacld-3.0/core/hdd/src/wlan_hdd_rx_monitor.h`
- `drivers/staging/qcacld-3.0/core/hdd/src/wlan_hdd_tx_rx.c`
- `drivers/staging/qcacld-3.0/core/hdd/src/wlan_hdd_wext.c`
- `drivers/staging/qcacld-3.0/core/mac/src/pe/lim/lim_process_action_frame.c`
- `drivers/staging/qcacld-3.0/core/mac/src/pe/lim/lim_process_sme_req_messages.c`
- `drivers/staging/qcacld-3.0/core/sme/src/common/sme_api.c`
- `drivers/staging/qcacld-3.0/core/sme/src/csr/csr_api_roam.c`
- `drivers/staging/qcacld-3.0/core/wma/inc/wma_frame_inject.h`
- `drivers/staging/qcacld-3.0/core/wma/src/wma_data.c`
- `drivers/staging/qcacld-3.0/core/wma/src/wma_dev_if.c`
- `drivers/staging/qcacld-3.0/core/wma/src/wma_frame_inject.c`
- `drivers/staging/qcacld-3.0/core/wma/src/wma_main.c`
- `drivers/staging/qcacld-3.0/core/wma/src/wma_mgmt.c`
- `drivers/staging/qcacld-3.0/core/wma/src/wma_utils.c`

## Keep/Drop Notes By Area

### Build and Config

Keep:
- `CONFIG_FEATURE_FRAME_INJECTION_SUPPORT := y`
- object additions for:
  - `wlan_hdd_frame_inject.o`
  - `wlan_hdd_frame_validate.o`
  - `wlan_hdd_inject_security.o`
  - test objects if you want the upstream test coverage
  - `wma_frame_inject.o`

Drop:
- `wlan_hdd_frame_inject_debug.o`
- `DEVELOPER_DISABLE_BUILD_TIMESTAMP := y`
- `CONFIG_FEATURE_MEMDUMP_ENABLE := y`

### HDD Injection Core

Keep:
- `wlan_hdd_frame_inject.c`
- `wlan_hdd_frame_validate.c`
- `wlan_hdd_inject_security.c`
- monitor TX hook in `wlan_hdd_tx_rx.c`
- monitor channel reporting in `wlan_hdd_cfg80211.c` and `wlan_hdd_wext.c`
- monitor enable/disable hooks in `wlan_hdd_rx_monitor.c`
- IOCTL/vendor plumbing in `wlan_hdd_ioctl.c` and `qca_vendor.h`

Drop or rewrite:
- adapter debugfs directory storage
- global debugfs/sysfs init and teardown
- global enable/config fetches that only exist in the dropped HDD debug layer

### WMA/DP Core

Keep all of this:
- WMA injection queue
- hidden helper vdev creation/teardown
- management TX completion handling
- descriptor ID tracking
- inflight tx buffer bookkeeping
- mgmt pool robustness changes in DP flow control

Reason:
- This is the real functional injection path.
- Removing it will break TX completion, cleanup, or firmware routing.

### Tests

Keep:
- `wlan_hdd_frame_inject_comprehensive_test.c`
- `wlan_hdd_frame_inject_integration.c`
- `wlan_hdd_frame_inject_security_test.c`
- `wlan_hdd_frame_inject_test.c`
- `wlan_hdd_frame_validate_test.c`
- the corresponding test headers

But adjust:
- remove the test cases that explicitly validate debug interface init/create/remove/deinit

## Required Edits Because HDD Debug Layer Is Dropped

### A. `wlan_hdd_frame_inject.h`

Upstream includes:
- `wlan_hdd_frame_inject_debug.h`

For OP13:
- remove that include
- keep the logging macros, but rebind them locally to existing HDD/QDF logging

Suggested replacement:
- `hdd_inject_log_error` -> `hdd_err`
- `hdd_inject_log_warn` -> `hdd_warn`
- `hdd_inject_log_info` -> `hdd_info`
- `hdd_inject_log_debug` -> `hdd_debug`
- `hdd_inject_log_verbose` -> `hdd_debug`

If your tree already uses QDF trace macros in HDD, bind to those instead.

### B. `wlan_hdd_frame_inject.c`

Remove:
- `hdd_injection_create_debugfs_entries(adapter)`
- `hdd_injection_remove_debugfs_entries(adapter)`
- global gate:
  - `if (!hdd_injection_is_globally_enabled())`

Replace global enable behavior with one of these:
- simplest: default injection enabled in the adapter security config
- or: gate on `adapter->injection_ctx->security_ctx.config.injection_enabled`

### C. `wlan_hdd_inject_security.c`

Upstream pulls initial config from the dropped debug layer:
- `hdd_injection_get_global_config(&security_ctx->config);`

For OP13:
- initialize `security_ctx->config` directly in code
- set sane defaults there

Recommended defaults:
- `injection_enabled = true`
- `max_frame_size = HDD_FRAME_INJECT_MAX_SIZE`
- `max_queue_size = HDD_FRAME_INJECT_MAX_QUEUE_SIZE`
- `require_monitor_mode = true`
- `log_level = 3`

### D. `wlan_hdd_main.c`

Remove:
- `hdd_injection_init_debug_interfaces()`
- `hdd_injection_deinit_debug_interfaces()`

Also remove any include that was only needed for those calls.

### E. `wlan_hdd_frame_inject_test.c`

Keep the file, but remove the subtests for:
- global debug interface init
- adapter debugfs entry create/remove
- explicit debug logging validation
- debug interface deinit

## Minimum Port Order

Recommended order:
1. Common kernel:
   - `include/net/mac80211.h`
   - `net/mac80211/cfg.c`
   - `net/mac80211/tx.c`
   - `net/wireless/chan.c`
2. Vendor host-common:
   - `qca_vendor.h`
3. QCACLD build/config:
   - `Kbuild`
   - `default_defconfig`
4. DP/WMA foundation:
   - `ol_tx_desc.c`
   - `ol_txrx.c`
   - `ol_txrx_flow_control.c`
   - `wma_frame_inject.h`
   - `wma_data.c`
   - `wma_mgmt.c`
   - `wma_main.c`
   - `wma_frame_inject.c`
5. HDD integration:
   - `wlan_hdd_frame_inject.h`
   - `wlan_hdd_frame_validate.h/.c`
   - `wlan_hdd_inject_security.h/.c`
   - `wlan_hdd_cfg80211.c`
   - `wlan_hdd_tx_rx.c`
   - `wlan_hdd_rx_monitor.c`
   - `wlan_hdd_wext.c`
   - `wlan_hdd_ioctl.c`
   - `wlan_hdd_main.c`
   - `wlan_hdd_frame_inject.c`
6. MAC/SME compatibility fixes:
   - `lim_process_action_frame.c`
   - `lim_process_sme_req_messages.c`
   - `sme_api.c`
   - `csr_api_roam.c`
7. Tests:
   - all upstream test files except pure debug tests/calls

## Practical Rule

When the source tree differs:
- port by function, not by path
- reuse upstream logic blocks
- re-resolve includes and symbols against your vendor tree
- keep common-kernel edits in the msm tree
- keep QCACLD/QCA host changes in the vendor WLAN tree

If a symbol mismatch appears:
- trust the subsystem placement first
- then adapt the function signature to the local tree snapshot
- do not move common-kernel changes into vendor just because the paths differ

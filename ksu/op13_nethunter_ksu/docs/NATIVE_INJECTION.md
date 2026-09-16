# peach_v2 global monitor RX with internal STA TX (experimental)

The public interface remains native `wlan0` in `con_mode=4`. The monitor vdev
owns RX, host references and native management descriptors. TX uses a separate
firmware-only STA helper on the confirmed monitor channel, following sam's
`0001-wlan-native-monitor-injection.patch`. No extra netdev is created.

This replaces v5's direct monitor-vdev WMI TX, which returned DISCARD for the
reported probe/auth frames. Global mode does not require TX on the monitor
vdev. The old oplus patches are supporting references, not the port baseline.
On 2026-09-16 the user reported successful broadcast and directed Probe testing
on channel 1 with v6. See the device evidence and remaining scope below.

Lifecycle follows sam: confirmed START and self-peer creation; FIFO unicast
peer changes after old inflight TX drains; confirmed peer deletion, STOP and
DELETE; native descriptor/peer bookkeeping; one ordered worker and a bounded
64-slot coherent DMA pool with at most 32 inflight frames. Early completions
cannot recycle a submitting slot. Lost completions retain uncertain DMA and
request recovery. Only the existing platform's fresh firmware reinit/idle
restart can reclaim a retired pool; CNSS/MHI are not replaced.

Mode exit quiesces TX before queuing the driver transaction or acquiring RTNL.
Administrative `ip link down` pauses host traffic and keeps the firmware
session; `up` resumes. Full exit uses con_mode/monstop. Recovery recreates TX
only after restoring the monitor channel and clearing recovery state, and an
accepted mode-exit request remains latched across SSR.

TX accepts Radiotap plus 24–2048 bytes of management frame. Raw callers must
prepend an empty eight-byte Radiotap header. F_FCS strips trailing FCS;
DATAPAD, control/data frames and invalid lengths are rejected. Other Radiotap
hints do not change firmware rate, retries, power or sequence handling.
Probe/auth keep ordinary flags by default. Deauth/disassoc retain wrong-key;
`mon_tx_wrong_key` remains an optional root diagnostic override. No flag change
is claimed as the fix for v5's DISCARD.

The helper is limited to enabled non-passive 2.4/5 GHz 20 MHz channels,
excluding channel 14 and DFS. Wider 40/80/160 MHz monitor requests are RX-only,
subject to complete channel/center validation and firmware capability. Channel
changes stop the old helper first; failed teardown blocks retuning. Repeating
the same channel skips RX restart while retrying optional helper setup.

This v7 package includes follow-up fixes for two v6 device findings. The
unified build succeeded; v7 has not yet been tested on the phone:

- Monitor WEXT name/mode/frequency/range handlers follow sam's
  `0001-wlan-native-monitor-injection.patch`, with `wireless_handlers` wired
  at monitor setup. Reads use peach's confirmed-channel getter. Reads and
  same-channel confirmation serialize with nl80211; overlap returns EBUSY.
  WEXT may confirm the current 20 MHz channel but cannot retune it; use `iw`
  for channel changes. The numeric decoder rejects invalid exponents/channel
  numbers and fractional MHz instead of silently truncating them.
- RX-only and unavailable TX drain to the rejecting transmit path instead of
  stopping the netdev queue indefinitely. Normal running-helper capacity
  pressure still stops/wakes the queue. Before a real retune or failed-helper
  retry, HDD blocks admission and uses `dev_deactivate()` under a short RTNL
  trylock to join/reset the host qdisc. RTNL contention returns EBUSY before
  changing the helper. RTNL is released before any firmware wait. Carrier-off
  and an admission gate protect the transition against reopen and qdisc-bypass
  traffic. Every exit releases the gate. Carrier-on lets linkwatch reactivate
  the empty qdisc; packets arriving before activation are dropped. This also
  works when a wide channel has no WMA netdev reference. An already-working
  same-channel confirmation preserves the helper and queued traffic.

The qdisc tests model kernel networking primitives while executing production
HDD/WMA functions. They do not establish real kernel lock scheduling or device
behavior. Repeat the observed 80 MHz one-frame -> 20 MHz test with v7, check normal backpressure, and check WEXT without `--ignore-negative-one`.

Diagnostics under `/sys/module/qca_cld3_peach_v2/parameters/`:

- `inject_stats`: admission, queue, inflight, timeout and retained-pool counts.
- `inject_tx_status`: separate firmware OK, DISCARD, INSPECT and NO_ACK counts;
  host failures/drains never count as firmware success.
- `inject_peer_setup_only`: create peers but suppress TX for diagnosis.

`NETHUNTER-INJ` logs include owner/helper IDs and sampled submissions and
completions. Successful WMI submission is not proof of RF transmission;
firmware OK likewise needs independent reception to establish RF success.

Host checks from the qcacld directory (ASan/UBSan with production code):

```
python3 tests/test_monitor_radiotap.py
python3 tests/test_native_injection.py
python3 tests/test_inject_tx_status.py
python3 tests/test_inject_recovery.py
python3 tests/test_monitor_channel.py
python3 tests/test_monitor_channel_alloc.py
python3 tests/test_monitor_channel_serialization.py
python3 tests/test_monitor_restore_result.py
python3 tests/test_mode_handoff.py
python3 tests/test_monitor_wext.py
python3 tests/test_monitor_host_queue.py
```

They cover parsing, helper TX parameters/flags, queue pressure, ordered peer
switches, early completion, synchronous failures/retries, timeout retention,
channel errors and serialization, recovery eligibility and exit handoff.
These host checks do not substitute for device firmware and RF validation.

## v6 device evidence (2026-09-16)

The user supplied `aireplay-ng --test wlan0` output from 10:58:24–10:58:32
(device clock; timezone unspecified). It reported `Injection is working!`,
found three APs on channel 1, and received directed Probe responses of 29/30
(96%), 25/30 (83%) and 11/30 (36%). This establishes a working Probe
request/response path on 2.4 GHz channel 1 in this run.

The report followed delivery of
`op13_nethunter_ksu-peach-native-global-v6-integrated.zip`, SHA-256
`0ce6a9200601feba5ae9e92006bf2235d264cabd97b361011c19cbbc8899308a`.
Its build source was `eab4d48d0034f88961de8f06e371d54985242588`; the packaged
qcacld Build ID is `cc13d725ff0b78cb272c54643bc9d88187862483`.
Loaded module identity, driver counters and an independent capture were not
included in this user report. No device operation was performed by the agent.

The differing response rates alone do not identify a driver fault. The report
does not establish authentication/deauthentication/disassociation behavior,
other channels or bands, repeated mode/channel transitions, long runs or SSR.
Keep this package as the baseline. Next collect before/after `inject_stats`
and `inject_tx_status` around short repeated Probe tests, then check complete
mode exit/re-entry and channel changes before broadening frame coverage.

## Later v6 device results and v7 packaging

The later authorized device run confirmed v6 module identities, 2.4/5 GHz
Probe replies (including channels 149/161), authentication replies, 40/80 MHz
Beacon RX and repeated mode transitions. The user separately confirmed
unicast/broadcast operation. That run exposed the WEXT and qdisc issues
addressed in v7. v7 itself has no device validation yet.

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

The v7 source includes follow-up fixes for two v6 device findings. The unified
build and targeted device regressions passed on 2026-09-16:

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
behavior. The separate v7 device evidence below covers the observed wide-to-20
MHz stale-packet regression and WEXT without `--ignore-negative-one`.

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
python3 tests/test_monitor_ssr_rebuild.py
python3 tests/test_monitor_ssr_stop.py
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

## v7 build and device evidence (2026-09-16)

Source commit `c79b6f6541583b148354b731691dc92caeac6adb` preserves all 11
changed source/test/documentation files from the v7 build snapshot. It was
committed after the build; the build itself used `cd811a61` plus those working
changes. This later documentation update does not change runtime code.

The single unified `sun perf` build ran 14:47:27-14:59:02 UTC and passed.
Eleven production-code ASan/UBSan host checks passed. The stripped three-module
KSU ZIP is `op13_nethunter_ksu-peach-native-global-v7-integrated.zip`, SHA-256
`3a32b8975076861d43285b0bab25c7a8f92e79cefe6da7e614eab851e12401f2`.
Its qcacld Build ID is `6f765b5dc0aeaafd1b5c71d23b95ca612ca153dd`.

After the user installed and hot-switched v7, device checks ran from 15:47:59
to 15:57:49 UTC. Installed file hashes and loaded Build ID notes matched v7
before/after testing. Results:

- WEXT reported the confirmed frequency/channel. Same-mode/channel
  confirmation succeeded; actual WEXT retuning returned EOPNOTSUPP as
  intended. Directed aireplay tests without `--ignore-negative-one` scored
  30/30 on all three rounds: initial, down/up and full mode exit/re-entry.
- nl80211 tuning succeeded on channels 1/6/11/36/149/161. Probe responses
  were observed on 1/6/11/149. Channel 36 had no RF reception evidence, and
  channel 161 had Beacons but no Probe responses in this run.
- 40/80 MHz RX captures contained 224/63 Beacons. Sending 17 host frames at
  either RX-only width left every qdisc empty. Returning to 20 MHz without
  a new send did not advance accepted/submitted/completed. Sending one new
  valid frame then advanced all three counters by exactly one.
- A 128-frame short burst was fully submitted/completed, reached peak 62
  slots, and drained with no timeout or retained buffer. It does not prove
  sustained-load behavior or the NETDEV_TX_BUSY branch.
- Repeated start, down/up, full exit/re-entry and normal Wi-Fi connection,
  IPv4 assignment and scanning succeeded. The final state restored mode 0
  and Wi-Fi off, with v7 modules left loaded.

Final accepted/submitted/completed were 343; firmware OK=253, NO_ACK=90,
DISCARD=0. Queued/inflight/used/retained and timeout counters were zero;
DMA pools allocated/freed=2/2. Completion is not an ACK or independent RF
confirmation. Separate auth/deauth/disassoc validation was not repeated.
SSR, long-running stress/hopping and 160 MHz reception remain unvalidated.

The first direct Kali chroot lacked sys/proc/dev mounts and aireplay traffic
was rejected as malformed Radiotap. Preparing those mounts in an isolated
mount namespace made the same test pass 30/30. Use a prepared chroot when
repeating these tests; do not classify this first environment failure as a
driver regression. Full evidence is in `/root/pt/op13-v7-runtime-20260916/`
and the workspace report `oplus/说明/op13_v7_runtime_20260916.md`.

## v7 extended testing and SSR follow-up (built as v8)

Further device testing on 2026-09-16 completed 601.3 seconds of mixed-width
hopping: 517 phases, 6864 submitted/completed Probe frames, 1768 RX-only host
send attempts without qdisc backlog or replay on a later channel. TX was
drained before each retune; concurrent retuning and NETDEV_TX_BUSY remain
unvalidated. 160 MHz configuration/readback succeeded on primaries 36/40/44/48
with center 5250, but no frames were captured: RF reception remains unverified.

One idle firmware SSR failed to restore monitor mode. Firmware became ready,
but monitor restart returned -22 and TX remained stopped. Manual retuning
restored TX completions without RX; full mode exit/re-entry restored Beacons
and Probe responses. The phone did not reboot. Normal Wi-Fi recovered, and
testing ended in mode 0/Wi-Fi off. No inflight SSR was attempted after this
failure. See `oplus/说明/op13_v7_extended_20260916.md` in the workspace.

The follow-up source fixes the monitor rebuild before sam's TX restore hook:

- Store the saved monitor context outside `session`'s STA/AP union. Monitor
  vdev creation calls STA initialization; its roam profile previously aliased
  the monitor PHY/center fields. v7 DWARF places both center_freq1 and the STA
  SSIDList pointer at offset 16. Moving the context preserves all link channel
  fields without a temporary restore over live STA bookkeeping.
- Recreate the global monitor vdev, disable idle PS/PS/WoW, register RX,
  enable DP monitor, restore the validated channel and reapply monitor bus
  policy. Report the failing stage. Only successful RX/channel reconstruction
  marks this SSR eligible for subsequent TX-helper restoration, which still
  runs after recovery state is cleared inside the existing psoc transaction.
- Preserve monitor WEXT handlers during shared STA initialization. Do not
  rerun Ethernet setup on a registered, possibly administratively down netdev.
- Require the confirmed primary/width/full center to match. Wide channels
  resume the rejecting host TX path without creating a helper; paused netdevs
  stay paused. WMA's existing mode-stop latch and DMA ownership rules remain.
- When firmware is down, skip monitor UP/STOP response waits while retaining
  SME session cleanup, object references and normal vdev destruction. Failed
  STOP enqueue does not wait for an impossible response either. This is not
  a DMA fence and does not free injection memory on a timer.

Thirteen host ASan/UBSan checks pass. The new rebuild test runs production
STA initialization and the new monitor restart function with an extracted
production context layout; a negative control using the old union fails the
saved-channel assertion. It covers both links, 20/40/80/160 fields, no saved
channel, each restart failure, WEXT and the non-global fallback. The teardown
test covers live/dead firmware, failed enqueue, wait failure and missing vdev.
The TX restore test covers the new readiness gate, full centers, RX-only
queues and paused interfaces. Firmware/DP calls are modeled, not device proof.

The follow-up was built and packaged as v8 from commit
`30426bf8a3e1b57596ee741086e2c491617c58d1`. The older v7 ZIP still contains
the demonstrated SSR failure. The following results are later evidence;
this documentation update does not change the v8 runtime code.

## v8 build and SSR device evidence (2026-09-17)

The single unified `sun perf` build ran on 2026-09-16 from 18:10:43 to
18:22:15 UTC. The three-module package was stripped with `--strip-debug`;
no CNSS modules were added. ZIP SHA-256 is
`ec6361da53d4a14c89c98492b5f3bbe84796d7b6abed57f39b625276cd2dff3a`,
and qcacld Build ID is `ff0f34e4ea4eba64f788c495b3a9eabb401d3157`.

After the user installed and hot-switched v8, all three installed module
hashes and loaded Build ID notes matched the package. Four firmware SSR
scenarios passed targeted checks, with the same boot ID after every SSR:

- Idle channel 1/20 MHz: helper ready was first observed after 2.506 seconds;
  the saved channel and WEXT were restored. Six new Probe requests completed,
  with 166 Beacons and 16 addressed Probe responses captured.
- During traffic: 640 host send calls overlapped the fault, with 32 inflight
  and 30 queued frames observed. The queued frames were dropped and the
  inflight frames were host-drained, not counted as firmware completions.
  The uncertain DMA pool was retained, then reclaimed after fresh firmware
  boot (`reset_reclaims=1`). Helper readiness returned after 2.115 seconds;
  six new Probes completed, with 211 Beacons and 11 Probe responses captured.
  Host send calls do not imply that all 640 frames reached the firmware.
- Channel 1/40 MHz RX-only: recovery preserved primary 2412/center 2422 and
  did not create a TX helper. The capture contained 207 Beacons. Six host
  send attempts left TX counters unchanged and all qdiscs empty; retuning
  to 20 MHz caused no old-frame transmission, while one new Probe completed.
- Administratively down: IFF_UP stayed clear across SSR. An explicit up
  restored the visible 2412/20 MHz channel. This checked the paused state;
  it did not attempt sending while the interface was down.

Normal Wi-Fi subsequently connected, obtained IPv4 and VALIDATED status,
and scanned successfully. Full monitor exit/re-entry passed, with WEXT
working and directed aireplay Probe responses of 20/30 without the negative
channel override. The saved idle/traffic SSR logs show both monitor RX and
TX restoration and no new checked kernel BUG/WARNING/Call trace/KASAN during
the captured interval; complete logs for the later stages were not collected.

The user unplugged USB before the final agent down/up command could run.
The user then performed the requested phone-side follow-up and supplied
monitor channel 1/20 MHz, working WEXT, and Probe results of 23/30 for
`tdgcxh` at 01:12:59-01:13:03 (terminal timezone unspecified). This is a user
report: the pasted excerpt omits the down/up commands and module identity.
It is not an uninterrupted agent observation.

The user's final counters were accepted=207, submitted=177, completed=145,
dropped=30, drained=32, failed=60 and reset_reclaims=1. Queued/inflight/used/
retained/timeouts/stale/retries/backpressure were zero. The two TX-count
differences match the observed SSR queue drop and host drain. One DMA pool
remained active (allocs=6, frees=5) with monitor still running. The earlier
failed=30 matched NO_ACK; the later increase lacks a TX status breakdown
and must not be classified as SSR failures. No final monstop or loaded
identity recheck was performed after the user's follow-up.

The user reports no known 160 MHz signal source in the current environment;
160 MHz RX testing is deferred, not classified as a driver failure. Wider
80/160 MHz SSR, concurrent retuning/exit, NETDEV_TX_BUSY and long-duration
or screen-off/resume behavior remain outside this validation. This update
does not start another build or device test. Full records are in the workspace
`oplus/说明/op13_v8_runtime_20260917.md` and `op13-v8-runtime-20260917/`.

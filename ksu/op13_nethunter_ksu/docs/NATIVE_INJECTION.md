# peach_v2 global monitor RX with internal STA TX (experimental)

The public interface remains native `wlan0` in `con_mode=4`. The monitor vdev
owns RX, host references and native management descriptors. TX uses a separate
firmware-only STA helper on the confirmed monitor channel, following sam's
`0001-wlan-native-monitor-injection.patch`. No extra netdev is created.

This replaces v5's direct monitor-vdev WMI TX, which returned DISCARD for the
reported probe/auth frames. Global mode does not require TX on the monitor
vdev. The old oplus patches are supporting references, not the port baseline.
The helper port has not yet been verified on peach_v2 firmware or over the air.

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
```

They cover parsing, helper TX parameters/flags, queue pressure, ordered peer
switches, early completion, synchronous failures/retries, timeout retention,
channel errors and serialization, recovery eligibility and exit handoff.
Firmware confirmations and RF behavior still require later device validation.

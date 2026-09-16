# peach_v2 native global monitor TX (experimental)

Only `con_mode=4` on `wlan0` is supported. No helper STA is created.
TX uses the existing monitor vdev and WMI management-TX command.
Deauthentication/disassociation retain MGMT_TX_USE_INCORRECT_KEY. Other
management frames use ordinary flags by default; the root-only boolean
`mon_tx_wrong_key` sysfs parameter forces that flag on them for A/B diagnosis.
Sam's helper-vdev results do not establish peach_v2 native monitor TX support.

Input is Radiotap followed by a management frame (24–2048 bytes excluding FCS).
Raw callers must prepend an empty 8-byte Radiotap header. FLAGS.FCS removes
four trailing bytes from the submitted view; DATAPAD is rejected. Other
Radiotap hints are parsed but do not configure firmware rate, power, sequence
or retry behavior. Control and data frames are rejected by this management API.
Use a fixed channel during injection; concurrent retuning is not validated.

TX has 64 slots, searches all free slots, stops netdev queues when full and
wakes them on completion. Netdev/module references protect outstanding frames.
WMI may complete before send returns: reclamation waits for both events.
Generation bits distinguish a reused slot's current descriptor from stale IDs;
the 16-bit descriptor namespace is finite, not an unlimited generation number.
A failed WMI send rolls back its own DMA mapping before host buffer release.
TX admission is covered by an HDD vdev operation to join driver teardown.

Missing completion is not a DMA fence. On WMA close, incomplete buffers and
module references are quarantined and TX remains disabled across WMA reopen.
This bounds retention to 64 buffers but requires reboot for recovery; module
hot-unload can be refused while references remain. Automatic recovery after a
confirmed CNSS firmware boot is outstanding work. No timeout reclaims memory.

`[submit]` proves WMI submission only. `[completion] status=0` is a firmware
report. NO_ACK and DISCARD must be distinguished, and independent reception is
needed to claim RF transmission. Counters are cumulative over module lifetime.

Host checks (run from the qcacld directory):

```
python3 tests/test_monitor_radiotap.py
python3 tests/test_native_injection.py
```

The first uses this kernel's real Radiotap iterator with ASan/UBSan. The second
runs the production TX/complete/close code against a WMI stub with injected
allocation/send failures, early/duplicate completions and missing completions.
They validate host ownership and input handling, not RF or firmware behavior.

Device investigation (2026-09-16): the installed v4 payload initially differed
from the loaded qcacld Build ID. After explicit reload the v4 Build ID matched.
The Kali chroot had no /sys mount: aircrack-ng 1.7 therefore missed the phy80211
sysfs check and sent raw frames, which this Radiotap interface rejects. With
/sys visible, broadcast probes reached WMI and the logged completions were
DISCARD, not successful RF injection. The 5 GHz directed test also returned
zero replies. Local outgoing tcpdump capture is not an independent RF capture.

Monitor get_channel now reports the active vdev's channel, and repeating an
identical tuning avoids the no-op restart that previously waited for an UP
notification and timed out. The callback publishes its state before waking
waiters. Run tests/test_monitor_channel.py for the channel reporting checks.

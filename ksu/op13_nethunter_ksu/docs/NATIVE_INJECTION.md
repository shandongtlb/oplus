# peach_v2 native global monitor TX (experimental)

Only `con_mode=4` on `wlan0` is supported. No helper STA is created.
TX uses the existing monitor vdev and WMI management-TX command. The PMF test
flag copied from sam remains an experiment: sam's helper-vdev results do not
establish firmware acceptance on peach_v2's native monitor vdev.

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

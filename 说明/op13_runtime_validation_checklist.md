# OP13 WiFi Injection Runtime Validation Checklist

This checklist is for validating the patched OP13 kernel on a real device.

## 1. Confirm the New WLAN Module Is Installed

Check:
- the deployed WLAN module is the new `qca_cld3_kiwi_v2.ko`
- the module timestamp/version matches the newly built output
- boot logs show the expected WLAN driver loading path

Suggested checks:
```sh
uname -a
lsmod | grep -i qca
dmesg | grep -i -E 'qca|qcacld|wlan|cnss'
modinfo /vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko 2>/dev/null
strings /vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko 2>/dev/null | grep -i 'legacy injection'
```

Expected:
- the module is present
- the module loads normally
- no immediate load crash or unresolved symbol errors

## 2. Confirm Monitor Mode Can Be Enabled

Suggested checks:
```sh
iw dev
iw dev wlan0 set type monitor
ip link set wlan0 up
iw dev
iw dev wlan0 info
```

Expected:
- the interface can switch to `monitor`
- `ip link set ... up` does not immediately fail
- the interface does not get forced back to station mode right away

Watch for:
- `ENETDOWN`
- framework forcing interface type changes
- monitor mode dropping immediately after `up`

## 3. Confirm Channel Setting Works

Suggested checks:
```sh
iw dev wlan0 set channel 6
iw dev wlan0 info
iwconfig wlan0
iw dev wlan0 set channel 36
iw dev wlan0 info
iwconfig wlan0
```

Expected:
- channel changes succeed
- `iw dev ... info` reports the selected channel
- `iwconfig` does not show `channel -1`

This validates:
- cfg80211 monitor channel handling
- monitor `get_channel`
- wext `SIOCGIWFREQ`

## 4. Confirm Passive Monitor Capture Works

Suggested checks:
```sh
tcpdump -I -i wlan0 -y IEEE802_11_RADIO
```

Or:
```sh
airodump-ng wlan0
```

Expected:
- radiotap frames are visible
- 802.11 traffic is captured normally
- changing channel changes what is captured

## 5. Run Minimal Injection Tests

Start with management-frame injection only.

Suggested checks:
```sh
aireplay-ng --test wlan0
```

If you have a controlled target:
- test probe request injection
- test deauth injection

Expected:
- management-frame injection reports success
- no immediate driver crash or firmware assert

Important:
- this port should be treated as management-frame injection first
- do not assume arbitrary data-frame injection is working until separately proven

## 6. Capture Logs During Injection

Suggested checks:
```sh
dmesg | grep -i -E 'wlan|qcacld|wma|inject|monitor|cfg80211|mac80211'
```

Useful live logging:
```sh
dmesg -w
```

Look for:
- monitor mode enable/disable errors
- helper vdev creation errors
- mgmt tx completion errors
- queue overflow or dropped frame logs
- firmware or descriptor id errors

## 7. How To Interpret Results

Basic success:
- monitor mode stays up
- channel can be set and read back
- passive capture works
- `aireplay-ng --test` or basic mgmt-frame injection works

Likely WMA/firmware issue:
- monitor mode works
- passive capture works
- channel reporting works
- but injection fails

Likely HDD/cfg80211/wext issue:
- monitor mode is unstable
- channel cannot be read back
- `iwconfig` shows `channel -1`
- interface gets forced down or reset

## 8. Recommended Test Order

Run in this order:
1. Verify module and boot logs
2. Enable monitor mode
3. Set channel and read it back
4. Confirm passive capture
5. Run `aireplay-ng --test`
6. Try controlled mgmt-frame injection
7. Collect logs if anything fails

## 9. Validation Notes

What this checklist proves:
- the runtime path for monitor mode is stable
- the monitor channel path is correct
- the injection path is at least alive

What this checklist does not automatically prove:
- arbitrary data-frame injection
- every tool's radiotap parser behaving correctly
- long-term stability under heavy injection load

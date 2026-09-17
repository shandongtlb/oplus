#!/usr/bin/env python3
"""Regress stale enabled markers and core unload failure without device writes."""
from pathlib import Path
import subprocess,tempfile
r=Path(__file__).resolve().parents[1]/'ksu/op13_nethunter_ksu'
def run(s):
 return subprocess.check_output(['sh','-eu','-c',s],text=True).strip()
def func(s,n):
 a=s.index(n+'() {');return s[a:s.index('\n}',a)+2]+'\n'
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp);(p/'module_build_ids').mkdir();sys=p/'sys';sys.mkdir()
 helper=(r/'module_identity.sh').read_text().replace('/sys/module/',str(sys)+'/')
 prefix='MODDIR='+str(p)+'\n'+helper
 assert run(prefix+'\npayload_stack_mode')=='inactive'
 (p/'.nethunter_enabled').touch() # Marker alone never proves loaded provenance.
 assert run(prefix+'\npayload_stack_mode')=='inactive'
 for n in ('cfg80211','mac80211','qca_cld3_peach_v2'):
  (p/'module_build_ids'/f'{n}.note').write_bytes(b'expected\0id')
  d=sys/n/'notes';d.mkdir(parents=True);(d/'.note.gnu.build-id').write_bytes(b'other\0id')
 assert run(prefix+'\npayload_stack_mode')=='unverified'
 for n in ('cfg80211','mac80211','qca_cld3_peach_v2'):
  (sys/n/'notes/.note.gnu.build-id').write_bytes(b'expected\0id')
  assert run(prefix+'\npayload_stack_mode')==('nethunter' if n=='qca_cld3_peach_v2' else 'mixed')
 (sys/'cfg80211/notes/.note.gnu.build-id').unlink()
 assert run(prefix+'\npayload_stack_mode')=='mixed'
s=(r/'wlan_stack_control.sh').read_text()
# Loaded module of the wrong build must not be accepted as an insmod success.
mock='''
is_loaded() { return 0; }
module_identity() { echo other; }
log_i() { :; }
log_e() { :; }
'''
assert run(mock+func(s,'load_module_strict')+'if load_module_strict qca_cld3_peach_v2 any; then exit 1; fi; echo passed')=='passed'
# Stopped userspace can quiesce while qcacld is still loaded, before rmmod.
mock='process_running() { return 1; }; is_loaded() { return 0; }; sleep() { exit 99; };\n'
assert run(mock+func(s,'wait_for_wifi_to_quiesce')+'wait_for_wifi_to_quiesce; echo passed')=='passed'
# Stop the core unload sequence as soon as qcacld refuses unload.
mock='''
log_i() { :; }; log_e() { :; }; wifi_is_enabled() { return 1; }
wifi_scan_always_available() { return 1; }; set_wifi_disabled() { :; }
stop_wifi_userspace() { :; }; wait_for_wifi_to_quiesce() { return 0; }
sleep() { :; }; unload_extra_modules_from_rel() { :; }
unload_module() { echo "$1"; [ "$1" != qca_cld3_peach_v2 ]; }
'''
out=run(mock+func(s,'prepare_switch')+'if prepare_switch; then exit 1; fi')
assert out.splitlines()[-1]=='qca_cld3_peach_v2' and 'cfg80211' not in out
print('Loaded Build ID, stale marker, userspace quiescence and core unload failure checks passed')
# Runtime status takes priority over stale ColorOS wifi_on and scan prose.
mock='''
settings() { echo 1; }
cmd() { printf 'Wifi is disabled\\nWifi scanning is only available when wifi is enabled\\n'; }
dumpsys() { echo 'Wi-Fi is enabled'; }
'''
assert run(mock+func(s,'wifi_is_enabled')+'if wifi_is_enabled; then exit 1; fi; echo passed')=='passed'
mock='''
settings() { echo 0; }
cmd() { echo 'Wifi is enabled'; }
dumpsys() { echo 'Wi-Fi is disabled'; }
'''
assert run(mock+func(s,'wifi_is_enabled')+'wifi_is_enabled; echo passed')=='passed'
print('Current Wi-Fi state overrides stale settings and scan-only prose: passed')

# Vendor recovery must be able to read/load the replacement. A failed label
# update must not remove an existing bind or begin unloading the WLAN stack.
bind=(r/'bind_mount_control.sh').read_text()
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp);src=p/'payload.ko';target=p/'vendor.ko'
 src.touch();target.touch()
 mock=f'''
resolve_moddir_file() {{ echo '{src}'; }}
log_i() {{ :; }}; log_e() {{ :; }}
is_target_bound() {{ return 0; }}
chcon() {{ [ "$1" = u:object_r:vendor_file:s0 ] && [ "$2" = '{src}' ] || exit 90; echo label; return "$LABEL_RC"; }}
umount() {{ echo unmount; }}
mount() {{ echo mount; }}
'''
 command=func(bind,'apply_one')+f'apply_one payload "{target}"'
 assert run(mock+'LABEL_RC=0\n'+command).splitlines()==['label','unmount','mount']
 out=run(mock+'LABEL_RC=1\n'+func(bind,'apply_one')+f'if apply_one payload "{target}"; then exit 91; fi')
 assert out=='label',out
 controller=p/'bind_mount_control.sh';controller.write_text('#!/bin/sh\nexit 1\n');controller.chmod(0o755)
 flag=p/'state';flag.touch()
 mock=f'''
MODDIR='{p}'
STATE_FLAG='{flag}'
log_i() {{ :; }}; log_e() {{ :; }}
stage_usb_firmware() {{ return 0; }}
prepare_switch() {{ echo unexpected-unload; exit 92; }}
'''
 out=run(mock+func(s,'switch_to_nethunter')+'if switch_to_nethunter; then exit 93; fi')
 assert out=='' and flag.exists()
print('Vendor module label, bind failure and reload boundary checks passed')

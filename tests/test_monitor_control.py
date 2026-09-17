#!/usr/bin/env python3
"""Execute copied production scripts with fake Android IO; no phone operations."""
import fcntl
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1] / 'ksu/op13_nethunter_ksu'

MOCK = r'''#!/usr/bin/env python3
import os, sys
from pathlib import Path
p = Path(os.environ['FIXTURE'])
name = Path(sys.argv[0]).name
args = sys.argv[1:]
def get(key, default=''):
    f = p / key
    return f.read_text().strip() if f.exists() else default
def end(code=0):
    sys.exit(code)
if name == 'log' or name == 'sleep': end()
if name == 'id': print('0'); end()
if name in ('cmd', 'svc', 'settings'):
    if name == 'cmd' and args == ['wifi', 'status']:
        print('Wifi is ' + ('enabled' if get('wifi', '0') == '1' else 'disabled')); end()
    if name == 'settings' and args[:3] == ['get', 'global', 'wifi_scan_always_enabled']:
        print(get('scan', '1')); end()
    if name == 'settings' and args[:3] == ['put', 'global', 'wifi_scan_always_enabled']:
        (p / 'scan').write_text(args[3]); end()
    if name == 'cmd' and args[:2] == ['wifi', 'set-scan-always-available']:
        end(int(get('scan_set_fail', '0')))
    if (name == 'svc' and args[:1] == ['wifi']) or (name == 'cmd' and args[:2] == ['wifi', 'set-wifi-enabled']):
        enable = args[-1] in ('enable', 'enabled')
        if enable and get('wifi_enable_fail') == '1': end(1)
        (p / 'wifi').write_text('1' if enable else '0'); end()
    end(96)
if name == 'dumpsys':
    if args[-1:] == ['wifi']:
        active = get('active_override', str(int(get('wifi', '0') == '1' or get('scan', '1') == '1')))
        print('NumActiveModeManagers: ' + active)
        # This unrelated scanner state must not be treated as a live STA.
        print('curState=ScanOnlyModeState')
        end()
    print(get('p2p', 'curState=InactiveState'))
    end(int(get('p2p_rc', '0')))
if name == 'iw':
    if args == ['dev']:
        print(get('interfaces', 'phy#0\n\tInterface wlan0\n\t\ttype managed'))
        end(int(get('iw_dev_rc', '0')))
    if args[:1] == ['phy']:
        print(get('channels', '* 2412 MHz [1] (20.0 dBm)\n* 5745 MHz [149] (20.0 dBm)\n* 5180 MHz [36] (disabled)'))
        end()
    if args == ['dev', 'wlan0', 'info']:
        if get('info_fail') == '1': end(1)
        mode = get('mode', '0')
        iface_type = 'monitor' if mode == '4' else 'managed'
        if get('managed_missing') == '1' and mode == '0': end(1)
        print(f'Interface wlan0\n\twiphy 0\n\ttype {iface_type}')
        freq = get('freq')
        if freq and mode == '4':
            print(f'\tchannel 1 ({freq} MHz), width: {get("width", "20")} MHz, center1: {freq} MHz')
        end()
    if args[:4] == ['dev', 'wlan0', 'set', 'freq']:
        with (p / 'calls').open('a') as f: f.write('setfreq\n')
        rc = int(get('freq_fail', '0'))
        if not rc and get('wrong_readback') != '1':
            (p / 'freq').write_text(args[4]); (p / 'width').write_text('20')
        end(rc)
    end(93)
if name == 'ip':
    if args == ['link', 'set', 'wlan0', 'up']:
        with (p / 'calls').open('a') as f: f.write('up\n')
        rc = int(get('up_fail', '0'))
        if not rc: (p / 'up').write_text('1')
        end(rc)
    if args == ['-o', 'link', 'show', 'dev', 'wlan0']:
        print('1: wlan0: <BROADCAST,' + ('UP,' if get('up') == '1' else '') + 'LOWER_UP> state UNKNOWN')
        end()
    end(94)
end(95)
'''


class MonitorControl(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='monitor-control-')
        self.addCleanup(self.tmp.cleanup)
        self.p = Path(self.tmp.name)
        self.mod = self.p / 'module'
        self.mod.mkdir()
        for name in ('monitor_control.sh', 'wlan_control_common.sh', 'wlan_stack_control.sh',
                     'action.sh', 'bind_mount_control.sh'):
            source = (ROOT / name).read_text()
            source = source.replace('/sys/module/qca_cld3_peach_v2/parameters/con_mode', str(self.p / 'mode'))
            source = source.replace('/sys/module/qca_cld3_peach_v2/parameters/inject_stats', str(self.p / 'stats'))
            dest = self.mod / name
            dest.write_text(source)
            dest.chmod(0o755)
        (self.mod / 'module_identity.sh').write_text('verify_payload_stack() { return 0; }\npayload_stack_mode() { echo nethunter; }\n')
        self.bin = self.p / 'bin'
        self.bin.mkdir()
        (self.bin / 'mock').write_text(MOCK)
        (self.bin / 'mock').chmod(0o755)
        for name in ('iw', 'ip', 'dumpsys', 'sleep', 'log', 'id', 'cmd', 'svc', 'settings'):
            (self.bin / name).symlink_to('mock')
        self.env = dict(os.environ, FIXTURE=str(self.p), PATH=str(self.bin) + ':' + os.environ['PATH'])
        self.env.pop('OP13_WLAN_LOCK', None)
        self.set(mode='0', stats='state=2 stopping=0')

    def set(self, **values):
        for key, value in values.items():
            (self.p / key).write_text(str(value))

    def run_script(self, name='monitor_control.sh', *args, **kwargs):
        return subprocess.run(['sh', str(self.mod / name), *args], env=self.env,
                              text=True, capture_output=True, timeout=15, **kwargs)

    def assert_mode(self, value):
        self.assertEqual((self.p / 'mode').read_text().strip(), value)

    def assert_untouched(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_mode('0')
        self.assertFalse((self.p / 'calls').exists())
        self.assertFalse((self.mod / '.global_monitor_enabled').exists())

    def test_invalid_arguments_before_mode_change(self):
        for args in (('on', '2412oops'), ('on', '99999'), ('on', '6', 'extra'),
                     ('on', ''), ('on', '-1'), ('reset', 'extra')):
            with self.subTest(args=args):
                self.assert_untouched(self.run_script('monitor_control.sh', *args))

    def test_unavailable_or_disabled_channel_before_mode_change(self):
        for channel in ('36', '5500', '2450'):
            with self.subTest(channel=channel):
                self.assert_untouched(self.run_script('monitor_control.sh', 'on', channel))

    def test_success_and_repeat_start(self):
        for _ in range(2):
            result = self.run_script('monitor_control.sh', 'on', '149')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('TX READY', result.stdout)
            self.assert_mode('4')
        self.assertEqual((self.p / 'freq').read_text(), '5745')

    def test_start_failure_rolls_back_new_session(self):
        for failure in ('up_fail', 'freq_fail', 'wrong_readback'):
            with self.subTest(failure=failure):
                self.set(mode='0', **{failure: '1'})
                result = self.run_script('monitor_control.sh', 'on', '1')
                self.assertNotEqual(result.returncode, 0)
                self.assert_mode('0')
                self.assertFalse((self.mod / '.global_monitor_enabled').exists())
                self.assertFalse((self.mod / '.global_monitor_framework_state').exists())
                self.assertEqual((self.p / 'scan').read_text(), '1')
                (self.p / failure).unlink()

    def test_framework_settings_restored_and_repeat_start_preserves_snapshot(self):
        for wifi, scan in (('0', '1'), ('1', '0'), ('1', '1'), ('0', '0')):
            with self.subTest(wifi=wifi, scan=scan):
                self.set(mode='0', wifi=wifi, scan=scan)
                started = self.run_script('monitor_control.sh', 'on', '1')
                self.assertEqual(started.returncode, 0, started.stderr)
                state = self.mod / '.global_monitor_framework_state'
                original = state.read_bytes()
                self.assertEqual((self.p / 'wifi').read_text(), '0')
                self.assertEqual((self.p / 'scan').read_text(), '0')
                again = self.run_script('monitor_control.sh', 'on', '149')
                self.assertEqual(again.returncode, 0, again.stderr)
                self.assertEqual(state.read_bytes(), original)
                stopped = self.run_script('monitor_control.sh', 'off')
                self.assertEqual(stopped.returncode, 0, stopped.stderr)
                self.assertEqual((self.p / 'wifi').read_text(), wifi)
                self.assertEqual((self.p / 'scan').read_text(), scan)
                self.assertFalse(state.exists())

    def test_restore_failure_retains_snapshot_and_stop_can_retry(self):
        self.set(wifi='1', scan='1')
        self.assertEqual(self.run_script('monitor_control.sh', 'on', '1').returncode, 0)
        self.set(wifi_enable_fail='1')
        failed = self.run_script('monitor_control.sh', 'off')
        self.assertNotEqual(failed.returncode, 0)
        self.assert_mode('0')
        self.assertTrue((self.mod / '.global_monitor_framework_state').exists())
        self.assertIn('RESTORE PENDING', self.run_script('monitor_control.sh', 'status').stdout)
        self.assertNotEqual(self.run_script('monitor_control.sh', 'on', '1').returncode, 0)
        self.set(wifi_enable_fail='0')
        self.assertEqual(self.run_script('monitor_control.sh', 'off').returncode, 0)
        self.assertEqual((self.p / 'wifi').read_text(), '1')
        self.assertFalse((self.mod / '.global_monitor_framework_state').exists())

    def test_active_framework_owner_blocks_mode_change(self):
        self.set(active_override='1')
        result = self.run_script('monitor_control.sh', 'on', '1')
        self.assertNotEqual(result.returncode, 0)
        self.assert_mode('0')
        self.assertFalse((self.p / 'calls').exists())
        self.assertTrue((self.mod / '.global_monitor_framework_state').exists())

    def test_existing_session_not_turned_off_on_retune_failure(self):
        self.set(mode='4', freq_fail='1', freq='5745')
        (self.mod / '.global_monitor_enabled').touch()
        result = self.run_script('monitor_control.sh', 'on', '1')
        self.assertNotEqual(result.returncode, 0)
        self.assert_mode('4')
        self.assertTrue((self.mod / '.global_monitor_enabled').exists())

    def test_status_distinguishes_states(self):
        self.set(mode='4', up='1')
        cases = [('', '20', '2', '0', '频道未确认'),
                 ('2412', '20', '2', '0', 'TX READY'),
                 ('2412', '20', '0', '0', 'TX UNAVAILABLE'),
                 ('2412', '20', '2', '1', 'TX UNAVAILABLE'),
                 ('2412', '80', '0', '0', 'RX ONLY'),
                 ('2412', '80', '4', '0', 'RECOVERY REQUIRED')]
        for freq, width, state, stopping, expected in cases:
            with self.subTest(expected=expected):
                self.set(freq=freq, width=width, stats=f'state={state} stopping={stopping}')
                self.assertIn(expected, self.run_script('monitor_control.sh', 'status').stdout)
        self.set(up='0')
        self.assertIn('PAUSED', self.run_script('monitor_control.sh', 'status').stdout)
        self.set(info_fail='1')
        self.assertIn('STARTING/UNAVAILABLE', self.run_script('monitor_control.sh', 'status').stdout)

    def test_stop_failure_not_reported_success(self):
        self.set(mode='4', managed_missing='1')
        result = self.run_script('monitor_control.sh', 'off')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('OFF：', result.stdout)
        self.assert_mode('0')

    def test_stop_does_not_require_p2p_idle(self):
        self.set(mode='4', p2p='curState=GroupCreatedState')
        result = self.run_script('monitor_control.sh', 'off')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_mode('0')

    def test_reset_preserves_child_error_and_inherits_lock(self):
        # Keep real dispatch, lock and monitor exit; stub only the module IO.
        path = self.mod / 'wlan_stack_control.sh'
        source = path.read_text()
        start = source.rindex('case "$1" in')
        source = source[:start] + '''switch_to_nethunter() {
  [ "$(cat "$FIXTURE/mode")" = 0 ] || return 98
  echo child-entered
  return 37
}
''' + source[start:]
        path.write_text(source)
        self.set(mode='4', interfaces='phy#0\n Interface wlan0\n  type monitor',
                 p2p='curState=GroupCreatedState')
        result = self.run_script('monitor_control.sh', 'reset')
        self.assertEqual(result.returncode, 37, result.stderr)
        self.assertIn('child-entered', result.stdout)
        self.assertIn('重载失败', result.stderr)
        self.assert_mode('0')

    def test_global_mode_ignores_stale_framework_group_on_repeat_start(self):
        self.set(mode='4', interfaces='phy#0\n Interface wlan0\n  type monitor',
                 p2p='curState=GroupCreatedState')
        result = self.run_script('monitor_control.sh', 'on', '1')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_switch_stops_before_reload_if_monitor_exit_fails(self):
        self.set(mode='4')
        (self.mod / 'monitor_control.sh').write_text('echo stop-failed >&2\nexit 29\n')
        result = self.run_script('wlan_stack_control.sh', 'nethunter')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('stop-failed', result.stderr)
        self.assertNotIn('switching wlan stack', result.stdout)
        self.assert_mode('4')

    def test_active_ap_and_p2p_interfaces_block_before_mutation(self):
        for iface_type in ('AP', 'P2P-GO', 'P2P-client'):
            self.set(interfaces=f'phy#0\n Interface wlan0\n  type managed\n Interface p2p0\n  type {iface_type}')
            for script, args in (('monitor_control.sh', ('on', '1')),
                                 ('wlan_stack_control.sh', ('nethunter',)), ('action.sh', ())):
                with self.subTest(type=iface_type, script=script):
                    result = self.run_script(script, *args)
                    self.assert_untouched(result)
                    self.assertIn('与平板网络共享', result.stderr)

    def test_idle_p2p_device_and_other_radio_allowed(self):
        self.set(interfaces='phy#0\n Interface wlan0\n  type managed\n Interface p2p0\n  type P2P-device\nphy#1\n Interface wlan9\n  type AP')
        result = self.run_script('monitor_control.sh', 'on', '1')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_only_current_p2p_state_blocks(self):
        for state in ('GroupCreatedState', 'GroupNegotiationState', 'UserAuthorizingJoinState'):
            self.set(p2p=f'curState={state}')
            self.assert_untouched(self.run_script('monitor_control.sh', 'on', '1'))
        self.set(p2p='curState=InactiveState\nmNetworkInfo [type: WIFI_P2P[], state: CONNECTED/CONNECTED]')
        self.assert_untouched(self.run_script('monitor_control.sh', 'on', '1'))
        self.set(p2p='rec[0]: state=GroupCreatedState\ncurState=InactiveState\nmGroups:\nGroupCreatedState\nmNetworkInfo [state: DISCONNECTED/DISCONNECTED]')
        result = self.run_script('monitor_control.sh', 'on', '1')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_optional_p2p_service_absent_does_not_lock_out_global_monitor(self):
        self.set(p2p_rc='1')
        result = self.run_script('monitor_control.sh', 'on', '1')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_lock_contends_across_all_writers_and_ignores_forged_marker(self):
        path = self.mod / '.wlan_control.lock'
        with path.open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.env['OP13_WLAN_LOCK'] = str(path)
            for script, args in (('monitor_control.sh', ('on', '1')),
                                 ('monitor_control.sh', ('off',)),
                                 ('monitor_control.sh', ('reset',)),
                                 ('wlan_stack_control.sh', ('nethunter',)),
                                 ('action.sh', ()), ('bind_mount_control.sh', ('on',))):
                with self.subTest(script=script, args=args):
                    result = self.run_script(script, *args)
                    self.assert_untouched(result)
                    self.assertIn('已有 WLAN 操作', result.stderr)
            # Read-only status is available during a control operation.
            self.assertEqual(self.run_script('monitor_control.sh', 'status').returncode, 0)
        self.assertEqual(self.run_script('monitor_control.sh', 'on', '1').returncode, 0)

    def test_lock_released_on_killed_owner(self):
        script = f'MODDIR={shlex.quote(str(self.mod))}; . "$MODDIR/wlan_control_common.sh"; wlan_control_lock "$@" || exit 1; echo ready; read line'
        holder = self.mod / 'hold-lock.sh'
        holder.write_text(script)
        proc = subprocess.Popen(['sh', str(holder)], env=self.env, text=True,
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            self.assertEqual(proc.stdout.readline().strip(), 'ready')
            self.assertNotEqual(self.run_script('monitor_control.sh', 'on', '1').returncode, 0)
            proc.kill()
            proc.communicate(timeout=5)
            result = self.run_script('monitor_control.sh', 'on', '1')
            self.assertEqual(result.returncode, 0, result.stderr)
        finally:
            if proc.poll() is None: proc.kill()
            proc.communicate(timeout=5)


if __name__ == '__main__':
    unittest.main(verbosity=2)

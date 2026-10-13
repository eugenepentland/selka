#!/usr/bin/env python3
"""Exercise deadlines and chunk carry-over using disposable subprocess guests."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]


class DeadlineTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.guest = self.root / 'guest.py'
        self.guest.write_text('''import os, pathlib, subprocess, sys, time
delay, marker, mode = sys.argv[1:]
if marker != '-':
    with open(marker, 'a') as stream: stream.write('started\\n')
if mode == 'child':
    child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])
    pathlib.Path(marker + '.pid').write_text(str(child.pid))
if mode == 'fail': sys.exit(7)
time.sleep(float(delay))
print('same oracle')
''')

    def tearDown(self):
        self.temporary.cleanup()

    def run_case(self, label, delay='0.6', mode='plain', reference_mode='plain', prior=None, before=False,
                 spec_patch=None, guest_timeout='2'):
        marker = self.root / 'checked-starts'
        def command(seconds, marker='-', mode='plain'):
            return [sys.executable, str(self.guest), seconds, str(marker), mode]
        spec = {'cell': 'test/deadline', 'oracle': 'zig-safe', 'files': [str(self.guest)],
                'arms': {'zig-safe': command('0'), 'zig-fast': command('0.04', mode=reference_mode),
                         'mylang-zero-rc': command(delay, marker, mode)}}
        if before:
            spec['arms']['mylang-before'] = command('0.6', self.root / 'before-starts')
            spec['relative_timeout_arms'] = ['mylang-zero-rc', 'mylang-before']
        if prior:
            spec['prior_receipt'] = str(prior)
        spec.update(spec_patch or {})
        path = self.root / (label + '.spec.json')
        output = self.root / (label + '.json')
        path.write_text(json.dumps(spec))
        subprocess.run([sys.executable, '-B', str(HERE / 'measure_recovered.py'), str(path), str(output),
                        '--cpu', str(min(os.sched_getaffinity(0))), '--rounds', '1',
                        '--warmups', '0' if prior else '1', '--rss-rounds', '1',
                        '--calibration-warmups', '1', '--calibration-rounds', '3',
                        '--guest-timeout', guest_timeout], stdout=subprocess.DEVNULL, check=True)
        return json.loads(output.read_text()), output, marker

    def test_slow_guest_is_censored_once_and_not_retried_in_later_chunk(self):
        data, path, marker = self.run_case('first')
        policy = data['relative_timeout_policy']
        self.assertAlmostEqual(policy['budget_seconds'], 3 * policy['reference_median_seconds'])
        self.assertEqual(data['arm_status']['mylang-zero-rc']['status'], 'relative_timeout')
        self.assertEqual(marker.read_text(), 'started\n')
        self.assertFalse(any(s['arm'] == 'mylang-zero-rc' for s in data['wall_samples'] + data['rss_samples']))
        later, _, _ = self.run_case('next', prior=path)
        self.assertEqual(later['relative_timeout_policy'], policy)
        self.assertTrue(later['arm_status']['mylang-zero-rc']['inherited_from_prior_chunk'])
        self.assertEqual(marker.read_text(), 'started\n')

    def test_fast_guest_completes_with_wall_and_rss(self):
        data, _, marker = self.run_case('fast', delay='0.01')
        self.assertEqual(data['arm_status']['mylang-zero-rc']['status'], 'ok')
        self.assertEqual(marker.read_text().count('started'), 3)
        self.assertEqual(len([s for s in data['wall_samples'] if s['arm'] == 'mylang-zero-rc']), 1)
        self.assertEqual(len([s for s in data['rss_samples'] if s['arm'] == 'mylang-zero-rc']), 1)

    def test_failed_reference_does_not_launch_checked_guest(self):
        data, _, marker = self.run_case('reference-fails', reference_mode='fail')
        self.assertEqual(data['arm_status']['mylang-zero-rc']['status'], 'reference_unavailable')
        self.assertIsNone(data['relative_timeout_policy']['budget_seconds'])
        self.assertFalse(marker.exists())

    def test_timeout_kills_descendant_process(self):
        data, _, marker = self.run_case('descendant', mode='child')
        self.assertEqual(data['arm_status']['mylang-zero-rc']['status'], 'relative_timeout')
        pid = int(Path(str(marker) + '.pid').read_text())
        stat = Path('/proc') / str(pid) / 'stat'
        if stat.exists():
            self.assertEqual(stat.read_text().split()[2], 'Z', 'descendant is still running')

    def test_before_and_candidate_have_independent_deadline_statuses(self):
        data, path, _ = self.run_case('two-arms', delay='0.01', before=True)
        self.assertEqual(data['arm_status']['mylang-zero-rc']['status'], 'ok')
        self.assertEqual(data['arm_status']['mylang-before']['status'], 'relative_timeout')
        self.assertEqual((self.root / 'before-starts').read_text(), 'started\n')
        later, _, _ = self.run_case('two-arms-next', delay='0.01', before=True, prior=path)
        self.assertEqual(later['arm_status']['mylang-zero-rc']['status'], 'ok')
        self.assertTrue(later['arm_status']['mylang-before']['inherited_from_prior_chunk'])
        self.assertEqual((self.root / 'before-starts').read_text(), 'started\n')

    def test_failed_calibration_skips_both_checked_sources(self):
        data, _, marker = self.run_case('two-fail', reference_mode='fail', before=True)
        for arm in ('mylang-before', 'mylang-zero-rc'):
            self.assertEqual(data['arm_status'][arm]['status'], 'reference_unavailable')
        self.assertFalse(marker.exists())
        self.assertFalse((self.root / 'before-starts').exists())

    def test_changed_environment_cannot_inherit_calibration(self):
        _, path, marker = self.run_case('initial-environment')
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_case('changed-environment', prior=path,
                          spec_patch={'env_by_arm': {'mylang-zero-rc': {'DEADLINE_TEST_VALUE': 'changed'}}})
        self.assertEqual(marker.read_text(), 'started\n')

    def test_changed_absolute_ceiling_cannot_inherit_calibration(self):
        _, path, marker = self.run_case('initial-ceiling')
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_case('changed-ceiling', prior=path, guest_timeout='3')
        self.assertEqual(marker.read_text(), 'started\n')


if __name__ == '__main__':
    unittest.main(verbosity=2)

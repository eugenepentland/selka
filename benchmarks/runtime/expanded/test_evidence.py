import copy
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import run
import verify
from registry import HERE, GROUPS, EDGE_PROBES, inventory, plans_for, checksum


def fixture():
    cases = inventory()
    report = {'schema': run.SCHEMA, 'status': 'complete', 'profile': 'baseline',
              'inventory': cases, 'coverage': list(cases), 'rounds': 1, 'warmup_rounds': 1,
              'plans': [], 'qualification': [], 'pilots': [], 'samples': [], 'warmups': [], 'memory': []}
    def outcome(case, size, n, seed):
        return {'checksum': checksum(case, size, n, seed), 'kernel_ns': 100, 'process_wall_ns': 500, 'exit_status': 0}
    for p in plans_for(cases):
        p.update(iterations=1, expected=checksum(p['case'], p['size'], 1, 42),
                 calibration={'fastest_ns': 100, 'slowest_ns': 100, 'target_ns': 100,
                              'slowest_cap_ns': 1000, 'iteration_cap': 10, 'limited': False,
                              'target_reached': True, 'slowest_budget_exceeded': False})
        report['plans'].append(p)
        report['pilots'].append({**p, 'arms': {arm: outcome(p['case'], p['size'], 1, 42) for arm in run.ARMS}})
        for arm in run.ARMS:
            row = {**p, 'arm': arm, **outcome(p['case'], p['size'], 1, 42)}
            report['samples'].append({**row, 'round': 0})
            report['warmups'].append({**row, 'round': -1})
            report['memory'].append({**row, 'peak_rss_kib': 1000})
    for case in cases:
        for size, seed, count in EDGE_PROBES:
            for arm in run.ARMS:
                report['qualification'].append({'case': case, 'arm': arm, 'size': size, 'iterations': count,
                                                'seed': seed, **outcome(case, size, count, seed)})
    names = [group + '/' + arm for group in GROUPS for arm in run.ARMS]
    identity = {'pinned_revision': verify.REVISION, 'inventory': cases,
                'binary_paths': {name: '/fake/' + name for name in names},
                'commands': {name: ['compile', name] for name in names},
                'actual_build_commands': {name: ['slot', 'compile', name] for name in names},
                'actual_clock_build': ['slot', 'clock']}
    report.update(identity=identity, identity_after=copy.deepcopy(identity),
                  binary_hashes={name: 'a' * 64 for name in names + ['native_clock.o']},
                  build_logs=[{'name': name, 'command': identity['actual_build_commands'][name], 'exit_status': 0} for name in names]
                             + [{'name': 'clock', 'command': ['slot', 'clock'], 'exit_status': 0}])
    report['binary_hashes_after'] = report['binary_hashes'].copy()
    report['summary'] = run.common.summarize(report)
    return report


class EvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original = fixture()

    def setUp(self):
        self.report = copy.deepcopy(self.original)

    def test_complete_inventory_has_five_apps_and_every_proposed_area(self):
        cases = inventory()
        self.assertEqual({name for name, meta in cases.items() if meta['level'] == 'application'},
                         {'word_count', 'csv_aggregate', 'json_transform', 'packet_decode', 'lox_eval'})
        self.assertGreaterEqual(len(cases), 38)
        coverage = json.loads((HERE / 'coverage.json').read_text())
        named = [name for area in coverage['areas'].values() for name in area]
        self.assertEqual(len(named), len(set(named)))
        self.assertEqual(set(named), {name for name, meta in cases.items() if meta['level'] == 'micro'})
        self.assertEqual(set(coverage['applications']), {name for name, meta in cases.items() if meta['level'] == 'application'})
        self.assertEqual(verify.verify(self.report), len(cases) * 2 * 6)

    def test_missing_arm_duplicate_sample_and_missing_memory_are_rejected(self):
        for field in ('samples', 'warmups', 'memory', 'qualification', 'pilots', 'summary'):
            report = copy.deepcopy(self.original)
            report[field].pop()
            with self.subTest(field=field), self.assertRaises(ValueError):
                verify.verify(report)
        self.report['samples'][1] = self.report['samples'][0]
        with self.assertRaises(ValueError):
            verify.verify(self.report)

    def test_smoke_subset_bad_checksum_and_stale_identity_are_rejected(self):
        for status in ('smoke', 'subset', 'incomplete'):
            self.report['status'] = status
            with self.assertRaises(ValueError):
                verify.verify(self.report)
        self.report = copy.deepcopy(self.original)
        self.report['samples'][0]['checksum'] += 1
        with self.assertRaises(ValueError):
            verify.verify(self.report)
        self.report = copy.deepcopy(self.original)
        self.report['identity_after']['pinned_revision'] = 'stale'
        with self.assertRaises(ValueError):
            verify.verify(self.report)

    def test_summary_cannot_hide_failure_or_change_units(self):
        self.report['summary'][0]['median_ns_per_op'] *= 2
        with self.assertRaises(ValueError):
            verify.verify(self.report)
        self.report = copy.deepcopy(self.original)
        self.report['samples'][0]['unit'] = 'wrong work denominator'
        with self.assertRaises(ValueError):
            verify.verify(self.report)
        self.report = copy.deepcopy(self.original)
        self.report['build_logs'][0]['exit_status'] = 1
        with self.assertRaises(ValueError):
            verify.verify(self.report)

    def test_artifact_hash_detects_edit(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'port'
            path.write_text('before')
            digest = run.common.digest(path)
            verify.hash_matches(path, digest)
            path.write_text('after')
            with self.assertRaises(ValueError):
                verify.hash_matches(path, digest)

    def test_calibration_cannot_be_relabelled_after_sampling(self):
        self.report['plans'][0]['calibration']['fastest_ns'] += 1
        with self.assertRaises(ValueError):
            verify.verify(self.report)

    def test_slow_initial_pilot_is_downscaled_before_measurement(self):
        args = SimpleNamespace(cpu=2, quick=False, target_ms=50, max_sample_ms=1000, max_iterations=10000000)
        plan = plans_for(['record_reads'])[0]
        def fake_invoke(binaries, case, size, count, seed, cpu, arm):
            return {'kernel_ns': count * (100000000 if arm == 'my-qbe' else 1000000)}
        with patch('run.invoke', side_effect=fake_invoke):
            planned, pilots = run.calibrate(args, {}, plan)
        self.assertEqual(pilots[0]['iterations'], 31)
        self.assertLess(planned['iterations'], 31)
        self.assertLessEqual(planned['calibration']['slowest_ns'], 1000000000)
        self.assertTrue(planned['calibration']['limited'])

    def test_cargo_environment_has_no_inherited_release_overrides(self):
        with patch.dict(os.environ, {'CARGO_PROFILE_RELEASE_OPT_LEVEL': '0', 'CARGO_BUILD_TARGET': 'wrong',
                                     'CARGO_ENCODED_RUSTFLAGS': '-Ctarget-cpu=native', 'RUSTC_WRAPPER': '/wrapper'}):
            env = run.build_environment({'private_cache_environment': {'RUSTC': '/audited/rustc'}})
        self.assertEqual(env['RUSTC'], '/audited/rustc')
        for name in ('CARGO_PROFILE_RELEASE_OPT_LEVEL', 'CARGO_BUILD_TARGET', 'CARGO_ENCODED_RUSTFLAGS', 'RUSTC_WRAPPER'):
            self.assertNotIn(name, env)


if __name__ == '__main__':
    unittest.main()

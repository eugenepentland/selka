#!/usr/bin/env python3
"""Check LPT partitioning and the telemetry trust boundary."""
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import verification_shard_plan as shard_plan


class ShardPlanTests(unittest.TestCase):
    def test_default_assignments_are_unique_and_watched_by_the_coordinator(self):
        import verify_cache
        root = Path(__file__).resolve().parent.parent
        for label, identity, count in [('core', 'src/core/root_test.zig', 10),
                                       ('unit', 'src/root_test.zig', 12),
                                       ('cli', 'test/integration.zig', 6)]:
            relative = 'tests/shard-plans/' + label + '.json'
            plan = json.loads((root / relative).read_text())
            self.assertEqual((plan['version'], plan['root'], plan['shards']), (1, identity, count))
            names = [row['name'] for row in plan['tests']]
            self.assertEqual(names, sorted(set(names)))
            self.assertTrue(all(type(row['shard']) is int and 0 <= row['shard'] < count for row in plan['tests']))
            self.assertTrue(any(verify_cache.matches_recipe(relative, recipe, root)
                                for recipe in verify_cache.CONFIG_INPUTS))
        # Provenance contains durations, but only assignment bytes invalidate runs.
        self.assertFalse(any(verify_cache.matches_recipe('tests/shard-plans/provenance.json', recipe, root)
                             for recipe in verify_cache.CONFIG_INPUTS))

    def test_retired_tests_are_in_no_default_plan(self):
        root = Path(__file__).resolve().parent.parent
        retired = json.loads((root / 'tests/shard-plans/retired.json').read_text())
        for label, names in retired.items():
            plan = json.loads((root / 'tests/shard-plans' / (label + '.json')).read_text())
            self.assertTrue(names)
            self.assertFalse({row['name'] for row in plan['tests']} & set(names))

    @staticmethod
    def report(times):
        return dict(actions=[dict(test_telemetry=[dict(
            producer='zig-test-protocol-v1', status='observed', complete=True,
            tests=[dict(test_id='root.zig::' + name, elapsed_ns=ns, state='passed',
                        elapsed_scope='runner-protocol-interval') for name, ns in times.items()])])])

    def test_medians_reject_outliers_and_do_not_treat_sparse_tests_as_measured(self):
        documents = [self.report({'x.test.a': 10, 'x.test.b': 100, 'x.test.sparse': 1}),
                     self.report({'x.test.a': 11, 'x.test.b': 200}),
                     self.report({'x.test.a': 900, 'x.test.b': 300})]
        times, summary = shard_plan.median_observations(documents, 'root.zig')
        self.assertEqual(times, {'x.test.a': 11, 'x.test.b': 200})
        self.assertEqual(summary['samples_per_test'], {'x.test.a': 3, 'x.test.b': 3})
        self.assertEqual(summary['insufficient_samples'], ['x.test.sparse'])
        self.assertEqual(shard_plan.median_observations(list(reversed(documents)), 'root.zig'), (times, summary))

    def test_multiple_intervals_in_one_run_do_not_count_as_multiple_runs(self):
        document = self.report({'x.test.a': 5})
        document['actions'][0]['test_telemetry'] *= 3
        with self.assertRaisesRegex(ValueError, 'three distinct'):
            shard_plan.median_observations([document], 'root.zig')
        times, _ = shard_plan.median_observations([document, self.report({}), self.report({})], 'root.zig')
        self.assertEqual(times, {})

    def test_even_median_keeps_integer_nanosecond_precision(self):
        values = [2**62 + offset for offset in (0, 1, 4, 500)]
        times, _ = shard_plan.median_observations([self.report({'x.test.a': value}) for value in values], 'root.zig')
        self.assertEqual(times['x.test.a'], 2**62 + 2)

    def test_default_zig_jobs_are_explicit_and_follow_affinity(self):
        import verify_cache
        with patch.object(verify_cache.os, 'sched_getaffinity', return_value={3, 5}):
            options = verify_cache.parse_options([])
            self.assertEqual([arg for arg in options if arg.startswith('-j')], ['-j1'])
            self.assertIn('-j1', verify_cache.parse_options(['-j1']))
        with patch.object(verify_cache.os, 'sched_getaffinity', return_value={3}):
            self.assertFalse(any(arg.startswith('-j') for arg in verify_cache.parse_options([])))
        with patch.object(verify_cache.os, 'sched_getaffinity', return_value=set()):
            with self.assertRaisesRegex(verify_cache.VerificationError, 'allowed CPU'):
                verify_cache.parse_options([])

    def test_cli_rejects_too_few_and_duplicate_report_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            reports = [root / (str(index) + '.json') for index in range(3)]
            for path in reports:
                path.write_text(json.dumps(self.report({'x.test.a': 10})))
            output = root / 'plan.json'
            for inputs, reason in ((reports[:1], 'three distinct'), (reports, 'duplicate reports')):
                with self.subTest(reason=reason):
                    stderr = io.StringIO()
                    argv = ['verification_shard_plan.py', *map(str, inputs), '--root', 'root.zig',
                            '--shards', '2', '--output', str(output)]
                    with patch.object(sys, 'argv', argv), contextlib.redirect_stderr(stderr), self.assertRaises(SystemExit) as caught:
                        shard_plan.main()
                    self.assertEqual(caught.exception.code, 2)
                    self.assertIn(reason, stderr.getvalue())
                    self.assertFalse(output.exists())

    def test_lpt_avoids_modulo_hot_spots_and_partitions_every_observation(self):
        times = {'suite.test.' + name: ns for name, ns in zip('abcdef', [8, 7, 6, 5, 4, 3])}
        plan, summary = shard_plan.assign(times, 3, 'root.zig')
        self.assertEqual(len(plan['tests']), len(times))
        self.assertEqual(summary['predicted_shard_ns'], [11, 11, 11])
        self.assertEqual(summary['max_to_lower_bound'], 1)
        self.assertEqual(summary['longest_first'], [0, 1, 2])
        self.assertEqual(plan, shard_plan.assign(dict(reversed(list(times.items()))), 3, 'root.zig')[0])

    def test_only_complete_passed_native_intervals_affect_the_hint(self):
        def row(name, ns, **changes):
            return dict(test_id='root.zig::' + name, elapsed_ns=ns, state='passed',
                        elapsed_scope='runner-protocol-interval', **changes)
        good = row('suite.test.known', 9)
        skipped = dict(row('suite.test.skipped', 99), state='skipped')
        failed = dict(row('suite.test.failed', 88), state='failed')
        wrong_scope = dict(row('suite.test.other_scope', 77), elapsed_scope='body')
        rows = [good, row('suite.test.known', 3), row('suite.test_0', 999), skipped, failed,
                wrong_scope, row('suite.test.bad', True), row('suite.test.negative', -1)]
        member = dict(producer='zig-test-protocol-v1', status='observed', complete=True, tests=rows)
        document = dict(actions=[dict(test_telemetry=[member, dict(member, complete=False)])])
        self.assertEqual(shard_plan.observations(document, 'root.zig'), {'suite.test.known': 9})
        self.assertEqual(shard_plan.observations(document, 'other.zig'), {})

    def test_empty_plan_preserves_fallback_and_zero_durations_are_stable(self):
        plan, summary = shard_plan.assign({}, 2, 'root.zig')
        self.assertEqual(plan['tests'], [])
        self.assertIsNone(summary['max_to_lower_bound'])
        plan, _ = shard_plan.assign({'x.test.b': 0, 'x.test.a': 0}, 2, 'root.zig')
        self.assertEqual([row['name'] for row in plan['tests']], ['x.test.a', 'x.test.b'])

    def test_the_core_shard_with_the_out_of_memory_check_is_the_one_build_zig_gives_the_larger_ceiling(self):
        # That test peaks at 1 GB where a core shard is declared 0.5 GB (the runner fails a step over its declaration), so
        # `core_memory_check_shard` in build.zig must name the shard the plan puts it in.
        root = Path(__file__).resolve().parent.parent
        plan = json.loads((root / 'tests/shard-plans/core.json').read_text())
        name = 'frontend_test.test.a check that runs out of memory names the host ceiling it reached and not a host failure'
        shards = [row['shard'] for row in plan['tests'] if row['name'] == name]
        self.assertEqual(len(shards), 1, 'the core plan must name the out-of-memory check')
        build = (root / 'build.zig').read_text()
        declared = int(build.split('const core_memory_check_shard: usize = ', 1)[1].split(';', 1)[0])
        self.assertEqual(shards[0], declared)
        self.assertIn('const shard_core_memory_check: u64 = 1536 * mib;', build)

    def test_bad_counts_and_durations_are_rejected(self):
        for count in (0, -1, 1025, True):
            with self.assertRaises(ValueError):
                shard_plan.assign({}, count, 'root.zig')
        for ns in (-1, True, 1.1):
            with self.assertRaises(ValueError):
                shard_plan.assign({'x.test.a': ns}, 2, 'root.zig')


if __name__ == '__main__':
    unittest.main()

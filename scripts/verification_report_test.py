#!/usr/bin/env python3
"""Focused tests of advisory dependency and execution reports."""
import json
from pathlib import Path
import tempfile
import unittest
import verification_report as report


def file(path, digest='a', **extra):
    return dict(path=path, sha256=digest * 64, **extra)


def summary(files=None, **common):
    return report.dependency_summary({'id': 'test'}, files or [], common)


class Reports(unittest.TestCase):
    def test_deterministic_and_immutable(self):
        files = [file('z'), file('a')]
        one = report.dependency_summary({'id': 'test'}, files, {'b': 2, 'a': 1})
        self.assertEqual(one, report.dependency_summary({'id': 'test'}, files[::-1], {'a': 1, 'b': 2}))
        files[0]['sha256'] = 'b' * 64
        self.assertEqual(json.loads(one)['files'][1]['sha256'], 'a' * 64)

    def test_precise_changes(self):
        old = summary([file('delete'), file('content'), file('mode', mode=1)], tools='old', environment='old')
        new = summary([file('add'), file('content', 'b'), file('mode', mode=2)], tools='new', environment='new')
        result = report.explain_miss(new, old)
        self.assertEqual(result['changes'], [
            dict(kind='common_changed', name='environment'), dict(kind='common_changed', name='tools'),
            dict(kind='file_added', name='add'), dict(kind='file_content_changed', name='content'),
            dict(kind='file_deleted', name='delete'), dict(kind='file_identity_changed', name='mode')])
        self.assertFalse(result['truncated'])

    def test_group_artifact_changes(self):
        old = report.dependency_summary({'id': 'test'}, [], {}, {'compiler': 'old'})
        new = report.dependency_summary({'id': 'test', 'inputs': ['new']}, [], {}, {'compiler': 'new'})
        self.assertEqual(report.explain_miss(new, old)['changes'], [
            dict(kind='group_changed', name='inputs'), dict(kind='artifacts_changed', name='compiler')])

    def test_unknown_is_not_false_cause(self):
        self.assertEqual(report.explain_miss(summary(), None)['status'], 'unknown')
        self.assertEqual(report.explain_miss(summary(), '{bad')['changes'], [])
        self.assertIn('cause unknown', report.explain_miss(summary(), summary())['reason'])
        self.assertIsNone(report.dependency_summary({}, [file('a'), file('a')], {}))
        self.assertIsNone(report.dependency_summary({}, [], {'value': float('nan')}))
        nested = []
        for _ in range(40):
            nested = [nested]
        self.assertIsNone(report.dependency_summary({}, [], {'nested': nested}))

    def test_bounded_records_and_changes(self):
        self.assertIsNone(summary([file(str(i)) for i in range(report.MAX_FILES + 1)]))
        self.assertIsNone(summary([], huge='x' * report.MAX_BYTES))
        result = report.explain_miss(summary([file(str(i)) for i in range(100)]), summary())
        self.assertEqual(len(result['changes']), report.MAX_CHANGES)
        self.assertTrue(result['truncated'])

    def test_io_corrupt_and_atomic(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'summary.json'
            self.assertIsNone(report.read_summary(path))
            self.assertTrue(report.write_summary(path, summary([file('a')])))
            self.assertEqual(report.read_summary(path), summary([file('a')]))
            self.assertFalse(report.write_summary(path, 'bad'))
            self.assertEqual(report.read_summary(path), summary([file('a')]))
            path.write_text('{"version":1,"version":1}')
            self.assertIsNone(report.read_summary(path))
            path.write_bytes(b'x' * (report.MAX_BYTES + 1))
            self.assertIsNone(report.read_summary(path))
            path.write_bytes(b'\xff')
            self.assertIsNone(report.read_summary(path))

    def test_nested_log_timings_are_not_added(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'log'
            path.write_text('Build Summary: 3/3 steps succeeded\n+- run test success 2s MaxRSS:12M\n|  +- compile test debug native cached 50ms MaxRSS:41M\n|  +- run guardian-check success 100µs\n')
            result = report.execution_timings(path)
            self.assertFalse(result['additive'])
            self.assertEqual(result['status'], 'observed')
            self.assertEqual([x['elapsed_seconds'] for x in result['observations'][:2]], [2, .05])
            self.assertAlmostEqual(result['observations'][2]['elapsed_seconds'], .0001)
            self.assertEqual(result['observations'][1]['kind'], 'build')
            self.assertEqual(result['observations'][0]['kind'], 'unknown')
            self.assertIsNone(result['cpu_seconds'])
            self.assertIsNone(result['aggregate_peak_rss_bytes'])

    def test_log_bounds_and_missing(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'log'
            self.assertEqual(report.execution_timings(path)['status'], 'unknown')
            path.write_text('no timings\n')
            self.assertEqual(report.execution_timings(path)['status'], 'unknown')
            path.write_text('x' * (report.MAX_LINE + 1) + '\n' + '+- run test success 2ms\n' * 300)
            result = report.execution_timings(path)
            self.assertTrue(result['truncated'])
            self.assertEqual(len(result['observations']), report.MAX_OBSERVATIONS)
            path.write_bytes(b'x' * (report.MAX_BYTES + 1))
            self.assertTrue(report.execution_timings(path)['truncated'])


if __name__ == '__main__':
    unittest.main()

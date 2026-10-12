#!/usr/bin/env python3
"""Adversarial tests of supported telemetry and advisory bounded reports."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest
import verification_telemetry as telemetry
import verification_report as report


def record(rows=None, selected=1, complete=True):
    return dict(version=1, producer='fixture', action_id='unit', member_id='unit/member/0',
                selected=selected, complete=complete,
                tests=rows if rows is not None else [dict(test_id='root.case', state='passed', elapsed_ns=12)])


class TelemetryTests(unittest.TestCase):
    def test_real_runner_captures_fast_failed_skipped_and_subtests(self):
        class Cases(unittest.TestCase):
            def test_pass(self):
                self.assertEqual(2 + 2, 4)
            def test_fail(self):
                self.fail('intentional fixture failure')
            @unittest.skip('fixture skip')
            def test_skip(self):
                self.fail('unreachable')
            def test_sub(self):
                with self.subTest(value=1):
                    self.assertEqual(1, 2)
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(Cases)
        result = telemetry.TelemetryRunner(stream=io.StringIO()).run(suite)
        captured = telemetry.validate_tests(telemetry.document(result, 'unit', 0))
        self.assertFalse(result.wasSuccessful())
        self.assertTrue(captured['complete'])
        self.assertEqual((captured['selected'], captured['executed'], captured['skipped'], captured['timed']), (4, 3, 1, 3))
        self.assertEqual([row['state'] for row in captured['tests']], ['failed', 'passed', 'skipped', 'failed'])
        self.assertEqual(captured['timing_coverage'], 'partial')
        self.assertEqual(captured['execution_timing_coverage'], 'complete')
        self.assertIsNone(result.telemetry_process['aggregate_peak_rss_bytes'])
        self.assertGreaterEqual(result.telemetry_process['user_cpu_seconds'], 0)
        self.assertEqual(result.telemetry_process['rss_scope'], 'process-lifetime-high-water')

    def test_failfast_is_partial_and_reuse_is_not_fresh_timing(self):
        class Cases(unittest.TestCase):
            def test_a(self):
                self.fail('fixture')
            def test_b(self):
                self.assertTrue(True)
        result = telemetry.TelemetryRunner(stream=io.StringIO(), failfast=True).run(
            unittest.defaultTestLoader.loadTestsFromTestCase(Cases))
        captured = telemetry.validate_tests(telemetry.document(result, 'unit', 0))
        self.assertFalse(captured['complete'])
        self.assertEqual(captured['timing_coverage'], 'partial')
        reused = telemetry.validate_tests(record([dict(test_id='case', state='reused', elapsed_ns=None)]))
        self.assertEqual((reused['executed'], reused['reused'], reused['timed']), (0, 1, 0))
        self.assertEqual(reused['timing_coverage'], 'partial')
        self.assertEqual(reused['execution_timing_coverage'], 'complete')

    def test_cli_failure_and_unwritable_telemetry_preserve_exit_status(self):
        script = Path(telemetry.__file__).resolve()
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / 'result.json'
            completed = subprocess.run([sys.executable, str(script), '--action-id', 'unit',
                                        '--output', str(destination), 'does_not_exist_fixture'],
                                       capture_output=True, text=True)
            self.assertEqual(completed.returncode, 1)
            self.assertIn('FAILED', completed.stderr)
            self.assertEqual(report.test_timings(destination)['tests'][0]['state'], 'failed')
            blocked = Path(directory) / 'blocked'
            blocked.mkdir()
            completed = subprocess.run([sys.executable, str(script), '--action-id', 'unit',
                                        '--output', str(blocked), 'verification_report_test'],
                                       capture_output=True, text=True)
            self.assertEqual(completed.returncode, 0)
            self.assertIn('Ran 12 tests', completed.stderr)
            self.assertTrue(blocked.is_dir())

    def test_process_measurement_scope_and_malformed_observations(self):
        observed = dict(scope='runner-process', rss_scope='process-lifetime-high-water',
                        user_cpu_seconds=.2, system_cpu_seconds=.1, peak_rss_bytes=4096)
        self.assertEqual(report.process_observations(observed)['peak_rss_bytes'], 4096)
        self.assertIsNone(report.process_observations(observed)['aggregate_peak_rss_bytes'])
        self.assertEqual(report.process_observations(dict(observed, user_cpu_seconds=float('inf')))['status'], 'unknown')
        self.assertEqual(report.process_observations(dict(observed, peak_rss_bytes=-1))['status'], 'unknown')
        self.assertEqual(report.process_observations()['status'], 'unknown')

    def test_invalid_documents_never_claim_coverage(self):
        variants = [record(selected=True), record(selected=0), record(complete='yes'),
                    record([dict(test_id='a', state='passed', elapsed_ns=-1)]),
                    record([dict(test_id='a', state='passed', elapsed_ns=True)]),
                    record([dict(test_id='a', state='reused', elapsed_ns=12)]),
                    record([dict(test_id='a', state='unknown', elapsed_ns=None)]),
                    record([dict(test_id='a', state='passed', elapsed_ns=0)] * 2, selected=2)]
        for variant in variants:
            self.assertEqual(telemetry.validate_tests(variant)['status'], 'unknown')
        self.assertEqual(telemetry.validate_tests(record(), action_id='wrong')['status'], 'unknown')
        self.assertEqual(telemetry.validate_tests(record(), member='unit/member/1')['status'], 'unknown')
        self.assertIsNone(report.test_timings()['selected'])

    def test_strict_bounded_io_and_partial_records(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'report'
            self.assertTrue(telemetry.write_document(path, record()))
            self.assertEqual(report.test_timings(path)['timed'], 1)
            path.write_text('{"version":1,"version":1}')
            self.assertEqual(report.test_timings(path)['status'], 'unknown')
            path.write_text(json.dumps(record())[:-1])
            self.assertEqual(report.test_timings(path)['status'], 'unknown')
            path.write_bytes(b'x' * (telemetry.MAX_BYTES + 1))
            self.assertEqual(report.test_timings(path)['status'], 'unknown')
            path.write_bytes(b'\xff')
            self.assertEqual(report.test_timings(path)['status'], 'unknown')
            self.assertFalse(telemetry.write_document(path, {'nan': float('nan')}))
        partial = telemetry.validate_tests(record(selected=2))
        self.assertFalse(partial['complete'])
        self.assertTrue(partial['truncated'])
        self.assertEqual(partial['timing_coverage'], 'partial')

    def test_diagnostics_are_bounded_detached_and_do_not_clear_dirty_authority(self):
        reason = dict(role='publication', facet='path', name='fixture', reason='watcher_event')
        dirty = dict(dirty=True, reasons=[reason])
        output = telemetry.stability_diagnostics(dirty['reasons'])
        self.assertTrue(dirty['dirty'])
        self.assertEqual(output['reasons'][0]['reason'], 'watcher_event')
        reason['reason'] = 'changed'
        self.assertEqual(output['reasons'][0]['reason'], 'watcher_event')
        bounded = telemetry.stability_diagnostics([reason] * 100)
        self.assertEqual(len(bounded['reasons']), telemetry.MAX_REASONS)
        self.assertTrue(bounded['truncated'])
        self.assertTrue(telemetry.stability_diagnostics([{}])['unknown'])
        self.assertTrue(telemetry.stability_diagnostics()['unknown'])
        self.assertTrue(telemetry.stability_diagnostics([dict(reason, name='x' * 1000)])['truncated'])

    def test_every_inventory_action_and_nested_phases_remain_visible(self):
        result = report.action_coverage([{'id': 'a'}, {'id': 'b'}, {'id': 'c'}],
                                       [{'id': 'a', 'state': 'executed'}, {'id': 'b', 'state': 'reused'}])
        self.assertEqual(result['selected'], 3)
        self.assertEqual(result['counts']['outstanding'], 1)
        self.assertEqual(result['actions'][-1], {'id': 'c', 'state': 'outstanding'})
        self.assertEqual(result['authority'], 'advisory-only')
        self.assertTrue(report.action_coverage([{'id': 'a'}], [{'id': 'wrong'}])['unknown'])
        self.assertTrue(report.action_coverage([{'id': 'a'}], [{'id': 'a'}, {'id': 'a'}])['unknown'])
        with self.assertRaises(ValueError):
            report.action_coverage([{'id': 'a'}, {'id': 'a'}], [])
        phases = report.phase_spans([dict(phase='action', start_ns=1, end_ns=20),
                                    dict(phase='test', start_ns=5, end_ns=10),
                                    dict(phase='invalid', start_ns=20, end_ns=0)])
        self.assertFalse(phases['additive'])
        self.assertTrue(phases['malformed'])
        self.assertEqual([span['elapsed_ns'] for span in phases['spans']], [19, 5])

    def test_enabling_collector_preserves_verdict_output_and_suite_selection(self):
        class Cases(unittest.TestCase):
            def test_ok(self):
                print('fixture stdout')
                self.assertEqual(1, 1)
        outcomes = []
        for runner in (unittest.TextTestRunner, telemetry.TelemetryRunner):
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                result = runner(stream=io.StringIO()).run(unittest.defaultTestLoader.loadTestsFromTestCase(Cases))
            outcomes.append((result.testsRun, result.wasSuccessful(), output.getvalue()))
        self.assertEqual(outcomes[0], outcomes[1])
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / 'blocked'
            destination.mkdir()
            self.assertFalse(telemetry.write_document(destination, record()))


if __name__ == '__main__':
    unittest.main()

import json
from pathlib import Path
import tempfile
import unittest

from experiments.application_comparison import session
from experiments.application_comparison.storage import read_json
from experiments.development_velocity.telemetry import (
    ObservedGateway, clipped_interval, diagnostic_codes, failure_diagnostic_codes, phase_records, summarize,
)


class TelemetryTests(unittest.TestCase):
    def test_clock_union_rejects_other_boot_and_clips_seal(self):
        def clock(n, boot='a'):
            return {'boot_id': boot, 'monotonic_ns': n, 'utc_ns': n}
        self.assertEqual(clipped_interval(clock(2), clock(8), clock(3), clock(7)), (3, 7))
        self.assertIsNone(clipped_interval(clock(1), clock(2), clock(3), clock(7)))
        with self.assertRaises(ValueError):
            clipped_interval(clock(2, 'b'), clock(8, 'b'), clock(3), clock(7))
        with self.assertRaises(ValueError):
            clipped_interval(clock(8), clock(2), clock(3), clock(7))

    def test_phase_records_leave_inclusive_measurements_separate(self):
        rows = [{'version': 'phase-timings-v1', 'kind': 'timing', 'name': name,
                 'inclusive': inclusive, 'duration_ns': duration}
                for name, inclusive, duration in [('total', True, 20), ('frontend', False, 11)]]
        data = 'compiler warning\n' + '\n'.join(json.dumps(x) for x in rows)
        self.assertEqual(phase_records(data), rows)
        self.assertEqual(diagnostic_codes('E_TYPE twice E_TYPE and E_BORROW_ALIAS'),
                         ['E_BORROW_ALIAS', 'E_TYPE'])
        rows[0]['duration_ns'] = -1
        with self.assertRaises(ValueError):
            phase_records(json.dumps(rows[0]))

    def test_successful_document_reads_are_not_compiler_failures(self):
        self.assertEqual(failure_diagnostic_codes({'returncode': 0, 'stdout': 'E_BORROW_ALIAS example'}), [])
        self.assertEqual(failure_diagnostic_codes({'returncode': 1, 'stderr': 'error[E_TYPE]: mismatch'}), ['E_TYPE'])
        self.assertEqual(failure_diagnostic_codes({'passed': False, 'diagnostics': [
            {'returncode': 0, 'stderr': 'E_EXAMPLE'}, {'returncode': 1, 'stderr': 'E_EXPORT_PLACEMENT'}]}),
            ['E_EXPORT_PLACEMENT'])

    def test_real_operations_capture_edits_failures_and_unknown_time(self):
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            baseline = parent / 'baseline'
            baseline.mkdir()
            (baseline / 'main.py').write_text('print(1)\n')
            root = parent / 'attempt'
            session.prepare(root, baseline, language='python', block='fixture', cohort='test',
                            participant='fixture', model='fixture', kind='fixture')
            session.start_preparation(root)
            session.start_task(root, 'passed')
            gateway = ObservedGateway(root, {})
            result = gateway.dispatch('command', {'purpose': 'edit', 'argv': [
                '/usr/bin/python3', '-B', '-c', "open('main.py','w').write('print(2)\\n')"]})
            self.assertEqual(result['returncode'], 0, result)
            result = gateway.dispatch('command', {'purpose': 'test', 'argv': [
                '/usr/bin/python3', '-B', '-c', 'raise SystemExit(7)']})
            self.assertEqual(result['returncode'], 7)
            output = gateway.dispatch('output', {'record': result['operation_record'], 'offset': 0, 'limit': 8192})
            self.assertEqual(json.loads(output['text'])['returncode'], 7)
            with self.assertRaises(ValueError):
                gateway.dispatch('command', {'purpose': 'pretend-reasoning', 'argv': ['/usr/bin/true']})
            session.seal(root, 'abandoned')
            profile = summarize(root)
            self.assertEqual(profile['operations'][0]['changed_files'], ['main.py'])
            self.assertEqual((root / 'telemetry/000000/changed-source/main.py').read_text(), 'print(2)\n')
            self.assertTrue(profile['operations'][1]['failed'])
            self.assertTrue(profile['operations'][3]['failed'])
            self.assertIsNone(profile['model_tokens'])
            self.assertAlmostEqual(profile['observed_operation_seconds'] + profile['unobserved_seconds'],
                                   profile['application_seconds'])
            self.assertEqual(profile['gateway_metrics']['phases']['working']['failed_commands'], 1)
            record = read_json(root / 'telemetry/000003/result.json')
            self.assertEqual(record['failure']['type'], 'ValueError')
            (root / 'telemetry/000003/result.json').unlink()
            with self.assertRaises(FileNotFoundError):
                summarize(root)


if __name__ == '__main__':
    unittest.main()

from pathlib import Path
import tempfile
import unittest
from experiments.application_comparison import pack_grading, session, task_pack, verified_grading
from experiments.application_comparison.execution import freeze_adapter
from experiments.application_comparison.storage import read_json, write_json


class PackGradingTests(unittest.TestCase):
    def test_all_cases_count_failures_and_resume_without_new_execution(self):
        self.run_case('fixture')

    def test_calibration_reports_keep_kind_and_reject_fixture_entry(self):
        self.run_case('calibration')

    def run_case(self, kind):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            pack = root / 'pack'
            task_pack.create(pack, task='eda-rotation', hidden_seed='fixture-suite')
            baseline = root / 'baseline'
            baseline.mkdir()
            # Deliberately wrong fixture executable under all three labels; this
            # tests grading orchestration, not language behavior or productivity.
            (baseline / 'main.py').write_text('print(\'{"error":"invalid-request"}\')\n')
            roots, adapters = [], {}
            for language in ('my', 'python', 'zig'):
                directory = root / language
                session.prepare(directory, baseline, language=language, block='eda-rotation',
                                cohort='fixture', participant=language, model='fixture', kind=kind, arm='language-focused')
                session.start_preparation(directory)
                session.start_task(directory, 'passed')
                submission = session.submit(directory)
                session.record_check(directory, 0, {'source_sha256': submission['source']['sha256'], 'passed': True})
                session.seal(directory, 'completed')
                roots.append(directory)
                adapters[language] = freeze_adapter(language, {}, [
                    {'phase': 'run', 'argv': ['/usr/bin/python3', '-S', '-B', 'main.py']}])
            # A fake executable fixture under the Zig label exercises suite reuse.
            # No real language timing or Guardian claims are made by this test.
            build = ("from pathlib import Path;p=Path('/cache/app');"
                     "p.write_text(" + repr("#!/usr/bin/python3\nprint('{\"error\":\"invalid-request\"}')\n") + ");p.chmod(0o700)")
            adapters['zig'] = freeze_adapter('zig', {}, [
                {'phase': 'build', 'argv': ['/usr/bin/python3', '-S', '-B', '-c', build]},
                {'phase': 'run', 'argv': ['/cache/app']}])
            output = root / 'grading'
            receipt = verified_grading.capture(adapters)
            verify = verified_grading.grade_fixture if kind == 'fixture' else verified_grading.grade_calibration
            grade = pack_grading.grade_fixture if kind == 'fixture' else pack_grading.grade_calibration
            verified = verify(pack, roots, adapters, output, environment=receipt)
            self.assertEqual(verified['environment_sha256'], receipt['sha256'])
            result = verified['grading']
            output = output / 'pack'
            self.assertEqual(result['case_count'], 7)
            self.assertEqual(result['record_kind'], kind)
            self.assertEqual(verified['record_kind'], kind)
            if kind == 'calibration':
                with self.assertRaisesRegex(ValueError, 'matching fixture trio'):
                    pack_grading.grade_fixture(pack, roots, adapters, root / 'wrong-kind')
                self.assertFalse((root / 'wrong-kind').exists())
            self.assertFalse(result['comparative_claim'])
            zig_records = [case['result']['outcomes']['zig']['execution'] for case in result['cases']]
            self.assertEqual(sum(step['phase'] == 'build' for record in zig_records
                                 for step in record['steps']), 1)
            self.assertEqual([record['build_reuse']['reused'] for record in zig_records],
                             [False] + [True] * 6)
            for language in adapters:
                self.assertFalse(result['outcomes'][language]['accepted'])
                self.assertEqual(result['outcomes'][language]['failed_cases'],
                                 ['documented-behavior', 'original-regressions', 'generated-maintenance'])
            # Preserve receipts and verify the retry returns existing case results.
            times = {path: path.stat().st_mtime_ns for path in output.glob('case-*/*-execution/*.stdout')}
            self.assertTrue(times)
            self.assertEqual(grade(pack, roots, adapters, output), result)
            self.assertEqual(times, {path: path.stat().st_mtime_ns for path in times})
            for directory in roots:
                path = directory / 'session.json'
                manifest = read_json(path)
                manifest['record_kind'] = 'agent'
                write_json(path, manifest)
            with self.assertRaisesRegex(ValueError, 'agent scoring is disabled'):
                pack_grading.grade_fixture(pack, roots, adapters, root / 'forbidden')
            self.assertFalse((root / 'forbidden').exists())


if __name__ == '__main__':
    unittest.main()

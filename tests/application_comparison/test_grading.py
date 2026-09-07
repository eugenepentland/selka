"""Coordinator behavior uses explicit fixture commands, not purported agent trials."""
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from experiments.application_comparison import grading, session
from experiments.application_comparison.execution import freeze_adapter, parse_output
from experiments.application_comparison.storage import read_json, write_json


class GradingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.roots = []
        self.adapters = {}
        for language in ('my', 'python', 'zig'):
            baseline = self.root / ('base-' + language)
            baseline.mkdir()
            (baseline / 'main.py').write_text('import json,sys\nr=json.load(sys.stdin)\nprint(json.dumps([x+1 for x in r]))\n')
            root = self.root / language
            session.prepare(root, baseline, language=language, cohort='fixture', block='one', participant=language, model='fixture')
            session.start_preparation(root)
            session.start_task(root, 'passed')
            row = session.submit(root)
            session.record_check(root, 0, {'source_sha256': row['source']['sha256'], 'passed': True})
            session.seal(root, 'completed')
            self.roots.append(root)
            self.adapters[language] = freeze_adapter(language, {}, [
                {'phase': 'run', 'argv': ['/usr/bin/python3', '-S', '-B', 'main.py']}])
        self.directory = self.root / 'grading'

    def grade(self, request=(1, 2), expected=(2, 3)):
        return grading.grade(self.roots, self.adapters, list(request), list(expected), self.directory,
                             grader_identity='fixture-add-one-v1')

    def test_shared_grading_and_unchanged_resume(self):
        report = self.grade()
        self.assertEqual(report['record_kind'], 'fixture')
        self.assertFalse(report['comparative_claim'])
        self.assertTrue(all(row['accepted'] for row in report['outcomes'].values()))
        self.assertEqual(self.grade(), report)
        for language in ('my', 'python', 'zig'):
            self.assertTrue((self.directory / (language + '-execution') / '00.stdout').exists())
        with self.assertRaisesRegex(ValueError, 'plan changed'):
            self.grade(request=(3,), expected=(4,))

    def test_raw_input_is_pinned_across_three_way_grading_and_resume(self):
        raw = b' [ 1, 2 ]\n'
        report = grading.grade(self.roots, self.adapters, None, [2, 3], self.directory,
                               grader_identity='fixture-raw-v1', request_bytes=raw)
        self.assertTrue(all(row['accepted'] for row in report['outcomes'].values()))
        self.assertEqual(grading.grade(self.roots, self.adapters, None, [2, 3], self.directory,
                                      grader_identity='fixture-raw-v1', request_bytes=raw), report)
        with self.assertRaisesRegex(ValueError, 'plan changed'):
            grading.grade(self.roots, self.adapters, None, [2, 3], self.directory,
                          grader_identity='fixture-raw-v1', request_bytes=b'[1,2]')

    def test_mismatch_is_a_defect_not_a_success(self):
        report = self.grade(expected=(9, 9))
        self.assertFalse(any(row['accepted'] for row in report['outcomes'].values()))

    def test_altered_sealed_source_is_rejected(self):
        (self.roots[0] / 'submissions/000/source/main.py').write_text('print("cheat")')
        with self.assertRaisesRegex(ValueError, 'snapshot changed'):
            self.grade()

    def test_correct_code_without_on_time_development_acceptance_is_not_a_win(self):
        # Simulate a recorded development check finishing after the common deadline.
        path = self.roots[0] / 'session.json'
        manifest = read_json(path)
        manifest['submissions'][0]['check']['finished']['monotonic_ns'] = manifest['task_started']['monotonic_ns'] + 1801 * 1_000_000_000
        write_json(path, manifest)
        result = self.grade()['outcomes']['my']
        self.assertTrue(result['behavior_passed'])
        self.assertFalse(result['development_accepted_in_budget'])
        self.assertFalse(result['accepted'])

    def test_changed_adapter_and_unfinished_grading_are_not_silently_retried(self):
        self.adapters['my']['commands'][0]['argv'].append('changed')
        with self.assertRaisesRegex(ValueError, 'adapter definition changed'):
            self.grade()
        self.adapters['my']['commands'][0]['argv'].pop()
        (self.directory / 'my-execution').mkdir(parents=True, exist_ok=True)
        with self.assertRaisesRegex(ValueError, 'unfinished grading'):
            self.grade()

    def test_output_protocol_rejects_duplicates_and_nonfinite_numbers(self):
        with self.assertRaises(ValueError):
            parse_output(b'{"x":1,"x":2}')
        with self.assertRaises(ValueError):
            parse_output(b'NaN')
        with self.assertRaises(ValueError):
            parse_output(b'1e999')


if __name__ == '__main__':
    unittest.main()

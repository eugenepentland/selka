from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from experiments.application_comparison import single_language_grading as grading, session, task_pack
from experiments.application_comparison.execution import freeze_adapter
from experiments.application_comparison.storage import read_json, write_json


class SingleLanguageTests(unittest.TestCase):
    def test_real_isolated_wrong_program_records_failures_and_resumes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            task_pack.create(root / 'pack', task='eda-rotation', hidden_seed='single-grader-fixture')
            baseline = root / 'baseline'
            baseline.mkdir()
            (baseline / 'main.py').write_text('print(\'{"error":"invalid-request"}\')\n')
            trial = root / 'my'
            session.prepare(trial, baseline, language='my', block='eda-rotation', cohort='fixture',
                participant='fixture', model='fixture', kind='calibration', arm='language-focused')
            adapter = freeze_adapter('my', {}, [{'phase': 'run', 'argv': ['/usr/bin/python3', '-S', '-B', 'main.py']}])
            config = {'language': 'my', 'sha256': adapter['sha256'], 'task_adapter': adapter}
            # Deliberate wrong-language fixture tests orchestration; no productivity claim.
            with patch.object(grading.trial_configuration, 'verify'):
                with self.assertRaisesRegex(ValueError, 'sealed matching'):
                    grading.grade(root / 'pack', trial, config, root / 'unsealed')
                session.start_preparation(trial)
                session.start_task(trial, 'passed')
                row = session.submit(trial)
                session.record_check(trial, 0, {'source_sha256': row['source']['sha256'], 'passed': True})
                session.seal(trial, 'completed')
                first = grading.grade(root / 'pack', trial, config, root / 'grading')
                self.assertFalse(first['accepted'])
                self.assertEqual(7, first['case_count'])
                self.assertTrue(first['failed_cases'])
                self.assertTrue(any(row['accepted'] for row in first['cases']))
                self.assertEqual(first, grading.grade(root / 'pack', trial, config, root / 'grading'))
                manifest = read_json(trial / 'session.json')
                manifest['participant_seconds'] += 1
                write_json(trial / 'session.json', manifest)
                with self.assertRaisesRegex(ValueError, 'plan changed'):
                    grading.grade(root / 'pack', trial, config, root / 'grading')

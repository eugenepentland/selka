from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from experiments.application_comparison import calibration_setup, cohort
from experiments.application_comparison.storage import read_json


class CalibrationSetupTests(unittest.TestCase):
    def test_freezes_complete_unscored_inputs_without_credentials_or_launches(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            zig = root / 'zig'
            zig.mkdir()
            (zig / 'lib').mkdir()
            (zig / 'zig').write_text('fixture; not executed')
            host = root / 'tool'
            host.write_text('fixture; not executed')
            settings = dict(blocks=['planner-input-boundary'], seed='fixture', model='fixture-model',
                max_reported_tokens_per_phase=100,
                budgets=dict(preparation_seconds=1200, task_seconds=1800, max_submissions=20, max_turns=6, max_output_tokens=37),
                byte_io=host, compiler=host, navigate=host, zig=zig, guardian=host)
            directory = root / 'setup'
            for changes in ({'model': ''}, {'max_reported_tokens_per_phase': 0}, {'blocks': ['unknown']},
                            {'blocks': ['planner-input-boundary'] * 2}):
                with self.assertRaises(ValueError):
                    calibration_setup.create(directory, **dict(settings, **changes))
                self.assertFalse(directory.exists())
            result = calibration_setup.create(directory, **settings)
            self.assertEqual(result, read_json(directory / 'result.json'))
            manifest = cohort.load(directory / 'cohort')
            self.assertEqual(result['cohort_sha256'], manifest['sha256'])
            self.assertEqual(result['scheduled_attempts'], 6)
            self.assertEqual(result['model_calls'], 0)
            self.assertFalse(result['scored_launch_authorized'])
            self.assertEqual(manifest['record_kind'], 'calibration')
            self.assertEqual(manifest['coordinator']['version'], 'application-coordinator-v2')
            self.assertEqual(set(manifest['configurations']['main/planner-input-boundary/my']['tools']), {'byte_io', 'compiler', 'navigate'})
            self.assertEqual(len(manifest['configurations']), 6)
            self.assertFalse((directory / 'cohort/calibration-reservations').exists())
            with self.assertRaises(FileExistsError):
                calibration_setup.create(directory, **settings)
            failed = root / 'failed-setup'
            with patch.object(calibration_setup.trial_configuration, 'freeze', side_effect=ValueError('fixture unavailable tool')):
                with self.assertRaisesRegex(ValueError, 'unavailable tool'):
                    calibration_setup.create(failed, **settings)
            self.assertTrue((failed / 'setup.json').exists())
            self.assertEqual(read_json(failed / 'interrupted.json')['type'], 'ValueError')
            self.assertFalse((failed / 'result.json').exists())
            with self.assertRaises(FileExistsError):
                calibration_setup.create(failed, **settings)


if __name__ == '__main__':
    unittest.main()

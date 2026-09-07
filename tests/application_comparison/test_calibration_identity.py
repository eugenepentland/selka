from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from experiments.application_comparison import cohort, cohort_sessions, session, session_driver


class CalibrationIdentityTests(unittest.TestCase):
    def test_calibration_is_distinct_and_requires_provenance_before_execution(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            baseline = root / 'baseline'
            baseline.mkdir()
            (baseline / 'main.py').write_text('print(1)')
            active = root / 'attempt'
            state = session.prepare(active, baseline, language='python', block='fixture', cohort='fixture',
                                    participant='fixture', model='fixture', kind='calibration')
            self.assertEqual(state['record_kind'], 'calibration')
            arguments = dict(tools={}, task_adapter=None, task_case=None, practice_source=None,
                             practice_adapter=None, practice_case=None, practice_prompt='practice',
                             task_prompt='task', transport_identity='fixture')
            with self.assertRaisesRegex(ValueError, 'fully bound provenance'):
                session_driver.run_calibration(active, None, **arguments)
            with self.assertRaisesRegex(ValueError, 'fresh prepared fixture'):
                session_driver.run_fixture(active, None, **arguments)
            self.assertFalse((active / 'driver').exists())
            self.assertEqual(session.load(active)['phase'], 'prepared')

    def test_calibration_cohort_cannot_omit_frozen_inputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / 'cohort'
            with self.assertRaisesRegex(ValueError, 'full frozen configuration'):
                cohort.freeze(destination, blocks=[], seed='fixture', model_settings={'model':'fixture'},
                              budgets={}, baseline_paths={}, task_paths={}, kind='calibration')
            self.assertFalse(destination.exists())

    def test_fixture_cannot_be_provisioned_as_calibration(self):
        with patch.object(cohort_sessions.cohort, 'load', return_value={'record_kind':'fixture'}):
            with self.assertRaises(ValueError):
                cohort_sessions.prepare_calibration('unused', 'unused', 'unused')


if __name__ == '__main__':
    unittest.main()

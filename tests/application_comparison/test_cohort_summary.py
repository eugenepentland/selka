import unittest
from pathlib import Path
import tempfile
from experiments.application_comparison.cohort_summary import aggregate, paired_outcomes, partial_phases
from experiments.application_comparison.storage import digest, write_json


class CohortSummaryTests(unittest.TestCase):
    def test_failures_and_unlaunched_attempts_stay_in_denominator(self):
        rows = [dict(status='graded', accepted=True, preparation_seconds=2, task_seconds=10, reported_tokens=20, usage_complete=True),
                dict(status='graded', accepted=False, preparation_seconds=4, task_seconds=30, reported_tokens=7, usage_complete=False),
                dict(status='not-launched', accepted=None)]
        result = aggregate(rows)
        self.assertEqual(result['accepted_fraction_of_assigned'], 1 / 3)
        self.assertFalse(result['grading_complete'])
        self.assertEqual(result['task']['median_seconds'], 20)
        self.assertEqual(result['task']['missing'], 1)
        self.assertEqual(result['reported_tokens'], 27)
        self.assertFalse(result['token_telemetry_complete'])
        self.assertIsNone(result['cost_per_accepted_change'])

    def test_pairing_counts_discordant_failures_and_conditional_times(self):
        rows = []
        outcomes = [(True, True, 10, 20), (True, False, 30, 5), (False, True, 1, 5),
                    (False, False, 1, 1), (True, True, None, 5)]
        for index, (a, b, at, bt) in enumerate(outcomes):
            rows.extend([dict(pair_id=str(index), language='my', status='graded', accepted=a, task_seconds=at),
                         dict(pair_id=str(index), language='python', status='graded', accepted=b, task_seconds=bt)])
        rows.append(dict(pair_id='pending', language='my', status='not-launched', accepted=None))
        result = paired_outcomes(rows)['my_vs_python']
        self.assertEqual(result['assigned_pairs'], 6)
        self.assertEqual(result['graded_pairs'], 5)
        self.assertEqual(result['both_accepted'], 2)
        self.assertEqual(result['left_only_accepted'], 1)
        self.assertEqual(result['right_only_accepted'], 1)
        self.assertEqual(result['neither_accepted'], 1)
        self.assertEqual(result['incomplete'], 1)
        self.assertEqual(result['paired_acceptance_difference'], 0)
        self.assertEqual(result['task_time_ratio_when_both_accepted']['median_ratio'], .5)
        self.assertEqual(result['task_time_ratio_when_both_accepted']['missing_timing_pairs'], 1)
        with self.assertRaisesRegex(ValueError, 'duplicate language'):
            paired_outcomes(rows + [rows[0]])
        self.assertIsNone(paired_outcomes([])['my_vs_zig']['paired_acceptance_difference'])

    def test_unknown_telemetry_is_not_zero(self):
        result = aggregate([dict(status='infrastructure-failure', accepted=None)])
        self.assertIsNone(result['reported_tokens'])
        self.assertIsNone(result['task']['total_seconds'])
        self.assertIsNone(aggregate([])['accepted_fraction_of_assigned'])

    def test_transport_stops_are_distinct_from_budgets_and_grading(self):
        rows = [dict(status='graded', accepted=False, task_stop='transport-timeout', seal_reason='abandoned'),
                dict(status='graded', accepted=False, task_stop='budget', seal_reason='budget'),
                dict(status='graded', accepted=True, preparation_stop='transport-timeout', task_stop='sealed', seal_reason='completed'),
                dict(status='infrastructure-failure', accepted=None, interruption_type='RuntimeError'),
                dict(status='not-launched', accepted=None)]
        result = aggregate(rows)
        self.assertEqual(result['accepted_fraction_of_assigned'], 1 / 5)
        self.assertEqual(result['task_stops'], {'counts': {'transport-timeout': 1, 'budget': 1, 'sealed': 1},
                                              'observed': 3, 'missing': 2})
        self.assertEqual(result['preparation_stops']['counts'], {'transport-timeout': 1})
        self.assertEqual(result['seal_reasons']['counts'], {'abandoned': 1, 'budget': 1, 'completed': 1})
        self.assertEqual(result['interruption_types']['counts'], {'RuntimeError': 1})
        self.assertEqual(result['interruption_types']['missing'], 4)

    def test_partial_receipts_reject_changed_configuration(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            phase = root / 'model-preparation'
            phase.mkdir()
            state = {'model': 'fixture', 'record_kind': 'fixture'}
            config = dict(state, phase='preparing')
            report = {'version': 'participant-model-loop-v1', 'record_kind': 'fixture',
                'configuration_sha256': digest(config), 'stop': 'preparation-ended',
                'reported_usage': {'input_tokens': 1, 'output_tokens': 1, 'total_tokens': 2}, 'usage_complete': True}
            write_json(phase / 'configuration.json', config)
            write_json(phase / 'result.json', report)
            observed = partial_phases(root, state)
            self.assertEqual(observed['partial_reported_tokens'], 2)
            self.assertNotIn('task_stop', observed)
            self.assertEqual(observed['partial_phase_receipts']['preparation']['result_sha256'], digest(report))
            write_json(phase / 'configuration.json', dict(config, model='different'))
            with self.assertRaisesRegex(ValueError, 'provenance mismatch'):
                partial_phases(root, state)


if __name__ == '__main__':
    unittest.main()

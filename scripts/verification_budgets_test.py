"""Advisory calibration rejects uncertainty instead of inventing samples."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from verification_budgets import calibrate, calibrate_observations, collect_report, read_json

A = 'a' * 64
B = 'b' * 64
C = 'c' * 64
INVENTORY = {'groups': [{'id': 'units'}], 'action_metadata': [
    {'id': 'units', 'steps': [{'label': 'verification action units member 0'}]}]}
LABEL = 'verification action units member 0'


def report(seconds=1, sequence=0):
    return {'success': True, 'status': 0, 'budget_context': A, 'sequence': sequence,
            'actions': [{'id': 'units', 'state': 'execute', 'action_key': B}],
            'admissions': [{'kind': 'gate', 'admitted': True, 'status': 0,
                            'timed_out': False, 'cancelled': False, 'incomplete': False,
                            'log_errors': [], 'logs': [{'capture_available': True,
                            'capture_complete': True, 'truncated': False,
                            'observed_steps': {'status': 'observed', 'truncated': False,
                            'malformed': False, 'observations': [{'node': LABEL,
                            'source': 'zig-summary', 'state': 'success', 'elapsed_seconds': seconds}]}}]}]}


def member(result):
    return result['actions'][0]['members'][0]


class BudgetTests(unittest.TestCase):
    def test_tiny_samples_have_no_recommendation_or_percentiles(self):
        result = calibrate([report(1)], INVENTORY)
        self.assertEqual(member(result)['status'], 'insufficient_samples')
        self.assertEqual(member(result)['sample_count'], 1)
        self.assertIsNone(member(result)['recommendation']['expected_seconds'])
        self.assertNotIn('p95', json.dumps(result))
        self.assertFalse(result['enforced'])

    def test_report_only_candidates_separate_targets_and_limits(self):
        result = calibrate([report(value, value) for value in range(1, 6)], INVENTORY)
        self.assertEqual(member(result)['status'], 'report_only_candidate')
        self.assertEqual(member(result)['median_seconds'], 3)
        self.assertEqual(member(result)['maximum_seconds'], 5)
        self.assertIsNone(member(result)['recommendation']['hard_deadline_seconds'])
        self.assertIsNone(result['actions'][0]['action_elapsed_seconds'])
        self.assertEqual(result['actions'][0]['targets'], dict(expected_seconds=None, regression_seconds=None, hard_deadline_seconds=None))

    def test_duplicate_report_does_not_inflate_samples(self):
        result = calibrate([report()] * 5, INVENTORY)
        self.assertEqual(member(result)['sample_count'], 1)

    def test_threshold_reassessment_preserves_samples(self):
        samples = collect_report(report(), INVENTORY)['observations']
        before = calibrate_observations(samples, INVENTORY)
        after = calibrate_observations(samples, INVENTORY, policy={'units': {'regression_seconds': 4}})
        self.assertEqual(member(before), member(after))
        self.assertEqual(after['actions'][0]['targets']['regression_seconds'], 4)
        self.assertFalse(after['enforced'])

    def test_cohorts_do_not_mix_environment_or_action_contract(self):
        other = report(2, 1)
        other['budget_context'] = C
        changed = report(3, 2)
        changed['actions'][0]['action_key'] = C
        result = calibrate([report(), other, changed], INVENTORY)
        self.assertEqual(member(result)['sample_count'], 1)
        self.assertEqual(member(result)['median_seconds'], 3)
        original = calibrate([report(), other, changed], INVENTORY, context=A, action_keys={'units': B})
        self.assertEqual(member(original)['median_seconds'], 1)

    def test_failed_reused_cancelled_incomplete_and_cached_rejected(self):
        mutations = [('success', False), ('status', 124)]
        for key, value in mutations:
            sample = report()
            sample[key] = value
            self.assertEqual(collect_report(sample, INVENTORY)['observations'], [])
        for key in ('timed_out', 'cancelled', 'incomplete'):
            sample = report()
            sample['admissions'][0][key] = True
            self.assertEqual(collect_report(sample, INVENTORY)['observations'], [])
        sample = report()
        sample['actions'][0]['state'] = 'reused'
        self.assertEqual(collect_report(sample, INVENTORY)['observations'], [])
        sample = report()
        sample['admissions'][0]['logs'][0]['observed_steps']['observations'][0]['state'] = 'cached'
        self.assertEqual(collect_report(sample, INVENTORY)['observations'], [])

    def test_capture_and_parser_integrity_are_required(self):
        for field, value in [('capture_available', False), ('capture_complete', False), ('truncated', True)]:
            sample = report()
            sample['admissions'][0]['logs'][0][field] = value
            self.assertEqual(collect_report(sample, INVENTORY)['observations'], [])
        for field in ('truncated', 'malformed'):
            sample = report()
            sample['admissions'][0]['logs'][0]['observed_steps'][field] = True
            self.assertEqual(collect_report(sample, INVENTORY)['observations'], [])
        sample = report()
        sample['admissions'][0]['log_errors'] = ['write failed']
        self.assertEqual(collect_report(sample, INVENTORY)['observations'], [])

    def test_ambiguous_labels_and_duplicate_rows_rejected(self):
        inventory = copy.deepcopy(INVENTORY)
        inventory['action_metadata'][0]['steps'].append({'label': LABEL})
        self.assertEqual(collect_report(report(), inventory)['observations'], [])
        sample = report()
        rows = sample['admissions'][0]['logs'][0]['observed_steps']['observations']
        rows.append(copy.deepcopy(rows[0]))
        self.assertEqual(collect_report(sample, INVENTORY)['observations'], [])

    def test_missing_identity_is_explicit_unknown(self):
        sample = report()
        del sample['budget_context']
        result = calibrate([sample], INVENTORY)
        self.assertEqual(member(result)['status'], 'unknown')
        self.assertTrue(result['rejections'])

    def test_history_is_bounded_and_keeps_provenance(self):
        samples = []
        for sequence in range(100):
            samples.extend(collect_report(report(sequence, sequence), INVENTORY)['observations'])
        result = calibrate_observations(samples, INVENTORY)
        self.assertEqual(member(result)['sample_count'], 64)
        self.assertEqual(member(result)['minimum_seconds'], 36)
        self.assertEqual(member(result)['provenance'][-1]['report_sha256'], samples[-1]['report_sha256'])

    def test_saved_provenance_cannot_duplicate_one_member_run(self):
        samples = collect_report(report(), INVENTORY)['observations']
        repeated = copy.deepcopy(samples[0])
        repeated['provenance'] = [0, 1, 0]
        result = calibrate_observations(samples + [repeated], INVENTORY)
        self.assertEqual(member(result)['sample_count'], 1)

    def test_overlapping_members_are_never_added(self):
        inventory = copy.deepcopy(INVENTORY)
        second = LABEL + ' second'
        inventory['action_metadata'][0]['steps'].append({'label': second})
        sample = report()
        rows = sample['admissions'][0]['logs'][0]['observed_steps']['observations']
        rows.append(dict(node=second, source='zig-summary', state='success', elapsed_seconds=2))
        result = calibrate([sample], inventory)
        self.assertEqual(len(result['actions'][0]['members']), 2)
        self.assertIsNone(result['actions'][0]['action_elapsed_seconds'])

    def test_strict_input_and_limits(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)/'bad'
            path.write_text('{"a":1,"a":2}')
            with self.assertRaises(ValueError):
                read_json(path)
        with self.assertRaises(ValueError):
            calibrate([report()] * 129, INVENTORY)
        with self.assertRaises(ValueError):
            calibrate([], INVENTORY, policy={'units': {'regression_seconds': float('nan')}})
        sample = report(float('inf'))
        self.assertEqual(collect_report(sample, INVENTORY)['observations'], [])
        self.assertEqual(collect_report([], INVENTORY)['observations'], [])


if __name__ == '__main__':
    unittest.main()

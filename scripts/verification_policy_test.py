"""Scoped policies cannot turn advisory evidence into enforcement or reuse."""
import copy
import unittest
import json
from pathlib import Path
import tempfile
from verification_budgets import evaluate_scoped_policy
from verification_policy import CLOCKS, evaluate, execution_identity, validate_policy


def policy(scope='admitted_action'):
    entry = {'action_id': 'units', 'scope': scope, 'targets': {'expected_seconds': 1,
             'regression_seconds': 2, 'hard_deadline_seconds': 3,
             'memory_ceiling_bytes': 1024, 'work_ceiling': 10}, 'work_unit': 'test_case'}
    if scope == 'individual_test':
        entry.update(member_id='units/0', test_id='example')
    return {'version': 1, 'mode': 'report_only', 'entries': [entry]}


def row(scope='admitted_action', **changes):
    value = dict(policy(scope)['entries'][0], clock=CLOCKS[scope], complete=True,
                 successful=True, fresh=True, elapsed_seconds=2.5,
                 aggregate_peak_rss_bytes=1000, completed_work=8)
    value.update(changes)
    return value


class PolicyTests(unittest.TestCase):
    def test_advisory_controls_do_not_change_execution_identity(self):
        before = policy()
        after = copy.deepcopy(before)
        after['entries'][0]['targets']['hard_deadline_seconds'] = 100
        self.assertEqual(execution_identity(before), execution_identity(after))
        result = evaluate(before, [row()])['entries'][0]
        self.assertEqual(result['evaluations']['regression_seconds']['status'], 'exceeded')
        self.assertEqual(result['evaluations']['hard_deadline_seconds']['status'], 'within_observed_samples')
        self.assertFalse(result['evaluations']['hard_deadline_seconds']['enforced'])
        self.assertEqual(result['headroom_status'], 'unqualified')

    def test_scope_and_clock_are_exact_and_nonadditive(self):
        for scope in CLOCKS:
            result = evaluate(policy(scope), [row(scope), row(scope, clock='queue')])['entries'][0]
            self.assertEqual(result['sample_count'], 1)
            self.assertFalse(result['additive'])
        result = evaluate(policy(), [row('setup_build')])['entries'][0]
        self.assertEqual(result['sample_count'], 0)
        self.assertEqual(result['evaluations']['expected_seconds']['status'], 'unknown')

    def test_incomplete_cancelled_reused_observations_are_not_samples(self):
        rows = [row(complete=False), row(successful=False), row(fresh=False)]
        self.assertEqual(evaluate(policy(), rows)['entries'][0]['sample_count'], 0)

    def test_process_rss_cannot_establish_aggregate_ceiling(self):
        sample = row()
        sample.pop('aggregate_peak_rss_bytes')
        sample['process_peak_rss_bytes'] = 5
        result = evaluate(policy(), [sample])['entries'][0]
        self.assertEqual(result['evaluations']['memory_ceiling_bytes']['status'], 'unknown')
        self.assertEqual(result['evaluations']['work_ceiling']['status'], 'within_observed_samples')

    def test_work_units_are_declared_and_not_interchangeable(self):
        result = evaluate(policy(), [row(work_unit='instruction')])['entries'][0]
        self.assertEqual(result['evaluations']['work_ceiling']['status'], 'unknown')
        document = policy()
        document['entries'][0].pop('work_unit')
        with self.assertRaisesRegex(ValueError, 'declared unit'):
            validate_policy(document)

    def test_enforcement_and_versions_rejected_even_with_evidence(self):
        document = policy()
        document['entries'][0]['headroom_evidence'] = ['a' * 64]
        document['mode'] = 'enforced'
        with self.assertRaisesRegex(ValueError, 'not qualified'):
            validate_policy(document)
        document = policy()
        document['version'] = True
        with self.assertRaises(ValueError):
            validate_policy(document)

    def test_legacy_exception_needs_review_and_no_relabeling(self):
        document = policy('individual_test')
        document['entries'][0]['exception'] = {'name': 'legacy-component', 'reason': 'cold setup', 'review_point': 'S10 final qualification'}
        self.assertEqual(validate_policy(document), document)
        document['entries'][0]['exception'].pop('review_point')
        with self.assertRaises(ValueError):
            validate_policy(document)

    def test_report_adapter_evaluates_policy_and_missing_scopes(self):
        inventory = {'groups': [{'id': 'units'}]}
        report = {'success': True, 'inputs_stable': True, 'scoped_budget_observations': [row()]}
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)/'policy.json'
            path.write_text(json.dumps(policy()))
            result = evaluate_scoped_policy(path, report, inventory)
            self.assertEqual(result['status'], 'evaluated')
            self.assertEqual(result['entries'][0]['sample_count'], 1)
            self.assertEqual(evaluate_scoped_policy(path, {}, inventory)['entries'][0]['sample_count'], 0)
            path.write_text('{"version":1,"version":1}')
            failed = evaluate_scoped_policy(path, report, inventory)
            self.assertEqual(failed['status'], 'unavailable')
            self.assertFalse(failed['enforced'])
            self.assertEqual(report['success'], True)

    def test_report_adapter_consumes_supported_test_rows_only(self):
        document = policy('individual_test')
        record = {'status': 'observed', 'complete': True, 'truncated': False, 'action_id': 'units',
                  'member_id': 'units/0', 'selected': 1,
                  'tests': [{'test_id': 'example', 'state': 'passed', 'elapsed_ns': 2500000000}]}
        report = {'success': True, 'inputs_stable': True,
                  'actions': [{'id': 'units', 'state': 'execute', 'test_telemetry': [record]}]}
        inventory = {'groups': [{'id': 'units'}]}
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)/'policy.json'
            path.write_text(json.dumps(document))
            self.assertEqual(evaluate_scoped_policy(path, report, inventory)['entries'][0]['sample_count'], 1)
            report['actions'][0]['state'] = 'reused'
            self.assertEqual(evaluate_scoped_policy(path, report, inventory)['entries'][0]['sample_count'], 0)
            report['actions'][0]['state'] = 'execute'
            record['complete'] = False
            self.assertEqual(evaluate_scoped_policy(path, report, inventory)['entries'][0]['sample_count'], 0)
            record['complete'] = True
            record['tests'][0]['state'] = 'skipped'
            record['tests'][0]['elapsed_ns'] = None
            self.assertEqual(evaluate_scoped_policy(path, report, inventory)['entries'][0]['sample_count'], 0)

    def test_report_adapter_rejects_unknown_actions_and_unavailable_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)/'policy.json'
            self.assertEqual(evaluate_scoped_policy(path, {}, {})['status'], 'unavailable')
            path.write_text(json.dumps(policy()))
            result = evaluate_scoped_policy(path, {}, {'groups': []})
            self.assertEqual(result['status'], 'unavailable')
            self.assertIn('absent', result['reason'])
        self.assertEqual(evaluate_scoped_policy(None, {}, {})['status'], 'not_configured')

    def test_ambiguous_or_malformed_policies_rejected(self):
        for mutate in (
            lambda p: p['entries'].append(copy.deepcopy(p['entries'][0])),
            lambda p: p['entries'][0].update(test_id='wrong-scope'),
            lambda p: p['entries'][0]['targets'].update(work_ceiling=1.5),
            lambda p: p['entries'][0]['targets'].update(regression_seconds=True),
            lambda p: p['entries'][0]['targets'].update(unknown=5),
        ):
            document = policy()
            mutate(document)
            with self.assertRaises(ValueError):
                validate_policy(document)


if __name__ == '__main__':
    unittest.main()

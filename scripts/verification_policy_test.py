"""Scoped policies cannot turn advisory evidence into enforcement or reuse."""
import copy
import unittest
import json
from pathlib import Path
import tempfile
from verification_budgets import evaluate_scoped_policy
from verification_policy import CLOCKS, PROTOCOL_CLOCK, calibrate_scope, evaluate, execution_identity, validate_policy


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


def captured(sequence=0, role='calibration', **changes):
    sample = row(context='a' * 64, action_key='b' * 64, measurement_context='c' * 64,
                 run_id=f'{sequence:064x}', evidence_sha256=f'{sequence + 100:064x}',
                 measurement_kind='isolated', sample_role=role)
    sample.update(changes)
    return sample


class PolicyTests(unittest.TestCase):
    def test_v2_clock_is_explicit_and_preserves_v1_default(self):
        document = policy('individual_test')
        interval = row('individual_test', clock=PROTOCOL_CLOCK)
        self.assertEqual(evaluate(document, [interval])['entries'][0]['sample_count'], 0)
        document['version'] = 2
        document['entries'][0]['clock'] = PROTOCOL_CLOCK
        result = evaluate(document, [interval, row('individual_test')])
        self.assertEqual(result['version'], 2)
        self.assertEqual(result['entries'][0]['sample_count'], 1)
        other_clock = copy.deepcopy(document['entries'][0])
        other_clock['clock'] = CLOCKS['individual_test']
        document['entries'].append(other_clock)
        both = evaluate(document, [interval, row('individual_test')])
        self.assertEqual([entry['sample_count'] for entry in both['entries']], [1, 1])
        document['entries'].pop()
        document['version'] = 1
        with self.assertRaisesRegex(ValueError, 'observation clock'):
            validate_policy(document)
        document['version'] = 2
        document['entries'][0]['clock'] = 'queue_time'
        with self.assertRaises(ValueError):
            validate_policy(document)

    def test_v2_adapter_does_not_relabel_protocol_interval(self):
        document = policy('individual_test')
        record = {'status': 'observed', 'complete': True, 'truncated': False, 'action_id': 'units',
                  'member_id': 'units/0', 'selected': 1, 'tests': [{'test_id': 'example',
                  'state': 'passed', 'elapsed_ns': 100, 'elapsed_scope': 'runner-protocol-interval'}]}
        report = {'success': True, 'inputs_stable': True,
                  'actions': [{'id': 'units', 'state': 'execute', 'test_telemetry': [record]}]}
        inventory = {'groups': [{'id': 'units'}]}
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)/'policy.json'
            path.write_text(json.dumps(document))
            self.assertEqual(evaluate_scoped_policy(path, report, inventory)['entries'][0]['sample_count'], 0)
            document['version'] = 2
            document['entries'][0]['clock'] = PROTOCOL_CLOCK
            path.write_text(json.dumps(document))
            self.assertEqual(evaluate_scoped_policy(path, report, inventory)['entries'][0]['sample_count'], 1)
            record['tests'][0]['elapsed_scope'] = 'unsupported'
            self.assertEqual(evaluate_scoped_policy(path, report, inventory)['entries'][0]['sample_count'], 0)

    def test_calibration_requires_provenance_and_independent_holdout(self):
        entry = policy()['entries'][0]
        result = calibrate_scope(entry, [row()])
        self.assertEqual(result['calibration_samples'], 0)
        self.assertEqual(result['rejections']['missing_capture_provenance'], 1)
        self.assertIn('independent_validation_runs', result['evidence_gaps'])
        samples = [captured(index, elapsed_seconds=index + 1) for index in range(5)]
        result = calibrate_scope(entry, samples + [captured(6, 'validation', elapsed_seconds=2.5)])
        self.assertEqual(result['candidate_expected_seconds'], 3)
        self.assertEqual(result['calibration_samples'], 5)
        self.assertEqual(result['validation_samples'], 1)
        self.assertEqual(result['headroom']['hard_deadline_seconds']['calibration']['status'], 'exceeded')
        holdout = result['headroom']['hard_deadline_seconds']['validation']
        self.assertEqual(holdout['remaining'], .5)
        self.assertEqual(holdout['maximum_to_threshold_ratio'], 2.5 / 3)
        self.assertEqual(result['qualification'], 'not_qualified')
        self.assertEqual(result['holdout_status'], 'contains_exceedances')
        self.assertFalse(result['enforced'])

    def test_calibration_deduplicates_runs_and_rejects_conflicts(self):
        entry = policy()['entries'][0]
        result = calibrate_scope(entry, [captured()] * 5)
        self.assertEqual(result['calibration_samples'], 1)
        self.assertEqual(result['rejections']['duplicate_run'], 4)
        conflict = captured(elapsed_seconds=7)
        result = calibrate_scope(entry, [captured(), conflict])
        self.assertEqual(result['calibration_samples'], 0)
        self.assertEqual(result['rejections']['conflicting_run'], 1)
        # A run cannot serve as both training and holdout.
        self.assertEqual(calibrate_scope(entry, [captured(), captured(role='validation')])['validation_samples'], 0)

    def test_calibration_separates_every_compatibility_dimension(self):
        entry = policy()['entries'][0]
        original = captured()
        for name, value in [('context', 'd' * 64), ('action_key', 'd' * 64),
                            ('measurement_context', 'd' * 64), ('measurement_kind', 'operational')]:
            other = captured(1, **{name: value})
            result = calibrate_scope(entry, [original, other])
            self.assertEqual(result['calibration_samples'], 1)
            self.assertEqual(result['rejections']['incompatible_cohort'], 1)
            cohort = {key: original[key] for key in ('context', 'action_key', 'measurement_context', 'measurement_kind')}
            result = calibrate_scope(entry, [original, other], cohort=cohort)
            self.assertEqual(result['cohort_selection'], 'explicit')
            self.assertEqual(result['capture_evidence'], [original['evidence_sha256']])
        wrong = captured(1, clock='shared_gate')
        self.assertEqual(calibrate_scope(entry, [original, wrong])['rejections']['different_clock'], 1)

    def test_calibration_metrics_and_evidence_gaps_remain_unknown(self):
        entry = policy()['entries'][0]
        entry['headroom_evidence'] = ['f' * 64]
        sample = captured(aggregate_peak_rss_bytes=None, completed_work=8.5)
        result = calibrate_scope(entry, [sample])
        self.assertIsNone(result['headroom']['memory_ceiling_bytes']['calibration']['observed_maximum'])
        self.assertIn('work_ceiling', result['unknown_metrics']['calibration'])
        self.assertEqual(result['unresolved_declared_evidence'], ['f' * 64])
        self.assertIn('declared_evidence_not_resolved', result['evidence_gaps'])
        evaluated = evaluate(policy(), [captured(aggregate_peak_rss_bytes=1.5, completed_work=8.5)])['entries'][0]
        self.assertEqual(evaluated['evaluations']['memory_ceiling_bytes']['status'], 'unknown')
        self.assertEqual(evaluated['evaluations']['work_ceiling']['status'], 'unknown')
        sample = captured(work_unit='different_unit')
        self.assertEqual(calibrate_scope(entry, [sample])['headroom']['work_ceiling']['calibration']['status'], 'unknown')

    def test_calibration_retains_bounded_distinct_history_and_holdout(self):
        entry = policy()['entries'][0]
        result = calibrate_scope(entry, [captured(index) for index in range(70)] +
                                 [captured(100 + index, 'validation') for index in range(70)])
        self.assertEqual(result['calibration_samples'], 64)
        self.assertEqual(result['validation_samples'], 64)
        self.assertEqual(result['rejections']['history_evicted'], 12)
        self.assertEqual(len(result['capture_evidence']), 128)
        self.assertFalse(result['enforced'])

    def test_calibration_failure_flags_and_operational_quality(self):
        entry = policy()['entries'][0]
        for flag in ('cancelled', 'timed_out', 'incomplete', 'truncated'):
            sample = captured(**{flag: True})
            self.assertEqual(calibrate_scope(entry, [sample])['calibration_samples'], 0)
            self.assertEqual(evaluate(policy(), [sample])['entries'][0]['sample_count'], 0)
        result = calibrate_scope(entry, [captured(index, measurement_kind='operational') for index in range(5)])
        self.assertEqual(result['status'], 'report_only_candidate')
        self.assertIn('isolated_measurement', result['evidence_gaps'])
        self.assertEqual(result['qualification'], 'not_qualified')

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

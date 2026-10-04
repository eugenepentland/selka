"""Acceptance failures use synthetic current rounds and archived provenance, never timings."""
import copy
import gzip
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import goal110 as goal

ARCHIVE = Path(__file__).parent / 'candidates/final-730a86e6-releasefast-20261003.json.gz'


def fixture(cases=('mutate_nested',)):
    report, _ = goal.read_document(ARCHIVE)
    report.update(status='subset', coverage=list(cases), measurement_session_id='first-session',
                  measurement_started_utc='2026-10-04T01:00:00+00:00', finished_utc='2026-10-04T01:01:00+00:00')
    report['plans'] = [p for p in report['plans'] if p['case'] in cases]
    report['samples'] = []
    for plan in report['plans']:
        for arm in goal.ARMS:
            for rnd in range(report['rounds']):
                factor = 1 if arm == 'my-llvm' else 2
                report['samples'].append({**plan, 'arm': arm, 'round': rnd, 'kernel_ns': factor * 100 * plan['iterations']})
    return report


def confirmation(first):
    report = copy.deepcopy(first)
    report.update(measurement_session_id='second-session', measurement_started_utc='2026-10-04T01:02:00+00:00',
                  finished_utc='2026-10-04T01:03:00+00:00')
    return report


def unchecked_analyze(report, evidence_id='B1', second=None, checks=None):
    anchor, _ = goal.read_document(ARCHIVE)
    # These fixtures exercise the new contract; expanded verifier has independent full fixtures.
    with patch.object(goal, 'verify'):
        return goal.analyze(report, anchor, evidence_id, second, checks)


class GoalTests(unittest.TestCase):
    def test_per_size_current_winners_and_self_intervals(self):
        report = fixture()
        for sample in report['samples']:
            if sample['profile'] == 'large' and sample['arm'] == 'my-qbe':
                sample['kernel_ns'] /= 4
        small, large = goal.session_rows(report)
        self.assertEqual(small['fastest_arms'], ['my-llvm'])
        self.assertEqual(large['fastest_arms'], ['my-qbe'])
        self.assertEqual(large['backends']['my-llvm']['state'], 'O')
        for row in (small, large):
            self.assertEqual(row['backends']['my-llvm']['intervals']['my-llvm'], [1, 1])
            self.assertEqual(len(row['backends']['my-llvm']['intervals']), 6)

    def test_missing_arm_duplicate_round_and_unknown_arm_rejected(self):
        for mutation in ('missing', 'duplicate', 'unknown'):
            report = fixture()
            if mutation == 'missing':
                report['samples'] = [s for s in report['samples'] if s['arm'] != 'my-qbe']
                report['frozen_reference_samples'] = [{'arm': 'my-qbe', 'round': i} for i in range(15)]
            elif mutation == 'duplicate':
                report['samples'].append(report['samples'][0])
            else:
                report['samples'][0]['arm'] = 'original-winner'
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                goal.session_rows(report)

    def test_threshold_is_unrounded_and_inclusive(self):
        for ratio, state in ((1.1, 'P'), (1.1000000001, 'O')):
            report = fixture()
            for plan in report['plans']:
                plan['iterations'] = 1
            for sample in report['samples']:
                sample['iterations'] = 1
                sample['kernel_ns'] = 1000 * (ratio if sample['arm'] == 'my-llvm' else 1)
            with self.subTest(ratio=ratio):
                self.assertEqual(goal.session_rows(report)[0]['backends']['my-llvm']['state'], state)

    def test_current_fastest_requires_intervals_against_every_other_arm(self):
        report = fixture()
        for sample in report['samples']:
            if sample['arm'] == 'my-qbe':
                sample['kernel_ns'] = (200 if sample['round'] < 8 else 80) * sample['iterations']
        row = goal.session_rows(report)[0]
        self.assertEqual(row['fastest_arms'], ['my-llvm'])
        self.assertEqual(row['backends']['my-llvm']['ratio'], 1)
        self.assertGreater(row['backends']['my-llvm']['intervals']['my-qbe'][1], 1.1)
        self.assertEqual(row['backends']['my-llvm']['state'], 'I')

    def test_normal_independent_sessions_are_required(self):
        first = fixture()
        identity = goal.execution_identity(first)
        for mutation, message in (('same_session', 'reuses'), ('short', '15 rounds'), ('warmups', '3 warmups'),
                                  ('overlap', 'overlap'), ('candidate', 'candidate ID'), ('debug', 'ReleaseFast')):
            second = confirmation(first)
            left = copy.deepcopy(first)
            if mutation == 'same_session':
                second['measurement_session_id'] = left['measurement_session_id']
            elif mutation == 'short':
                second['rounds'] = 5
            elif mutation == 'warmups':
                second['warmup_rounds'] = 2
            elif mutation == 'overlap':
                second['measurement_started_utc'] = left['measurement_started_utc']
            elif mutation == 'candidate':
                second['identity']['candidate_id'] += '-other'
            else:
                for report in (left, second):
                    receipt = report['identity']['compiler_build_receipt']['receipt']
                    receipt['compiler_optimize'] = 'Debug'
                    receipt['command'] = [arg.replace('ReleaseFast', 'Debug') for arg in receipt['command']]
                identity = goal.execution_identity(left)
            with self.subTest(mutation=mutation), self.assertRaisesRegex(ValueError, message):
                goal.confirmation_identity(left, second, identity, goal.execution_identity(second))

    def test_production_guest_compiler_policy_and_source_mismatches(self):
        first = fixture()
        for mutation in ('production', 'guest', 'compiler', 'isa', 'benchmark'):
            second = confirmation(first)
            if mutation == 'production':
                second['identity']['compiler_build_receipt']['receipt']['sources_after']['src/compiler.zig'] = 'f' * 64
            elif mutation == 'guest':
                second['binary_hashes']['legacy/my-qbe'] = 'f' * 64
            elif mutation == 'compiler':
                second['identity']['compiler_build_receipt']['receipt']['compiler_sha256'] = 'f' * 64
            elif mutation == 'isa':
                second['identity']['target_policy']['my-llvm'] = 'forced native CPU'
            else:
                second['identity']['sources']['ports/main.my'] = 'f' * 64
            with self.subTest(mutation=mutation), self.assertRaisesRegex(ValueError, 'identity mismatch'):
                goal.confirmation_identity(first, second, goal.execution_identity(first), goal.execution_identity(second))

    def test_docs_only_revisions_can_match_exact_production_and_guests(self):
        first = fixture()
        second = confirmation(first)
        second['identity']['source_revision'] = 'b' * 40
        second['identity']['compiler_build_receipt']['receipt']['source_revision'] = 'b' * 40
        second['identity']['compiler_build_receipt']['receipt']['sources_after']['docs/reference.md'] = 'f' * 64
        second['identity']['sources']['CANDIDATES.md'] = 'f' * 64
        goal.confirmation_identity(first, second, goal.execution_identity(first), goal.execution_identity(second))

    def test_starting_references_inputs_and_policy_cannot_change(self):
        first = fixture()
        original = goal.execution_identity(first)
        for field in ('binary_hashes', 'tools', 'benchmark_sources', 'policy'):
            changed = copy.deepcopy(original)
            if field == 'binary_hashes':
                changed[field]['legacy/rust'] = 'f' * 64
            elif field == 'tools':
                changed[field]['rust']['version'] = 'new'
            elif field == 'benchmark_sources':
                changed[field]['ports/main.my'] = 'f' * 64
            else:
                changed[field]['build_environment']['GOAMD64'] = 'v3'
            with self.subTest(field=field), self.assertRaises(ValueError):
                goal.check_anchor(changed, original)

        contract_change = fixture()
        contract_change['identity']['sources']['CONTRACT.md'] = 'f' * 64
        with self.assertRaisesRegex(ValueError, 'benchmark source/input'):
            goal.check_anchor(goal.execution_identity(contract_change), original)

    def test_backend_must_match_recorded_command(self):
        report = fixture()
        command = report['identity']['commands']['legacy/my-llvm']
        command[command.index('--backend') + 1] = 'qbe'
        with self.assertRaisesRegex(ValueError, 'actual guest backend'):
            goal.execution_identity(report)

    def test_confirmation_failure_cannot_be_hidden_by_passing_first_session(self):
        first = fixture()
        second = confirmation(first)
        for sample in second['samples']:
            if sample['arm'] == 'my-qbe':
                sample['kernel_ns'] /= 4
        result = unchecked_analyze(first, second=second)
        self.assertTrue(all(r['backends']['my-llvm']['state'] == 'I' for r in result['rows']))
        self.assertFalse(result['full_suite_confirmation'])
        result = unchecked_analyze(first, second=confirmation(first))
        self.assertTrue(all(r['backends']['my-llvm']['timing_confirmed'] for r in result['rows']))
        self.assertTrue(all(r['backends']['my-llvm']['state'] == 'P' for r in result['rows']))

    def test_correctness_receipt_binds_scope_artifacts_and_check_logs(self):
        first = fixture()
        identity_hash = goal.content_hash(goal.execution_identity(first))
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'checks.log'
            log.write_bytes(b'passed nearby inputs')
            receipt = {'schema': 'mylang-runtime-goal110-checks-v1', 'status': 'pass',
                       'execution_identity_sha256': identity_hash, 'coverage': first['coverage'],
                       'checks': [{'name': kind, 'kind': kind, 'status': 'pass', 'path': str(log),
                                   'sha256': goal.hashlib.sha256(log.read_bytes()).hexdigest()}
                                  for kind in ('qualification', 'holdout')]}
            result = unchecked_analyze(first, second=confirmation(first), checks=receipt)
            self.assertTrue(all(r['backends']['my-llvm']['state'] == 'C' for r in result['rows']))
            self.assertFalse(result['goal_complete'])
            changed = copy.deepcopy(receipt)
            changed['execution_identity_sha256'] = 'f' * 64
            with self.assertRaisesRegex(ValueError, 'identity mismatch'):
                unchecked_analyze(first, checks=changed)
            changed = copy.deepcopy(receipt)
            changed['coverage'] = ['bytes_scan']
            with self.assertRaisesRegex(ValueError, 'coverage mismatch'):
                unchecked_analyze(first, checks=changed)
            log.write_bytes(b'failed')
            with self.assertRaisesRegex(ValueError, 'log changed'):
                unchecked_analyze(first, checks=receipt)

    def test_partial_dashboard_preserves_unmeasured_evidence_and_stales_confirmations(self):
        full = fixture(tuple(goal.inventory()))
        full['status'] = 'complete'
        base = unchecked_analyze(full, 'B0')
        partial = unchecked_analyze(fixture(), 'B1')
        for row in partial['rows']:
            row['backends']['my-llvm']['state'] = 'C'
        merged = goal.dashboard([base, partial])
        self.assertEqual(len(merged['rows']), 80)
        self.assertEqual(merged['counts']['my-llvm']['C'], 2)
        self.assertTrue(all(r['evidence_id'] == 'B0' for r in merged['rows'] if r['case'] != 'mutate_nested'))
        self.assertFalse(merged['goal_complete'])
        production = copy.deepcopy(partial['execution_identity']['production_sources'])
        production['src/compiler.zig'] = 'f' * 64
        stale = goal.dashboard([base, partial], 'f' * 40, production)
        self.assertEqual(stale['counts']['my-llvm']['S'], 2)
        self.assertTrue(stale['mixed_production_evidence'])
        self.assertEqual(stale['rows'][0]['ratios'], merged['rows'][0]['ratios'])
        with self.assertRaisesRegex(ValueError, 'complete 80-cell'):
            goal.dashboard([partial])
        with self.assertRaisesRegex(ValueError, 'cannot be overwritten'):
            goal.dashboard([base, partial, partial])

    def test_completed_subsets_never_establish_full_suite_acceptance(self):
        full = fixture(tuple(goal.inventory()))
        full['status'] = 'complete'
        base = unchecked_analyze(full, 'B0')
        updates = [base]
        for index, case in enumerate(goal.inventory()):
            update = unchecked_analyze(fixture((case,)), f'B{index + 1}')
            for row in update['rows']:
                row['backends']['my-llvm']['state'] = 'C'
            updates.append(update)
        result = goal.dashboard(updates)
        self.assertEqual(result['counts']['my-llvm']['C'], 80)
        self.assertFalse(result['goal_complete'])
        self.assertEqual(result['latest_complete_integrated_evidence'], 'B0')

    def test_reopening_and_mixed_revision_do_not_average_failures_away(self):
        full = fixture(tuple(goal.inventory()))
        full['status'] = 'complete'
        base = unchecked_analyze(full, 'B0')
        for row in base['rows']:
            row['backends']['my-llvm']['state'] = 'C'
        base.update(goal_complete=True, full_suite_confirmation=True, full_repository_checks=True)
        self.assertTrue(goal.dashboard([base])['goal_complete'])
        partial = unchecked_analyze(fixture(), 'B1')
        partial['execution_identity']['production_sources']['src/compiler.zig'] = 'f' * 64
        partial['execution_identity_sha256'] = goal.content_hash(partial['execution_identity'])
        partial['production_sources_sha256'] = goal.content_hash(partial['execution_identity']['production_sources'])
        partial['rows'][0]['backends']['my-llvm']['state'] = 'O'
        partial['rows'][0]['ratios']['my-llvm'] = 2
        result = goal.dashboard([base, partial])
        self.assertFalse(result['goal_complete'])
        self.assertTrue(result['mixed_production_evidence'])
        self.assertEqual(result['counts']['my-llvm']['R'], 1)
        self.assertEqual(result['counts']['my-llvm']['S'], 78)

    def test_archive_hashes_and_existing_output_cannot_be_silently_reused(self):
        report, archive = goal.read_document(ARCHIVE)
        self.assertEqual(archive['sha256'], '5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'evidence.json.gz'
            path.write_bytes(gzip.compress(json.dumps(report).encode()))
            _, entry = goal.read_document(path)
            self.assertEqual(goal.read_recorded(entry), report)
            path.write_bytes(gzip.compress(b'{}'))
            with self.assertRaisesRegex(ValueError, 'evidence file changed'):
                goal.read_recorded(entry)
            output = Path(directory) / 'proposal.json'
            output.write_text('{}')
            with self.assertRaisesRegex(ValueError, 'already exists'):
                goal.write_result(output, {}, [])


if __name__ == '__main__':
    unittest.main()

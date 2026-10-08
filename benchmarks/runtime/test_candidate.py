"""Candidate arithmetic tests use synthetic same-session data, never timed guests."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

from build_compiler import validate_receipt, digest
from compare_candidate import ARMS, bootstrap, build_comparison, target_rows


def fixture():
    targets, baseline_hash = target_rows()
    key = ('integer_math', 64)
    target = targets[key]
    count = 7
    plan = {'case': key[0], 'size': key[1], 'profile': 'small', 'group': 'compute', 'iterations': count,
            'unit': target['unit'], 'level': target['level'], 'calibration': {'limited': False}}
    reference = {'case': key[0], 'size': key[1], 'arm': target['reference_arm'],
                 'name': 'compute/' + target['reference_arm'], 'binary_sha256': 'archive', 'binary_path': '/archive',
                 'target_ns_per_iteration': target['target_ns_per_iteration']}
    samples, archived = [], []
    factors = {'my-llvm': .5, 'my-qbe': 2, 'rust': .8, 'go': 1.5, 'zig-safe': 1.2, 'zig-fast': 1}
    for arm in ARMS:
        for rnd, multiplier in enumerate((.9, 1, 1.1)):
            samples.append({**plan, 'arm': arm, 'round': rnd,
                            'kernel_ns': factors[arm] * target['target_ns_per_iteration'] * count * multiplier})
    for rnd, multiplier in enumerate((.9, 1, 1.1)):
        archived.append({**plan, 'arm': reference['arm'], 'round': rnd,
                         'kernel_ns': target['target_ns_per_iteration'] * count * multiplier})
    report = {'schema': 'mylang-runtime-expanded-v2', 'rounds': 3, 'plans': [plan], 'samples': samples,
              'frozen_reference_samples': archived, 'measurement_session_id': 'synthetic-session',
              'identity': {'candidate_id': 'fixture', 'source_revision': 'a' * 40},
              'binary_hashes': {'compute/' + arm: 'candidate-' + arm for arm in ARMS},
              'frozen_reference': {'baseline_sha256': baseline_hash, 'plans': [reference],
                                   'original_identity': {'binary_paths': {reference['name']: '/archive'}}}}
    return report, targets, baseline_hash


class CandidateTests(unittest.TestCase):
    def test_win_loss_and_changed_current_winner(self):
        report, targets, baseline_hash = fixture()
        result = build_comparison(report, targets, baseline_hash)
        self.assertEqual(result['status'], 'focused')
        self.assertEqual(len(result['frozen_targets']), 80)
        llvm, qbe = result['comparisons']
        self.assertEqual(llvm['ratio_to_frozen_target'], .5)
        self.assertEqual(qbe['ratio_to_frozen_target'], 2)
        self.assertEqual(llvm['numerical_target_status'], 'at_or_below')
        self.assertEqual(qbe['numerical_target_status'], 'open')
        self.assertEqual(llvm['concurrent_evidence'], 'faster_in_this_session')
        self.assertEqual(qbe['concurrent_evidence'], 'slower_in_this_session')
        self.assertEqual(llvm['current_fastest_arms'], ['my-llvm'])
        self.assertEqual(llvm['ratio_to_current_fastest'], 1)
        self.assertEqual(llvm['paired_bootstrap_95_interval'], [.5, .5])

    def test_tie_is_numerically_at_target_but_inconclusive(self):
        report, targets, baseline_hash = fixture()
        for sample in report['samples']:
            if sample['arm'] == 'my-llvm':
                sample['kernel_ns'] *= 2
        row = build_comparison(report, targets, baseline_hash)['comparisons'][0]
        self.assertEqual(row['ratio_to_frozen_target'], 1)
        self.assertEqual(row['concurrent_evidence'], 'inconclusive')
        self.assertEqual(row['paired_bootstrap_95_interval'], [1, 1])

    def test_freeze_does_not_renormalize_to_new_winner(self):
        report, targets, baseline_hash = fixture()
        for sample in report['samples']:
            if sample['arm'] == 'go':
                sample['kernel_ns'] /= 10
        row = build_comparison(report, targets, baseline_hash)['comparisons'][0]
        self.assertEqual(row['ratio_to_frozen_target'], .5)
        self.assertEqual(row['current_fastest_arms'], ['go'])
        self.assertAlmostEqual(row['ratio_to_current_fastest'], 10 / 3)

    def test_archived_samples_never_pair_with_new_samples(self):
        report, targets, baseline_hash = fixture()
        report['frozen_reference_samples'].pop()
        report['archived_samples'] = [{'round': 2, 'kernel_ns': 1}]
        with self.assertRaisesRegex(ValueError, 'missing concurrent'):
            build_comparison(report, targets, baseline_hash)

    def test_current_binary_identical_to_original_uses_current_rounds(self):
        report, targets, baseline_hash = fixture()
        ref = report['frozen_reference']['plans'][0]
        report['binary_hashes'][ref['name']] = ref['binary_sha256']
        report['frozen_reference_samples'] = []
        row = build_comparison(report, targets, baseline_hash)['comparisons'][0]
        self.assertFalse(row['supplemental_reference'])

    def test_ratio_of_medians_bootstrap_preserves_paired_indices(self):
        self.assertEqual(bootstrap([2, 200, 20000], [1, 100, 10000], 'paired'), [2, 2])
        self.assertEqual(bootstrap([2, 50, 101], [1, 10, 100], 'paired'), [1.01, 5])

    def test_receipt_detects_source_and_compiler_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / 'mylang'
            binary.write_bytes(b'compiler')
            receipt = {'schema': 'mylang-runtime-compiler-build-v1', 'status': 'complete', 'exit_status': 0,
                       'source_revision': 'a' * 40, 'sources_before': {'src/a.zig': 'hash'},
                       'sources_after': {'src/a.zig': 'hash'}, 'compiler_sha256': digest(binary)}
            validate_receipt(receipt, binary)
            stale = copy.deepcopy(receipt)
            stale['sources_after']['src/a.zig'] = 'changed'
            with self.assertRaisesRegex(ValueError, 'sources changed'):
                validate_receipt(stale, binary)
            binary.write_bytes(b'changed compiler')
            with self.assertRaisesRegex(ValueError, 'compiler differs'):
                validate_receipt(receipt, binary)

    def test_receipt_mode_must_match_actual_compiler_command(self):
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / 'mylang'
            binary.write_bytes(b'compiler')
            receipt = {'schema': 'mylang-runtime-compiler-build-v1', 'status': 'complete', 'exit_status': 0,
                       'source_revision': 'a' * 40, 'sources_before': {'src/a.zig': 'hash'},
                       'sources_after': {'src/a.zig': 'hash'}, 'compiler_sha256': digest(binary),
                       'compiler_optimize': 'Debug', 'command': ['zig', 'build', '-Doptimize=Debug']}
            validate_receipt(receipt, binary)
            receipt['compiler_optimize'] = 'ReleaseFast'
            with self.assertRaisesRegex(ValueError, 'optimization mode'):
                validate_receipt(receipt, binary)


if __name__ == '__main__':
    unittest.main()

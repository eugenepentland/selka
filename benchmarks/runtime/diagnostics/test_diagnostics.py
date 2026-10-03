"""Check diagnostic oracles and reject corrupt paired evidence without running guests."""
import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import prepare

spec = importlib.util.spec_from_file_location('diagnostic_replay', HERE / 'verify.py')
replay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(replay)


def cell(case, size, arm, count, elapsed, **extra):
    return {'case': case, 'size': size, 'arm': arm, 'iterations': count, 'seed': 42,
            'kernel_ns': elapsed, 'exit_status': 0, 'stderr': '',
            'checksum': replay.original_checksum(case, size, count, 42), **extra}


def source_report():
    report = {'schema': 'mylang-runtime-same-session-sources-v1', 'status': 'focused_complete',
              'rounds': 15, 'warmup_rounds': 3, 'inputs': {'main': {}, 'candidate': {}},
              'plans': [], 'samples': [], 'warmups': [], 'memory': [], 'qualification': [], 'comparisons': []}
    guests = ['main/my-llvm', 'main/my-qbe', 'candidate/my-llvm', 'candidate/my-qbe', 'original/rust']
    for size in replay.inventory()['integer_math']['sizes']:
        report['plans'].append({'case': 'integer_math', 'size': size, 'iterations': 7,
                                'guests': guests, 'original_reference': {'arm': 'rust'}})
        for arm in guests:
            value = 50 if arm.startswith('candidate') else 25 if arm.startswith('original') else 100
            for field, rounds in (('samples', range(15)), ('warmups', range(-3, 0))):
                for rnd in rounds:
                    report[field].append(cell('integer_math', size, arm, 7, value, round=rnd, order=guests))
            report['memory'].append(cell('integer_math', size, arm, 7, value))
            for probe_size, seed, count in ((2, 1, 1), (3, 42, 7), (17, 999983, 31)):
                row = cell('integer_math', probe_size, arm, count, value)
                row.update(seed=seed, checksum=replay.original_checksum('integer_math', probe_size, count, seed))
                report['qualification'].append(row)
        for arm in ('my-llvm', 'my-qbe'):
            for denominator, ratio in (('main/' + arm, .5), ('original/rust', 2.0)):
                report['comparisons'].append({'case': 'integer_math', 'size': size, 'numerator': 'candidate/' + arm,
                                             'denominator': denominator, 'ratio_of_medians': ratio,
                                             'paired_bootstrap_95_interval': [ratio, ratio]})
    return report


def component_report():
    report = {'schema': 'mylang-runtime-components-v1', 'status': 'diagnostic_complete',
              'rounds': 1, 'warmup_rounds': 0, 'plans': [], 'samples': [], 'warmups': [],
              'memory': [], 'qualification': [], 'comparisons': []}
    order = [role + '/' + arm for role in ('control', 'probe') for arm in replay.ARMS]
    for variant, case in replay.CASES.items():
        for size in replay.inventory()[case]['sizes']:
            report['plans'].append({'variant': variant, 'size': size, 'iterations': 7})
            for arm in replay.ARMS:
                for role, elapsed in (('control', 100), ('probe', 200)):
                    row = {'variant': variant, 'size': size, 'arm': arm, 'role': role, 'iterations': 7,
                           'seed': 42, 'exit_status': 0, 'stderr': '', 'kernel_ns': elapsed,
                           'checksum': replay.component_checksum(variant, role, size, 7, 42)}
                    report['samples'].append({**row, 'round': 0, 'order': order})
                    report['memory'].append(row)
                report['comparisons'].append({'variant': variant, 'size': size, 'arm': arm,
                                             'probe_to_control': 2, 'control_ns_per_iteration': 100 / 7,
                                             'probe_ns_per_iteration': 200 / 7, 'paired_bootstrap_95_interval': [2, 2]})
        for size, seed, count in ((2, 1, 1), (3, 42, 7), (17, 999983, 31)):
            for role in ('control', 'probe'):
                for arm in replay.ARMS:
                    report['qualification'].append({'variant': variant, 'size': size, 'arm': arm, 'role': role,
                                                    'iterations': count, 'seed': seed, 'exit_status': 0, 'stderr': '',
                                                    'kernel_ns': 100, 'checksum': replay.component_checksum(variant, role, size, count, seed)})
    return report


class DiagnosticTests(unittest.TestCase):
    def test_same_session_known_win_and_loss(self):
        self.assertEqual(replay.verify_sources(source_report()), 10)

    def test_source_report_rejects_corruption(self):
        for change in ('ratio', 'interval', 'checksum', 'missing_sample', 'duplicate_probe', 'unknown_arm', 'empty'):
            with self.subTest(change=change):
                report = source_report()
                if change == 'ratio':
                    report['comparisons'][0]['ratio_of_medians'] = .4
                elif change == 'interval':
                    report['comparisons'][0]['paired_bootstrap_95_interval'] = [.4, .6]
                elif change == 'checksum':
                    report['samples'][0]['checksum'] += 1
                elif change == 'missing_sample':
                    report['samples'].pop()
                elif change == 'duplicate_probe':
                    report['qualification'].append(copy.deepcopy(report['qualification'][0]))
                elif change == 'unknown_arm':
                    report['samples'][0]['arm'] = 'unknown/my-llvm'
                else:
                    report['plans'] = []
                with self.assertRaises(ValueError):
                    replay.verify_sources(report)

    def test_component_oracles_match_direct_small_loops(self):
        modulus = 1000000007
        for size in (2, 3, 17):
            for seed in (1, 42, 999983):
                for count in (1, 7, 31, 53):
                    values = [(seed + index * 13) % 1009 for index in range(size)]
                    arithmetic = sum(((index + batch % 17) * 17 + 23) // 7 % 1009
                                     for batch in range(count) for index in range(size)) % modulus
                    numbers = [(seed + index * 137) % 1000003 for index in range(size)]
                    strings = [str(-value if index % 3 == 0 else value) for index, value in enumerate(numbers)]
                    length = sum(len(strings[(seed + batch) % size]) for batch in range(count)) % modulus
                    for variant, expected in (('arithmetic_only', arithmetic), ('collection_only', sum(values) * count % modulus),
                                              ('text_without_score', length)):
                        self.assertEqual(replay.component_checksum(variant, 'probe', size, count, seed), expected)

    def test_all_component_cells_and_statistics(self):
        self.assertEqual(replay.verify_components(component_report()), 120)
        for field in ('samples', 'qualification', 'comparisons'):
            with self.subTest(field=field):
                report = component_report()
                report[field].pop()
                with self.assertRaises(ValueError):
                    replay.verify_components(report)
        report = component_report()
        report['comparisons'][0]['probe_to_control'] = 1.9
        with self.assertRaisesRegex(ValueError, 'ratio math mismatch'):
            replay.verify_components(report)

    def test_generated_copies_preserve_inputs_and_pin_dependencies(self):
        sources = {}
        for meta in prepare.VARIANTS.values():
            group = prepare.RUNTIME / 'expanded' / meta['group']
            for path in group.iterdir():
                if path.name in ('main.my', 'main.rs', 'main.go', 'main.zig', 'Cargo.toml', 'Cargo.lock'):
                    sources[str(path.relative_to(prepare.RUNTIME))] = prepare.sha(path.read_bytes())
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = root / 'manifest.json'
            manifest.write_text(json.dumps({'identity': {'candidate_id': 'unit-probe', 'source_revision': 'unit-source', 'sources': sources}}))
            result = prepare.prepare(manifest, root / 'copies')
            self.assertEqual(set(result['variants']), set(prepare.VARIANTS))
            for variant in result['variants'].values():
                self.assertEqual(len(variant['files']), 4)
                for row in [*variant['files'], *variant['dependencies']]:
                    self.assertEqual(prepare.sha(Path(row['generated']).read_bytes()), row['generated_sha256'])
                    self.assertEqual(prepare.sha((prepare.RUNTIME / row['source']).read_bytes()), row['source_sha256'])
            self.assertEqual(len(result['variants']['text_without_score']['dependencies']), 2)
            sources['expanded/compute/main.my'] = 'bad'
            manifest.write_text(json.dumps({'identity': {'candidate_id': 'unit-probe', 'source_revision': 'unit-source', 'sources': sources}}))
            with self.assertRaisesRegex(ValueError, 'input port differs'):
                prepare.prepare(manifest, root / 'rejected')

    def test_ambiguous_transform_anchor_is_rejected(self):
        with self.assertRaises(ValueError):
            prepare.once('x x', 'x', 'y')
        with self.assertRaises(ValueError):
            prepare.between('start end start', 'start', 'end', 'new')


if __name__ == '__main__':
    unittest.main()

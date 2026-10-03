"""Independent P7 oracle and paired evidence corruption checks."""
import copy
import importlib.util
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('eligible_replay', HERE / 'verify.py')
replay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(replay)


def report():
    data = {'schema': 'mylang-runtime-eligible-v1', 'status': 'eligibility_complete',
            'iterations': 1000000, 'seed': 17, 'rounds': 15, 'warmup_rounds': 3,
            'samples': [], 'warmups': [], 'qualification': [], 'comparisons': []}
    arms = [label + '/' + arm for label in ('before', 'after') for arm in ('my-llvm', 'my-qbe')]
    for arm in arms:
        elapsed = 100 if arm.startswith('before') else 50
        row = {'arm': arm, 'iterations': 1000000, 'seed': 17, 'checksum': 101999913,
               'kernel_ns': elapsed, 'exit_status': 0, 'stderr': '', 'order': arms}
        for field, rounds in (('samples', range(15)), ('warmups', range(-3, 0))):
            data[field].extend({**row, 'round': rnd} for rnd in rounds)
        for count in (1, 2, 31, 32, 65, 127):
            for seed in (1, 17, 999983):
                expected = sum(3 * (seed + index % 31) + 6 for index in range(count))
                data['qualification'].append({**row, 'iterations': count, 'seed': seed, 'checksum': expected})
    for arm in ('my-llvm', 'my-qbe'):
        data['comparisons'].append({'arm': arm, 'after_to_before': .5, 'paired_bootstrap_95_interval': [.5, .5]})
    return data


class EligibleTests(unittest.TestCase):
    def test_oracle_golden_periods_and_bounds(self):
        self.assertEqual(replay.eligible_checksum(1000000, 17), 101999913)
        for count in (1, 2, 30, 31, 32, 65, 127):
            self.assertEqual(replay.eligible_checksum(count, 19), sum(3 * (19 + index % 31) + 6 for index in range(count)))
        for count, seed in ((0, 17), (10000001, 17), (1, 0), (1, 1000001)):
            with self.assertRaises(ValueError):
                replay.eligible_checksum(count, seed)

    def test_known_interval_and_reject_corrupt_evidence(self):
        self.assertEqual(replay.verify_eligible(report()), 4)
        for change in ('sample', 'qualification', 'checksum', 'ratio', 'interval'):
            with self.subTest(change=change):
                data = report()
                if change == 'sample':
                    data['samples'].pop()
                elif change == 'qualification':
                    data['qualification'].append(copy.deepcopy(data['qualification'][0]))
                elif change == 'checksum':
                    data['samples'][0]['checksum'] += 1
                elif change == 'ratio':
                    data['comparisons'][0]['after_to_before'] = .4
                else:
                    data['comparisons'][0]['paired_bootstrap_95_interval'] = [.4, .6]
                with self.assertRaises(ValueError):
                    replay.verify_eligible(data)


if __name__ == '__main__':
    unittest.main()

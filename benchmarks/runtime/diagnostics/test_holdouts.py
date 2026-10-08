"""Reject incomplete or corrupted holdout evidence without invoking guests."""
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('holdout_capture', Path(__file__).with_name('holdouts.py'))
holdouts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(holdouts)


def report():
    document = {'schema': 'mylang-runtime-holdouts-v1', 'status': 'correctness_complete',
                'plans': holdouts.plans(), 'arms': list(holdouts.ARMS), 'checks': []}
    for plan in document['plans']:
        expected = holdouts.checksum(plan['case'], plan['size'], plan['iterations'], plan['seed'])
        for arm in holdouts.ARMS:
            document['checks'].append({**plan, 'arm': arm, 'checksum': expected, 'expected_checksum': expected,
                                       'exit_status': 0, 'clock_protocol_validated': True})
    return document


class HoldoutTests(unittest.TestCase):
    def test_all_cases_and_six_larger_sets(self):
        plans = holdouts.plans()
        self.assertEqual(len(plans), 86)
        self.assertEqual({p['case'] for p in plans if p['label'] == 'larger'}, set(holdouts.LARGER))
        self.assertTrue(all(p['seed'] not in (1, 42, 999983) for p in plans))
        self.assertTrue(all(p['size'] & (p['size'] - 1) for p in plans))
        self.assertEqual(holdouts.verify(report()), 516)

    def test_reject_missing_duplicate_checksum_and_timings(self):
        for change in ('missing', 'duplicate', 'checksum', 'clock', 'timings'):
            with self.subTest(change=change):
                document = report()
                if change == 'missing':
                    document['checks'].pop()
                elif change == 'duplicate':
                    document['checks'].append(copy.deepcopy(document['checks'][0]))
                elif change == 'checksum':
                    document['checks'][0]['checksum'] += 1
                elif change == 'clock':
                    document['checks'][0]['clock_protocol_validated'] = False
                else:
                    document['checks'][0]['kernel_ns'] = 123
                with self.assertRaises(ValueError):
                    holdouts.verify(document)


if __name__ == '__main__':
    unittest.main()

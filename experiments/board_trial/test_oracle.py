"""Freeze development expectations before either board-validator implementation."""
from copy import deepcopy
import json
from pathlib import Path
import unittest

import oracle

CASES = Path(__file__).with_name('cases.json')


class ContractTests(unittest.TestCase):
    def setUp(self):
        self.cases = json.loads(CASES.read_text())
        self.base = deepcopy(self.cases[0]['input'])

    def test_frozen_cases_and_policy_matrix(self):
        self.assertEqual(87, len(self.cases))
        self.assertEqual(36, sum(c['name'].startswith('face_matrix_') for c in self.cases))
        oracle.check(CASES)

    def test_transport_shape_never_truncates_or_coerces(self):
        mutations = [
            lambda d: d.update(version=True),
            lambda d: d.update(extra=0),
            lambda d: d['board'].update(components=[1, 2, 3, 4, 5]),
            lambda d: d['board'].update(nets=[True]),
            lambda d: d['board'].update(nets=[-1]),
            lambda d: d['board'].update(nets=[2**64]),
            lambda d: d['board'].update(outline=[0, 0, 1.0, 1]),
            lambda d: d['board'].update(outline=[0, 0, 2**63, 1]),
            lambda d: d['board'].update(features=d['board']['features'] * 9),
            lambda d: d['board'].update(features=[{'kind': []}]),
            lambda d: d['board']['regions'][0].update(face='inner'),
            lambda d: d['board']['regions'][0].update(blocks=[[]]),
            lambda d: d['board']['regions'][0].update(allow_nets=[10] * 5),
            lambda d: d['board']['features'][0].update(layer='front'),
        ]
        for mutate in mutations:
            document = deepcopy(self.base)
            mutate(document)
            with self.assertRaises(ValueError):
                oracle.evaluate(document)

    def test_bound_endpoints_are_exact_integers(self):
        self.assertTrue(oracle.valid_rect([-oracle.LIMIT, -oracle.LIMIT, 1, 1]))
        self.assertTrue(oracle.valid_rect([oracle.LIMIT - 1, oracle.LIMIT - 1, 1, 1]))
        self.assertFalse(oracle.valid_rect([oracle.LIMIT, 0, 1, 1]))
        self.assertFalse(oracle.valid_rect([0, 0, 0, 1]))

    def test_translation_preserves_valid_verdicts_and_callback_counts(self):
        for case in self.cases:
            if not case['name'].startswith('generated_snapshot_'):
                continue
            document = deepcopy(case['input'])
            board = document['board']
            rectangles = [board['outline'], *(r['rect'] for r in board['regions']),
                          *(f['rect'] for f in board['features'])]
            for rect in rectangles:
                rect[0] += 100_000
                rect[1] -= 200_000
            self.assertEqual(case['expected'], oracle.evaluate(document), case['name'])

    def test_identity_renaming_preserves_membership_and_admission(self):
        for case in self.cases:
            if not case['name'].startswith('face_matrix_'):
                continue
            document = deepcopy(case['input'])
            board = document['board']
            board['components'] = [n + 100 for n in board['components']]
            board['nets'] = [n + 200 for n in board['nets']]
            for region in board['regions']:
                region['allow_nets'] = [n + 200 for n in region['allow_nets']]
            for feature in board['features']:
                if feature['kind'] == 'component':
                    feature['id'] += 100
                else:
                    feature['net'] += 200
            self.assertEqual(case['expected'], oracle.evaluate(document), case['name'])


if __name__ == '__main__':
    unittest.main()

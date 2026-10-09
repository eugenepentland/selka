#!/usr/bin/env python3
"""Ensure frontend qualification never weakens frozen conformance verdicts."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('conformance_ref', ROOT / 'experiments/new-core-s5-20261007/tools/conformance_ref.py')
reference = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reference)


class FrontendReferenceTests(unittest.TestCase):
    def fixture(self):
        return {'one': {'tests': [['one::old', 'failed', 'R_OVERFLOW']]}}

    def supplement(self):
        return {'name_mappings': {'one::old': 'one::new'},
                'files': {'extra': {'tests': [['extra::test', 'passed', '']]}},
                'original_cases_per_mode': 1, 'additional_cases_per_mode': 1}

    def test_mapping_preserves_verdict_and_adds_without_mutating_frozen_data(self):
        frozen = self.fixture()
        before = copy.deepcopy(frozen)
        merged, expected = reference.frontend_entries(frozen, self.supplement())
        self.assertEqual(frozen, before)
        self.assertEqual(merged['one']['tests'], [['one::new', 'failed', 'R_OVERFLOW']])
        self.assertEqual(merged['extra']['tests'], [['extra::test', 'passed', '']])
        self.assertEqual(expected, 2)

    def test_collisions_missing_names_and_overwrites_fail(self):
        for change in ('collision', 'missing', 'overwrite', 'failed_addition', 'count'):
            frozen, supplement = self.fixture(), self.supplement()
            if change == 'collision': frozen['one']['tests'].append(['one::new', 'passed', ''])
            if change == 'missing': supplement['name_mappings']['absent'] = 'invented'
            if change == 'overwrite': supplement['files']['one'] = {'tests': []}
            if change == 'failed_addition': supplement['files']['extra']['tests'][0][1] = 'failed'
            if change == 'count': supplement['additional_cases_per_mode'] = 0
            with self.subTest(change=change), self.assertRaises(ValueError):
                reference.frontend_entries(frozen, supplement)

    def test_both_modes_require_exact_complete_totals(self):
        good = {m: {'match': 2, 'mismatch': 0, 'unsupported': 0} for m in ('debug', 'release')}
        self.assertTrue(reference.frontend_totals(good, 2))
        for field in ('match', 'mismatch', 'unsupported'):
            bad = copy.deepcopy(good)
            bad['release'][field] += 1
            self.assertFalse(reference.frontend_totals(bad, 2))
        self.assertFalse(reference.frontend_totals({'debug': good['debug']}, 2))


if __name__ == '__main__':
    unittest.main()

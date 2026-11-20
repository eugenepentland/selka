#!/usr/bin/env python3
"""Regression checks for application performance qualification failures."""
import unittest
import io
import json
from pathlib import Path
import tarfile
import tempfile

from ownership_applications import baseline_protocol, performance_result


class HistoricalProtocolTests(unittest.TestCase):
    def archive(self, folder, *, count=60, inconsistent=False, invalid=None, measured_rounds=7):
        path = Path(folder) / 'runtime.tar.xz'
        with tarfile.open(path, 'w:xz') as archive:
            for case in range(count):
                for chunk, warmups, rounds in ((0, 3, 0), (1, 0, measured_rounds)):
                    record = dict(spec=dict(cell=f'eda/model-{case}'),
                                  cpu=5 if inconsistent and case == 0 else 4,
                                  warmups=warmups, rounds=rounds)
                    if invalid and case == 0 and chunk == 0:
                        record[invalid[0]] = invalid[1]
                    body = json.dumps(record).encode()
                    member = tarfile.TarInfo(f'runtime/runtime/model-{case}.chunk{chunk}.json')
                    member.size = len(body)
                    archive.addfile(member, io.BytesIO(body))
        return path

    def test_settings_come_from_all_recorded_chunks(self):
        with tempfile.TemporaryDirectory() as folder:
            result = baseline_protocol(self.archive(folder))
        self.assertEqual((result['cpu'], result['warmups'], result['rounds']), (4, 3, 7))

    def test_incomplete_or_inconsistent_protocol_is_rejected(self):
        for options in (dict(count=59), dict(inconsistent=True), dict(measured_rounds=0)):
            with self.subTest(options=options), tempfile.TemporaryDirectory() as folder:
                with self.assertRaises(ValueError):
                    baseline_protocol(self.archive(folder, **options))

    def test_recorded_settings_require_nonnegative_integers(self):
        for setting in ('cpu', 'warmups', 'rounds'):
            for value in (-1, True, 1.5, '8', None):
                with self.subTest(setting=setting, value=value), tempfile.TemporaryDirectory() as folder:
                    with self.assertRaises(ValueError):
                        baseline_protocol(self.archive(folder, invalid=(setting, value)))


class PerformanceQualificationTests(unittest.TestCase):
    def setUp(self):
        self.baseline = {
            'eda-model': {'candidate_wall_seconds': '0.02'},
            'tree-program': {'candidate_wall_seconds': '2.0'},
            'vm-string-equality': {'candidate_wall_seconds': ''},
        }
        self.rows = [
            dict(case='eda-model', mode='default', seconds=0.021, correct=True),
            dict(case='tree-program', mode='default', seconds=2.0, correct=True),
            dict(case='vm-string-equality', mode='default', seconds=3.0, correct=True),
        ]

    def qualify(self, rows=None, modes=None):
        return performance_result(self.rows if rows is None else rows,
                                  modes or ['default'], self.baseline)

    def test_exact_limit_passes_and_historical_censor_is_explicit(self):
        result = self.qualify()
        self.assertTrue(result['passed'])
        self.assertEqual(result['comparable'], 2)
        self.assertEqual(result['historically_censored'], ['vm-string-equality'])

    def test_correct_outputs_cannot_hide_a_slow_median(self):
        self.rows[0]['seconds'] = 0.021000001
        result = self.qualify()
        self.assertFalse(result['passed'])
        self.assertEqual([row['case'] for row in result['slow']], ['eda-model'])

    def test_missing_or_duplicate_case_cannot_shrink_the_denominator(self):
        for rows in (self.rows[1:], self.rows + [self.rows[0]]):
            with self.subTest(rows=rows):
                self.assertFalse(self.qualify(rows)['passed'])

    def test_invalid_or_incorrect_observation_fails_even_when_fast(self):
        for seconds in (None, 0, -1, float('nan'), float('inf'), True):
            with self.subTest(seconds=seconds):
                self.rows[0]['seconds'] = seconds
                self.assertFalse(self.qualify()['passed'])
        self.rows[0].update(seconds=0.001, correct=False)
        self.assertFalse(self.qualify()['passed'])

    def test_every_required_mode_must_be_present(self):
        self.assertFalse(self.qualify(modes=['default', 'zero-rc'])['passed'])

    def test_no_comparable_baseline_never_passes(self):
        self.assertFalse(performance_result([], ['default'], {})['passed'])

    def test_invalid_baseline_cannot_become_a_censor_or_a_pass(self):
        for value in ('nan', 'inf', '0', '-1', 'invalid', None, True, 0, -1, 10**1000):
            with self.subTest(value=value):
                self.baseline['eda-model']['candidate_wall_seconds'] = value
                result = self.qualify()
                self.assertFalse(result['passed'])
                self.assertEqual(result['invalid_baseline'], ['eda-model'])
                self.assertNotIn('eda-model', result['historically_censored'])


if __name__ == '__main__':
    unittest.main()

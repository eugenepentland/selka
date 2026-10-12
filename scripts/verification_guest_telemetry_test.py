#!/usr/bin/env python3
"""Guest inventories cannot fabricate timing or hide malformed reports."""
import json
from pathlib import Path
import tempfile
import unittest
import verification_guest_telemetry as guest
import verification_report as report


def fixture(states=('passed', 'cached', 'skipped', 'failed', 'unsupported')):
    return dict(version='native-tests-v1',
                tests=[dict(name=f'app::test_{index}', status=state, reason='') for index, state in enumerate(states)],
                **{state: states.count(state) for state in guest.STATES})


class GuestTelemetryTests(unittest.TestCase):
    def test_exact_states_counts_property_data_and_unknown_clocks(self):
        data = fixture()
        data['tests'][0]['property'] = dict(counts=dict(passed=1000), campaign=dict(reused=500))
        observed = guest.guest_tests(data, action_id='language', member=2)
        self.assertEqual((observed['selected'], observed['executed'], observed['reused'],
                          observed['skipped'], observed['unsupported'], observed['timed']), (5, 2, 1, 1, 1, 0))
        self.assertEqual(observed['timing_coverage'], 'unknown')
        self.assertEqual(observed['inventory_coverage'], 'complete')
        self.assertTrue(all(row['elapsed_ns'] is None for row in observed['tests']))
        self.assertEqual(observed['tests'][1]['state'], 'reused')
        self.assertEqual(observed['tests'][-1]['state'], 'unsupported')
        self.assertEqual(observed['member_id'], 'language/member/2')

    def test_incomplete_duplicate_and_fake_text_records_stay_unknown(self):
        variants = [dict(fixture(), passed=99), dict(fixture(), version='other'),
                    dict(fixture(), passed=True), dict(fixture(), tests=[])]
        duplicate = fixture(('passed', 'passed'))
        duplicate['tests'][1]['name'] = duplicate['tests'][0]['name']
        variants.append(duplicate)
        setup_failure = fixture(('failed',))
        setup_failure['tests'][0]['name'] = 'tests/app.my'
        variants.append(setup_failure)
        for value in variants:
            self.assertEqual(guest.guest_tests(value, action_id='language', member=0)['status'], 'unknown')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'report'
            self.assertEqual(report.guest_test_timings(path, action_id='language', member=0)['status'], 'unknown')
            path.write_text('passed fake::test\n1 passed, 0 cached, 0 failed, 0 skipped\n')
            self.assertEqual(report.guest_test_timings(path, action_id='language', member=0)['status'], 'unknown')
            path.write_text(json.dumps(fixture())[:-1])
            self.assertEqual(report.guest_test_timings(path, action_id='language', member=0)['status'], 'unknown')
            path.write_text(json.dumps(fixture()))
            self.assertEqual(report.guest_test_timings(path, action_id='language', member=0)['selected'], 5)


if __name__ == '__main__':
    unittest.main()

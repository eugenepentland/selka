import json
import subprocess
import unittest

from ownership_counts import EVENTS, validate


class OwnershipCountsTests(unittest.TestCase):
    def result(self, **changes):
        record = {'version': 1, 'runtime': 'rc-v5-counting', 'saturated': False,
                  **{key: 3 for key in EVENTS}, **changes}
        return subprocess.CompletedProcess([], 0, '17 29\n',
                                           'MYLANG_RC_COUNTS ' + json.dumps(record) + '\n')

    def test_valid_counts_discard_instrumented_time(self):
        result = validate(self.result(), 17)
        self.assertEqual(result, {'checksum': 17, 'events': dict.fromkeys(EVENTS, 3)})

    def test_corrupt_or_incompatible_counters_fail_closed(self):
        for changes in ({'saturated': True}, {'runtime': 'rc-v5'}, {'version': 2},
                        {'extra': 1}, {'retire': -1}, {'retire': True},
                        {'retire': 2**64}, {'retire': 0.5}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                validate(self.result(**changes), 17)

    def test_missing_duplicate_or_guest_diagnostic_is_rejected(self):
        good = self.result()
        for stderr in ('', good.stderr * 2, good.stderr + 'unexpected diagnostic\n'):
            with self.subTest(stderr=stderr), self.assertRaises(ValueError):
                validate(subprocess.CompletedProcess([], 0, good.stdout, stderr), 17)

    def test_wrong_checksum_clock_or_exit_is_rejected(self):
        good = self.result()
        for status, stdout in ((1, good.stdout), (0, '18 29\n'), (0, '17 0\n'), (0, '17 29\nextra')):
            with self.subTest(status=status, stdout=stdout), self.assertRaises(ValueError):
                validate(subprocess.CompletedProcess([], status, stdout, good.stderr), 17)


if __name__ == '__main__':
    unittest.main()

#!/usr/bin/env python3
"""Check saved text parsing and avoid cumulative-percentage double counting."""
import unittest

import profile_summary as summary


class SummaryTests(unittest.TestCase):
    def test_children_are_never_added_to_self(self):
        rows = summary.parse_rows(
            '# Samples: 10 of event cycles:u\n'
            ' 90.00% 2.00% mylang mylang [.] crypto.blake3.compressPre  -  -\n'
            ' 40.00% 1.00% mylang mylang [.] crypto.sha2.round  -  -\n'
            ' 10.00% 0.50% 4 memfd:mylang-planner (deleted) [.] 0x1234  -  -\n')
        groups = summary.self_groups(rows)
        self.assertEqual(groups['blake3_plus_sha2'], 3)
        self.assertEqual(groups['mylang_host_dso'], 3)
        self.assertEqual(groups['unresolved_including_zig'], 0.5)
        self.assertEqual(groups['memfd_planner'], 0.5)
        self.assertEqual(rows[0]['children_pct'], 90)

    def test_preserves_spaces_inside_demangled_symbol(self):
        rows = summary.parse_rows(' 1.00% 1.00% mylang mylang [.] crypto.sha2.Round(.{ 1, 2 },256)  -  -\n')
        self.assertEqual(rows[0]['symbol'], 'crypto.sha2.Round(.{ 1, 2 },256)')

    def test_rejects_multiple_event_denominators(self):
        with self.assertRaisesRegex(ValueError, 'multiple perf events'):
            summary.parse_rows('# Samples: 10 of event cycles\n'
                               ' 1.00% 1.00% mylang mylang [.] first  -  -\n'
                               '# Samples: 10 of event instructions\n'
                               ' 1.00% 1.00% mylang mylang [.] second  -  -\n')

    def test_rejects_malformed_or_empty_report(self):
        with self.assertRaisesRegex(ValueError, 'unrecognized perf row'):
            summary.parse_rows(' 1.00% missing columns\n')
        with self.assertRaisesRegex(ValueError, 'no flat percentage rows'):
            summary.parse_rows('# header only\n')


if __name__ == '__main__':
    unittest.main()

#!/usr/bin/env python3
"""Validate depth attribution and fail-closed current typed dump parsing."""
import unittest
from count_typed import count, parse

HEADER = 'fn probe #0 params=0 ret=bool cabi=false host=false\n'

class WalkerTests(unittest.TestCase):
    def test_range_roles_keep_endpoints_outside_loop(self):
        text = HEADER + '''  range_loop binding=8 id=3
    start:
      binary : bool eq
        local : List[i64] %0
        local : List[i64] %1
    end:
      binary : bool eq
        local : List[i64] %0
        local : List[i64] %1
    setup:
      binary : bool eq
        local : List[i64] %0
        local : List[i64] %1
    loop:
      condition:
        binary : bool eq
          local : List[i64] %0
          local : List[i64] %1
      body:
        loop id=4
          binary : bool eq
            local : List[i64] %0
            local : List[i64] %1
      step:
        binary : bool eq
          local : List[i64] %0
          local : List[i64] %1
'''
        self.assertEqual(count(parse(text))['counts']['list.eq'], [3, 2, 1])

    def test_unknown_range_role_fails_closed(self):
        with self.assertRaisesRegex(ValueError, 'role schema changed'):
            count(parse(HEADER + '  range_loop binding=8 id=3\n    integer : i64 0\n'))

    def test_bad_indentation_and_missing_operand_fail_closed(self):
        with self.assertRaisesRegex(ValueError, 'indentation'):
            parse(HEADER + '   block\n')
        with self.assertRaisesRegex(ValueError, 'two typed operands'):
            count(parse(HEADER + '  ret\n    binary : bool eq\n      integer : i64 1\n'))

    def test_opaque_and_unknown_nominal_stay_explicit(self):
        report = count(parse(HEADER + '''  block
    invoke : i64 ...
    binary : bool eq
      local : mystery::Item %0
      local : mystery::Item %1
'''))
        self.assertEqual(report['uncounted_visible_nodes'],
                         {'equality.unknown_nominal': 1, 'opaque.invoke': 1})
        self.assertIn('hidden_operands', report['uncounted_constructs'])
        self.assertIn('sequence_repetition', report['uncounted_constructs'])

if __name__ == '__main__':
    unittest.main()

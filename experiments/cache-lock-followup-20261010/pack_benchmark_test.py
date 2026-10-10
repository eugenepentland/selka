import unittest

from pack_benchmark import parse_locks


class LockTraceTests(unittest.TestCase):
    def test_blocked_call_uses_return_time_and_ignores_unlocked_read_descriptor(self):
        result = parse_locks('''101 100.000000 flock(3</cache/sequence>, LOCK_EX <unfinished ...>
202 100.100000 close(4</cache/sequence>) = 0 <0.000010>
101 100.200000 <... flock resumed>) = 0 <0.200000>
101 100.600000 close(3</cache/sequence>) = 0 <0.000010>
''')
        self.assertEqual(result['flock_syscall']['count'], 1)
        self.assertAlmostEqual(result['flock_syscall']['sum_s'], 0.2)
        self.assertAlmostEqual(result['held_until_close']['sum_s'], 0.4)

    def test_reused_descriptor_and_failed_lock_do_not_invent_holds(self):
        result = parse_locks('''101 100.000000 flock(3</cache/sequence>, LOCK_EX|LOCK_NB) = -1 EAGAIN (Resource temporarily unavailable) <0.000010>
101 100.100000 close(3</cache/sequence>) = 0 <0.000010>
101 101.000000 flock(3</cache/sequence>, LOCK_EX) = 0 <0.000010>
101 101.100000 close(3</cache/sequence>) = 0 <0.000010>
101 102.000000 flock(3</cache/sequence>, LOCK_EX) = 0 <0.000010>
101 102.100000 close(3</cache/sequence>) = 0 <0.000010>
''')
        self.assertEqual(result['held_until_close']['count'], 2)
        self.assertAlmostEqual(result['held_until_close']['sum_s'], 0.19998)

    def test_incomplete_trace_cannot_claim_completed_occupancy(self):
        with self.assertRaisesRegex(ValueError, 'without observed close'):
            parse_locks('101 100.000000 flock(3</cache/sequence>, LOCK_EX) = 0 <0.000010>')


if __name__ == '__main__':
    unittest.main()

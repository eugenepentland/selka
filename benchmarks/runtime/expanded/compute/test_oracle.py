"""Hand-computed one-pass edges and independently repeated phase checks."""
import unittest
from oracle import CASES, checksum, frame, packet

class OracleTests(unittest.TestCase):
    def test_hand_computed(self):
        expected = dict(integer_math=100, float_math=2197, branch_predictable=127,
                        branch_mixed=209, record_construct=134, record_update=134,
                        call_direct=131, call_indirect=217, option_handle=119,
                        result_propagate=119, binary_search=0, packet_decode=244)
        self.assertEqual({case:checksum(case,2,1,1) for case in CASES}, expected)

    def test_packet_errors(self):
        self.assertEqual([packet(frame(j,1)) for j in range(4)], [143,101,404,303])

    def test_cycle_remainder(self):
        for case in CASES:
            cycle = checksum(case,17,17,42)
            self.assertEqual(checksum(case,17,51,42), cycle*3%1000000007)
            self.assertEqual(checksum(case,17,52,42), (cycle*3+checksum(case,17,1,42))%1000000007)

if __name__ == '__main__': unittest.main()

"""Independent hand arithmetic and period-boundary checks for collection fixtures."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('collections_oracle', Path(__file__).with_name('oracle.py'))
oracle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(oracle)

class OracleTests(unittest.TestCase):
    def test_hand_computed_two_element_fixtures(self):
        self.assertEqual(oracle.checksum('list_scan',2,1,1),15)
        self.assertEqual(oracle.checksum('list_append',2,1,1),29)
        self.assertEqual(oracle.checksum('list_filter',2,1,1),0)
        self.assertEqual(oracle.checksum('dict_lookup',2,1,1),31)
        self.assertEqual(oracle.checksum('set_dedup',2,1,1),1)
        self.assertEqual(oracle.checksum('alloc_short',2,1,1),24)
        self.assertEqual(oracle.checksum('alloc_retained',2,1,1),24)
        self.assertEqual(oracle.checksum('sort_int',2,1,1),29)
        self.assertEqual(oracle.checksum('lox_eval',2,1,1),11)
    def test_lox_loop_call_and_branch_arithmetic(self):
        # total=42 ->133 ->134 ->409; repeated execution starts from43.
        self.assertEqual(oracle.checksum('lox_eval',3,1,42),409)
        self.assertEqual(oracle.checksum('lox_eval',3,2,42),827)
    def test_periodic_scan_against_direct_iteration(self):
        values=[(42+j*13)%1009 for j in range(3)]
        direct=sum(sum((v+b)%1009 for v in values) for b in range(2031))%oracle.MOD
        self.assertEqual(oracle.checksum('list_scan',3,2031,42),direct)

if __name__ == '__main__': unittest.main()

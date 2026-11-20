"""Hand-derived edge answers guard oracle Unicode/quoting/sign semantics."""
import importlib.util
from pathlib import Path
import unittest
spec = importlib.util.spec_from_file_location('expanded_text_oracle', Path(__file__).with_name('oracle.py'))
oracle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(oracle)
class OracleSemantics(unittest.TestCase):
    def test_byte_mask_and_signed_parse(self):
        self.assertEqual(oracle.checksum('bytes_scan',2,1,1),39)
        self.assertEqual(oracle.checksum('int_parse',2,1,1),1000000007-138)
        self.assertEqual(oracle.checksum('int_parse',2,7,1),1000000007-549)
        self.assertEqual(oracle.checksum('int_format',2,1,1),159)
    def test_unicode_search_uses_scalars_and_missing_is_zero(self):
        self.assertEqual(oracle.checksum('string_search',2,1,1),9)
        self.assertEqual(oracle.checksum('string_search',2,1,3),7)
        self.assertEqual(oracle.checksum('string_search',2,1,2),0)
        self.assertEqual(oracle.checksum('string_equal',2,1,1),0)
        self.assertEqual(oracle.checksum('string_equal',2,1,4),1)
    def test_split_retains_empty_and_join_consumes_utf8(self):
        self.assertEqual(oracle.checksum('string_split',2,1,1),1204)
        raw='alpha::café'.encode()
        self.assertEqual(oracle.checksum('string_join',2,1,1),len(raw)+sum(raw))
        # Seed5 begins with an empty field; trailing empty fields also survive.
        self.assertEqual(len(oracle.fixtures('string_split',2,5)),2)
        self.assertEqual(oracle.fixtures('string_split',2,5)[0],'')
    def test_csv_quotes_and_invalid_amount_are_observable(self):
        # Row0 invalid =>101; row1 active north amount20=>60+17+name score.
        raw='naïve,item1'.encode()
        self.assertEqual(oracle.checksum('csv_aggregate',2,1,1),101+60+17+len(raw)+sum(raw))
        self.assertIn('"café,""item""0"',oracle.fixtures('csv_aggregate',2,1))
    def test_word_frequency_squared_and_json_transform(self):
        blue=b'blue';cafe='café'.encode()
        self.assertEqual(oracle.checksum('word_count',2,1,1),4*(len(blue)+sum(blue))+len(cafe)+sum(cafe))
        raw='[{"id":1,"name":"café,\\"item\\"0","amount":2},{"id":2,"name":"naïve,item1","amount":21}]'.encode()
        self.assertEqual(oracle.checksum('json_transform',2,1,1),len(raw)+sum(raw))
if __name__=='__main__': unittest.main()

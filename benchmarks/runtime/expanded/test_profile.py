"""Profiling parser/attribution tests; never invokes perf or runs a guest."""
import unittest
import os
from unittest.mock import patch
from profile import classify, load_rules, parse_script, scale_iterations, validate_guest, guest_environment, RULES_PATH


class ProfileTests(unittest.TestCase):
    def test_addresses_and_unknowns(self):
        rows=parse_script('   00401001 main::decode (/tmp/compute-my-qbe)\n  0x7fa122 [unknown] ([unknown])\n')
        self.assertEqual(rows[0][0],0x401001)
        self.assertEqual(rows[1][0],0x7fa122)
        with self.assertRaises(ValueError): parse_script('no-address main (/tmp/guest)')

    def test_conservative_attribution(self):
        rules=load_rules(RULES_PATH)
        binary='/tmp/text-my-llvm'
        samples=[(1,'myl_native_dictionary_read',binary),(2,'myl_f_1234',binary),(3,'main',binary),(4,'malloc','/usr/lib/libc.so.6'),(5,'malloc','/tmp/unrelated.so')]
        result=classify(samples,binary,rules,{'myl_f_1234':'main::word_count'},min_samples=1)
        self.assertEqual(result['primitive_samples'],2)
        self.assertEqual(result['unclassified_samples'],3)
        self.assertEqual(result['primitive_sample_fraction'],0.4)
        self.assertNotIn('target_reached',result)
        self.assertNotIn('target_fraction',result)
        self.assertFalse(any('coverage' in key or 'covered' in key for key in result))
        named=next(row for row in result['symbol_groups'] if row['symbol']=='myl_f_1234')
        self.assertEqual(named['source_name'],'main::word_count')
        self.assertEqual(named['classification'],'unclassified')

    def test_low_samples(self):
        result=classify([(1,'malloc','libc.so.6')],'/tmp/guest',load_rules(RULES_PATH),{})
        self.assertEqual(result['primitive_sample_fraction'],1)
        self.assertTrue(result['low_sample_count'])
        self.assertNotIn('target_reached',result)
        self.assertNotIn('target_fraction',result)
        self.assertFalse(any('coverage' in key or 'covered' in key for key in result))

    def test_scaling_cap(self):
        count,meta=scale_iterations({'iterations':100},[{'kernel_ns':100000000}],1,500)
        self.assertEqual(count,500)
        self.assertTrue(meta['iteration_cap_limited'])
        self.assertEqual(meta['estimated_kernel_seconds'],0.5)
        with self.assertRaises(ValueError): scale_iterations({'iterations':100},[{'kernel_ns':float('nan')}],1,500)

    def test_runtime_environment(self):
        with patch.dict(os.environ, {'MYLANG_OTHER':'changed', 'MYLANG_MEMORY_LIMIT':'1K', 'GOTOOLCHAIN':'unexpected', 'CGO_CFLAGS':'bad'}):
            environment=guest_environment()
        self.assertFalse(any(key.startswith('MYLANG_') for key in environment))
        self.assertNotIn('CGO_CFLAGS',environment)
        self.assertEqual(environment['GOTOOLCHAIN'],'local')
        self.assertEqual(environment['GOEXPERIMENT'],'')

    def test_strict_guest(self):
        self.assertEqual(validate_guest('42 12\n','',0,42)['kernel_ns'],12)
        for stdout,stderr,status in [('42 0\n','',0),('42 1\nextra\n','',0),('41 1\n','',0),('42 1\n','bad',0),('42 1\n','',1)]:
            with self.subTest(stdout=stdout,stderr=stderr,status=status):
                with self.assertRaises(ValueError): validate_guest(stdout,stderr,status,42)


if __name__=='__main__': unittest.main()

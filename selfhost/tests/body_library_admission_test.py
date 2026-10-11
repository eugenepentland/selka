"""Fail-closed selection and real guest-receipt checks for library admission."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import run_body_library_admission as D


class LibraryAdmissionTests(unittest.TestCase):
    def test_corpus_pins_all_sources_and_ordered_native_errors(self):
        manifest=json.loads((D.FIXTURES/'manifest.json').read_text())
        D.require_manifest(manifest)
        self.assertEqual(len(manifest),16)
        for name,spec in manifest.items():
            self.assertEqual(hashlib.sha256((D.FIXTURES/Path(name).with_suffix('.input')).read_bytes()).hexdigest(),spec['source_sha256'])
            self.assertEqual(bool(spec.get('diagnostics')),spec['status']==1)
        self.assertEqual(manifest['iteration_shadow_error.my']['diagnostics'][0]['code'],'E_SHADOWING')
        self.assertEqual(manifest['comprehension_filter_error.my']['diagnostics'][0]['code'],'E_TYPE')

    def test_missing_profile_and_boolean_verdicts_cannot_count_as_admission(self):
        manifest=json.loads((D.FIXTURES/'manifest.json').read_text())
        for change in ('remove','profile','boolean'):
            bad=json.loads(json.dumps(manifest))
            if change=='remove':bad.pop(next(iter(bad)))
            else:bad[next(iter(bad))]['status']=2 if change=='profile' else False
            with self.assertRaises(RuntimeError):D.require_manifest(bad)

    def test_guest_receipt_requires_all_actual_names_and_uncached_execution(self):
        good={'version':'native-tests-v1','passed':2,'cached':0,'failed':0,'skipped':0,'unsupported':0,
              'tests':[{'name':'m::test_one','status':'passed'},{'name':'m::test_two','status':'passed'}]}
        def result(value):return (0,json.dumps(value).encode(),b'')
        self.assertEqual(len(D.require_tests(result(good),['test_one','test_two'])),2)
        for field,value in (('cached',1),('failed',1),('skipped',1),('unsupported',1)):
            with self.assertRaises(RuntimeError):D.require_tests(result(dict(good,**{field:value})),['test_one','test_two'])
        with self.assertRaises(RuntimeError):D.require_tests(result(good),['test_one','test_other'])
        with self.assertRaises(RuntimeError):D.require_tests((2,b'',b'ComponentProfile'),['test_one','test_two'])

    def test_actual_test_root_inventory_is_nonempty_and_duplicate_safe(self):
        self.assertEqual((len(D.LIBRARIES),len(D.TESTS)),(9,6))
        self.assertTrue(all((D.D.ROOT/'selfhost/components'/name).is_file() for name in D.LIBRARIES+D.TESTS))
        with tempfile.TemporaryDirectory() as temporary:
            path=Path(temporary)/'tests.my'
            path.write_text('func helper() -> bool:\n    return True\n')
            with self.assertRaises(RuntimeError):D.test_selection(path)
            path.write_text('public func test_one() -> bool:\n    return True\n'*2)
            with self.assertRaises(RuntimeError):D.test_selection(path)
            path.write_text('public func test_one() -> bool:\n    return True\n')
            self.assertEqual(D.test_selection(path),['test_one'])


if __name__=='__main__':
    unittest.main()

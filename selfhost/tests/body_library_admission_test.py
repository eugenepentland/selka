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
        self.assertEqual(len(manifest),30)
        for name,spec in manifest.items():
            self.assertEqual(hashlib.sha256((D.FIXTURES/Path(name).with_suffix('.input')).read_bytes()).hexdigest(),spec['source_sha256'])
            self.assertEqual(bool(spec.get('diagnostics')),spec['status']==1)
        self.assertEqual((sum(spec['status']==0 for spec in manifest.values()),sum(spec['status']==1 for spec in manifest.values())),(20,10))
        self.assertEqual(manifest['repeat_wrong_count_error.my']['diagnostics'][0]['code'],'E_TYPE')
        self.assertEqual(manifest['repeat_buffer_error.my']['diagnostics'][0]['code'],'E_TYPE')
        self.assertEqual(manifest['constant_literal_type_error.my']['diagnostics'][0]['code'],'E_TYPE')
        self.assertEqual(manifest['constant_private_import_error.my']['diagnostics'][0]['notes'][0]['role'],'related')
        self.assertEqual(manifest['iteration_shadow_error.my']['diagnostics'][0]['code'],'E_SHADOWING')
        self.assertEqual(manifest['comprehension_filter_error.my']['diagnostics'][0]['code'],'E_TYPE')

    def test_imported_donor_inventory_cannot_reuse_or_omit_changed_source(self):
        from unittest.mock import patch
        import shutil
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            fixtures=root/'fixtures'
            shutil.copytree(D.FIXTURES,fixtures)
            destination=root/'sources'
            destination.mkdir()
            with patch.object(D,'FIXTURES',fixtures):
                D.stage_donors(destination)
                self.assertEqual((destination/'literal_constants.my').read_bytes(),(fixtures/'literal_constants.my').read_bytes())
                with (fixtures/'literal_constants.my').open('a') as stream:stream.write('\n# changed\n')
                with self.assertRaisesRegex(RuntimeError,'donor source changed'):D.stage_donors(destination)
                (fixtures/'untracked.my').write_text('const TEXT: str = "unselected"\n')
                with self.assertRaisesRegex(RuntimeError,'unselected/missing imported donor'):D.stage_donors(destination)

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

    def test_failed_selected_operation_retains_incomplete_raw_evidence(self):
        from types import SimpleNamespace
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as temporary:
            report=Path(temporary)/'report.json'
            args=SimpleNamespace(compiler=Path('/fake'),zig=Path('/zig'),builder=None,
                                 source_root=D.D.ROOT,component_dir=Path('/components'),
                                 native_controls=True,report=report)
            real_digest=D.F.digest
            with patch.object(D.argparse.ArgumentParser,'parse_args',return_value=args), \
                 patch.object(D.F,'digest',side_effect=lambda path: 'compiler-before' if path==args.compiler else real_digest(path)), \
                 patch.object(D.F,'execute',return_value=(2,b'',b'ComponentProfile')):
                with self.assertRaisesRegex(RuntimeError,'native fixture status changed'):D.main()
            evidence=json.loads(report.read_text())
            self.assertFalse(evidence['complete'])
            self.assertEqual(evidence['selected_admission'],'pending')
            self.assertEqual(evidence['records'][0]['stderr'],'ComponentProfile')
            self.assertEqual(evidence['records'][0]['status'],2)
            self.assertNotIn('failed',evidence)
            self.assertIn('--no-cache',evidence['records'][0]['command'])
            self.assertEqual(evidence['compiler_sha256'],'compiler-before')
            args.native_controls=False
            before={'compiler_sha256':'compiler-before','packages':{'body-check':'artifact-before'}}
            with patch.object(D.F,'digest',return_value='compiler-before'), \
                 patch.object(D.D,'packages',return_value={'body-check':'artifact-before'}):
                D.require_deployment(args,before)
            with patch.object(D.F,'digest',return_value='compiler-after'), \
                 patch.object(D.D,'packages',return_value={'body-check':'artifact-before'}):
                with self.assertRaisesRegex(RuntimeError,'deployment changed'):D.require_deployment(args,before)
            with patch.object(D.F,'digest',return_value='compiler-before'), \
                 patch.object(D.D,'packages',return_value={'body-check':'artifact-after'}):
                with self.assertRaisesRegex(RuntimeError,'deployment changed'):D.require_deployment(args,before)

    def test_actual_test_root_inventory_is_nonempty_and_duplicate_safe(self):
        warning={'version':'diagnostic-v1','kind':'diagnostic','diagnostic':{'code':'W_UNUSED_BINDING','severity':'warning','message':'unused','location':{'path':'engine.my','start':{'line':1,'column':1},'end':{'line':1,'column':2},'bytes':{'start':0,'end':1}},'notes':[],'stack':{'frames':[],'omitted':0}}}
        native=(0,b'',json.dumps(warning).encode()+b'\n')
        D.require_library_success((0,b'',b''))
        D.require_library_match(native,native)
        for bad in ((1,b'',native[2]),(0,b'noise',native[2]),(0,b'',b'noise'),(0,b'',b'{}'),(0,b'',b'\n')):
            with self.assertRaises(RuntimeError):D.require_library_success(bad)
        for key,value in (('severity','error'),('code','E_TYPE'),('location',{}),('stack',{})):
            changed=json.loads(json.dumps(warning));changed['diagnostic'][key]=value
            with self.assertRaises(RuntimeError):D.require_library_success((0,b'',json.dumps(changed).encode()))
        for changed in (b'',native[2].replace(b'unused',b'changed')):
            with self.assertRaises(RuntimeError):D.require_library_match(native,(0,b'',changed))
        self.assertEqual((len(D.LIBRARIES),len(D.TESTS)),(9,6))
        self.assertEqual(D.D.BODY_VALUE_LIMIT,2097152)
        self.assertEqual(D.F.SOURCE_LIMIT,1048576)
        env=D.D.environment('component',Path('/components'),Path('/empty'))
        for mode in ('LEXER','PARSER','DECLARATION','TYPE_INTERFACE','TEST_INDEX','CACHE_PLAN'):
            self.assertEqual(env['MYLANG_'+mode+'_MODE'],'reference')
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

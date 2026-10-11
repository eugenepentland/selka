"""Adversarial accounting, freshness, and exact oracle tests for B8 admission."""
import copy
import json
import os
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch
import run_body_dictionary_admission as B


class DictionaryAdmissionTests(unittest.TestCase):
    def test_check_command_never_inherits_unsupported_guest_build_flags(self):
        entry = Path('/private/main.my')
        self.assertEqual(B.check_command(entry), ['check-project', entry, '--no-cache', '--diagnostics=json'])
        self.assertNotIn('--release', B.check_command(entry))
        self.assertNotIn('--verify-facts', B.check_command(entry))

    def test_all_34_sources_24_successes_and_10_diagnostics_are_required(self):
        manifest, inventory = B.selection()
        self.assertEqual(len(manifest), 34)
        self.assertEqual(B.expected_operations(manifest, B.MODES), 246)
        self.assertEqual(B.expected_operations(manifest, ('reference',)), 82)
        for change in ('missing', 'profile', 'extra', 'order'):
            modified = copy.deepcopy(manifest)
            if change == 'missing':
                modified.pop(next(iter(modified)))
            elif change == 'profile':
                modified['option_eager.my']['status'] = 2
            elif change == 'extra':
                modified['unexpected.my'] = {'status': 0}
            else:
                modified = dict(reversed(list(modified.items())))
            with self.assertRaises(RuntimeError):
                B.require_selection(modified, inventory)
        self.assertEqual(manifest['option_mut_call_error.my']['status'], 1)
        self.assertEqual(manifest['dict_private_import_error.my']['diagnostics'][0]['notes'][0]['role'], 'related')

    def test_source_and_donor_hash_changes_fail_before_admission(self):
        with tempfile.TemporaryDirectory() as temporary:
            import shutil
            root = Path(temporary) / 'fixtures'
            shutil.copytree(B.FIXTURES, root)
            with patch.object(B, 'FIXTURES', root):
                (root / 'option_eager.input').write_bytes(b'changed')
                with self.assertRaises(RuntimeError):
                    B.selection()
                shutil.copyfile(Path(__file__).with_name('fixtures') / 'body_dictionary_candidate/option_eager.input', root / 'option_eager.input')
                (root / 'collection_donor.my').write_bytes(b'changed')
                with self.assertRaises(RuntimeError):
                    B.selection()

    def test_native_errors_require_exact_ordered_code_span_message_and_repairs(self):
        manifest, _ = B.selection()
        spec = manifest['option_rebind_error.my']
        expected = spec['diagnostics'][0]
        diagnostic = {'severity': 'error', 'code': expected['code'], 'message': expected['message'],
                      'location': {'bytes': expected['bytes']}, 'notes': [],
                      'fix': {'edits': [{'bytes': e['bytes'], 'text': e['text']} for e in expected['edits']]}}
        diagnostic['notes'] = [{'role': n['role'], 'message': n['message'], 'location': {'bytes': n['bytes']}} for n in expected['notes']]
        record = {'version': 'diagnostic-v1', 'kind': 'diagnostic', 'diagnostic': diagnostic}
        rendered = (json.dumps(record) + '\n').encode()
        B.native_contract((1, b'', rendered), spec)
        for bad in ((2, b'', rendered), (1, b'output', rendered), (1, b'', b'not json'),
                    (1, b'', rendered + rendered), (1, b'', rendered.replace(b'"error"', b'"warning"'))):
            with self.assertRaises(RuntimeError):
                B.native_contract(bad, spec)
        changed = copy.deepcopy(record)
        changed['diagnostic']['location']['bytes']['end'] += 1
        with self.assertRaises(RuntimeError):
            B.native_contract((1, b'', json.dumps(changed).encode()), spec)

    def test_selected_tuple_cannot_drop_or_change_warnings_or_typed_output(self):
        native = (0, b'typed rows', b'warning bytes')
        B.require_match(native, native)
        for selected in ((0, b'typed rows', b''), (0, b'typed rows', b'changed warning'),
                         (0, b'changed typed rows', b'warning bytes'), (2, b'', b'ComponentProfile')):
            with self.assertRaises(RuntimeError):
                B.require_match(native, selected)

    def test_paths_are_absolute_before_private_cwd_and_failure_is_retained(self):
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            fixtures = work / 'fixtures'; fixtures.mkdir()
            source = b'func main() -> int:\n    return 7\n'
            (fixtures / 'one.input').write_bytes(source)
            digest = B.hashlib.sha256(source).hexdigest()
            manifest = {'one.my': {'status': 0, 'source_sha256': digest}}
            inventory = {'donors': {}}
            old = Path.cwd()
            try:
                os.chdir(work)
                args = ['driver', '--compiler', 'host', '--zig', 'zig', '--component-dir', 'packages',
                        '--source-root', '.', '--native-controls', '--native-body-schema', '5', '--report', 'report.json']
                with patch.object(B, 'FIXTURES', fixtures), patch.object(B, 'selection', return_value=(manifest, inventory)), \
                     patch.object(B, 'identity', return_value={'compiler_sha256': 'pinned', 'packages': None}), \
                     patch.object(B.F, 'execute', return_value=(2, b'', b'ComponentProfile')) as execute, \
                     patch('sys.argv', args):
                    with self.assertRaises(RuntimeError):
                        B.main()
                command = execute.call_args.args[0]
                self.assertEqual(command[0], work / 'host')
                self.assertIn('--no-cache', command)
                report = json.loads((work / 'report.json').read_text())
                self.assertFalse(report['complete'])
                self.assertEqual(report['records'][0]['status'], 2)
                self.assertEqual(report['records'][0]['stderr_hex'], b'ComponentProfile'.hex())
                self.assertEqual(report['selected_admission'], 'pending')
            finally:
                os.chdir(old)

    def test_body_schema11_is_strict_and_deployment_drift_fails(self):
        args = SimpleNamespace(compiler=Path('/host'), component_dir=Path('/packages'), native_controls=False)
        with patch.object(B.F, 'digest', return_value='host'), patch.object(B.D, 'packages', return_value={'body-check': 'schema11'}) as packages:
            expected = B.identity(args)
            packages.assert_called_once_with(args.component_dir, body_schema=11)
            B.require_identity(args, expected)
            packages.return_value = {'body-check': 'changed'}
            with self.assertRaises(RuntimeError):
                B.require_identity(args, expected)

    def test_caller_modes_and_wrapper_controls_cannot_contaminate_reference(self):
        with patch.dict(os.environ, {'MYLANG_BODY_CHECK_MODE': 'component', 'MYLANG_PARSER_MODE': 'component',
                                     'BODY_REPLY': '/forged', 'PILOT_TRUSTED': '1'}):
            env = B.D.environment('reference', Path('/packages'), Path('/empty'))
        self.assertEqual(env['MYLANG_BODY_CHECK_MODE'], 'reference')
        for key in ('MYLANG_LEXER_MODE', 'MYLANG_PARSER_MODE', 'MYLANG_DECLARATION_MODE', 'MYLANG_TYPE_INTERFACE_MODE'):
            self.assertEqual(env[key], 'reference')
        self.assertNotIn('BODY_REPLY', env)
        self.assertNotIn('PILOT_TRUSTED', env)
        self.assertEqual(env['MYL_CORE_LEAKCHECK'], '1')


if __name__ == '__main__':
    unittest.main()

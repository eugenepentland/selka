"""Strict numeric phase accounting and native runtime diagnostic contracts."""
import copy
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch
import run_body_numeric_admission as N


class NumericAdmissionTests(unittest.TestCase):
    def test_complete_width_literal_and_runtime_selection_is_required(self):
        manifest, inventory = N.selection()
        self.assertEqual(len(manifest), 40)
        self.assertEqual(N.expected_operations(manifest, N.MODES), 366)
        self.assertEqual(N.expected_operations(manifest, ('reference',)), 122)
        for width in ('i8', 'i16', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64'):
            self.assertEqual(manifest['width_' + width + '.my']['status'], 0)
            self.assertEqual(manifest['error_max_' + width + '.my']['diagnostics'][0]['code'], 'E_INTEGER_RANGE')
        for change in ('missing', 'profile', 'extra', 'order', 'trap', 'parser'):
            altered = copy.deepcopy(manifest)
            changed = copy.deepcopy(inventory)
            if change == 'missing':
                altered.pop(next(iter(altered)))
            elif change == 'profile':
                altered['width_u64.my']['status'] = 2
            elif change == 'extra':
                altered['unselected.my'] = altered['width_u64.my']
            elif change == 'order':
                altered = dict(reversed(list(altered.items())))
            elif change == 'trap':
                altered['trap_narrow_cast.my']['runtime']['trap'] = False
            else:
                changed['parser_magnitude_cases'] = []
            with self.subTest(change=change), self.assertRaises(RuntimeError):
                N.require_selection(altered, changed)

    def test_source_hashes_cannot_be_silently_regenerated(self):
        manifest, _ = N.selection()
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp)
            for source in N.FIXTURES.iterdir():
                if source.is_file():
                    (target / source.name).write_bytes(source.read_bytes())
            (target / 'width_u64.input').write_text('func main() -> int:\n    return 7\n')
            with patch.object(N, 'FIXTURES', target), self.assertRaises(RuntimeError):
                N.selection()
        self.assertTrue(manifest['u64_metadata.my']['source_sha256'])

    def test_numerical_trap_operands_width_stack_and_provenance_are_exact(self):
        manifest, _ = N.selection()
        spec = manifest['trap_checked_overflow.my']
        entry = Path('/private/sources/trap_checked_overflow.my')
        records = copy.deepcopy(spec['runtime']['diagnostics'])
        def paths(value):
            if isinstance(value, list):
                return [paths(child) for child in value]
            if isinstance(value, dict):
                return {key: str(entry) if key == 'path' else paths(child) for key, child in value.items()}
            return value
        records = paths(records)
        def result(rows):
            return (1, b'', b''.join(json.dumps(row).encode() + b'\n' for row in rows))
        N.runtime_contract(result(records), spec, entry)
        for change in ('width', 'operand', 'stack', 'path', 'message', 'output', 'status'):
            altered = copy.deepcopy(records)
            verdict = None
            if change == 'width':
                altered[0]['diagnostic']['trap_detail']['width'] = 32
            elif change == 'operand':
                altered[0]['diagnostic']['trap_detail']['left'] = 0
            elif change == 'stack':
                altered[0]['diagnostic']['stack']['frames'].reverse()
            elif change == 'path':
                altered[0]['diagnostic']['location']['path'] = '/foreign/source.my'
            elif change == 'message':
                altered[0]['diagnostic']['message'] = 'unrelated host failure'
            elif change == 'output':
                verdict = (1, b'7\n', result(altered)[2])
            else:
                verdict = (2, b'', result(altered)[2])
            with self.subTest(change=change), self.assertRaises(RuntimeError):
                N.runtime_contract(verdict or result(altered), spec, entry)

    def test_success_never_accepts_warning_or_profile_or_wrong_runtime_value(self):
        manifest, _ = N.selection()
        spec = manifest['width_u8.my']
        N.runtime_contract((7, b'7\n', b''), spec, Path('/private/width_u8.my'))
        for verdict in ((7, b'7\n', b'warning'), (2, b'', b'ComponentProfile'), (8, b'8\n', b'')):
            with self.assertRaises(RuntimeError):
                N.runtime_contract(verdict, spec, Path('/private/width_u8.my'))
        with self.assertRaises(RuntimeError):
            N.native_contract((0, b'', b'warning'), spec)

    def test_selected_tuple_retains_full_typed_oracle_and_all_diagnostics(self):
        native = (0, b'canonical typed metadata', b'')
        N.require_match(native, native)
        for verdict in ((0, b'changed metadata', b''), (2, b'', b'ComponentProfile'), (0, native[1], b'warning')):
            with self.assertRaises(RuntimeError):
                N.require_match(native, verdict)

    def test_paths_are_absolute_before_workspace_changes(self):
        args = SimpleNamespace(compiler=Path('zig-out/bin/mylang'), zig=Path('zig'), builder=Path('tools/builder'),
                               source_root=Path('.'), component_dir=Path('packages'), report=Path('report.json'))
        N.normalize(args)
        self.assertTrue(all(value.is_absolute() for value in vars(args).values()))

    def test_identity_is_strict_schema_nine_with_explicit_historical_native_profile(self):
        args = SimpleNamespace(compiler=Path('/host'), component_dir=Path('/packages'),
                               native_controls=False, native_body_schema=None)
        with patch.object(N.F, 'digest', return_value='host'), patch.object(N.D, 'packages', return_value={'body-check': 'strict'}) as packages:
            expected = N.identity(args)
            packages.assert_called_once_with(args.component_dir, body_schema=9)
            args.native_controls = True
            args.native_body_schema = 5
            N.identity(args)
            packages.assert_called_with(args.component_dir, body_schema=5)
            with patch.object(N, 'identity', return_value={'changed': True}), self.assertRaises(RuntimeError):
                N.require_identity(args, expected)

    def test_unrelated_or_malformed_runtime_status_one_is_not_a_numeric_trap(self):
        manifest, _ = N.selection()
        spec = manifest['trap_narrow_cast.my']
        for stderr in (b'R_OVERFLOW', b'{}\n', b'{not json}\n', b'{"version":"diagnostic-v1","kind":"message","message":"R_OVERFLOW"}\n'):
            with self.assertRaises(RuntimeError):
                N.runtime_contract((1, b'', stderr), spec, Path('/private/trap_narrow_cast.my'))


if __name__ == '__main__':
    unittest.main()

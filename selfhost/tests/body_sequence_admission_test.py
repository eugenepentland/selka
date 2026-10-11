"""Strict selection and request-binding checks for ordinary sequence proofs."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import run_body_sequence_admission as S
import run_body_sequence_hostile as H


class SequenceAdmissionTests(unittest.TestCase):
    def test_full_selection_and_phase_accounting(self):
        manifest, inventory = S.selection()
        self.assertEqual(S.expected_operations(manifest), 1338)
        self.assertEqual(S.expected_operations(manifest, True), 378)
        self.assertEqual(len(inventory['runtime_trap_cases']), 10)

    def test_missing_extra_profile_reordered_and_dropped_trap_fail(self):
        manifest, inventory = S.selection()
        for change in ('missing', 'extra', 'profile', 'order', 'trap', 'runtime', 'notes', 'width'):
            altered, selected = copy.deepcopy(manifest), copy.deepcopy(inventory)
            if change == 'missing':
                altered.pop('sum_u64.my')
            elif change == 'extra':
                altered['unselected.my'] = altered['sum_u64.my']
            elif change == 'profile':
                altered['sum_u64.my']['status'] = 2
            elif change == 'order':
                altered = dict(reversed(list(altered.items())))
            elif change == 'trap':
                altered['overflow_sum_u64.my']['runtime']['trap'] = False
            elif change == 'runtime':
                altered['sum_u64.my'].pop('runtime')
            elif change == 'notes':
                altered['sorted_cmp_keyword.my']['diagnostics'] = []
            else:
                selected['integer_widths'] = ['int']
            with self.subTest(change=change), self.assertRaises(RuntimeError):
                S.require_selection(altered, selected)

    def test_source_hash_cannot_be_silently_regenerated(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            for source in S.FIXTURES.iterdir():
                if source.is_file():
                    (target / source.name).write_bytes(source.read_bytes())
            (target / 'sum_u64.input').write_bytes(b'func main() -> int:\n    return 7\n')
            with patch.object(S, 'FIXTURES', target), self.assertRaises(RuntimeError):
                S.selection()

    def test_keyless_hostile_inventory_is_exact(self):
        inventory = H.require_inventory()
        self.assertEqual(len(inventory['hostile_names']), 12)
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            source = target / 'main.input'
            source.write_bytes(H.SOURCE.read_bytes())
            changed = dict(inventory, hostile_names=inventory['hostile_names'][:-1])
            (target / 'inventory.json').write_text(json.dumps(changed))
            with patch.object(H, 'SOURCE', source), self.assertRaises(RuntimeError):
                H.require_inventory()

    def test_shadow_warning_is_preserved_without_permitting_extra_diagnostics(self):
        manifest, _ = S.selection()
        spec = manifest['shadow_function.my']
        self.assertEqual([row['code'] for row in spec['warnings']], ['W_UNUSED_BINDING'])
        warning = spec['warnings'][0]
        entry = Path('/private/shadow_function.my')
        row = {'version': 'diagnostic-v1', 'kind': 'diagnostic', 'diagnostic': {
            'code': warning['code'], 'message': warning['message'], 'severity': 'warning',
            'location': {'path': str(entry), 'bytes': warning['bytes']}, 'notes': []}}
        stderr = json.dumps(row).encode() + b'\n'
        S.native_contract((0, b'', stderr), spec)
        S.runtime_contract((7, b'7\n', stderr), spec, entry)
        for altered in (b'', stderr + stderr):
            with self.assertRaises(RuntimeError):
                S.runtime_contract((7, b'7\n', altered), spec, entry)
        row['diagnostic']['severity'] = 'error'
        with self.assertRaises(RuntimeError):
            S.native_contract((0, b'', json.dumps(row).encode()), spec)
        row['diagnostic']['severity'] = 'warning'
        row['diagnostic']['location']['path'] = '/foreign/source.my'
        with self.assertRaises(RuntimeError):
            S.runtime_contract((7, b'7\n', json.dumps(row).encode()), spec, entry)


if __name__ == '__main__':
    unittest.main()

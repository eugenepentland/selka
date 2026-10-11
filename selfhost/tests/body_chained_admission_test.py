"""Closed source inventory and exact contracts; no synthetic installed claim."""
import copy
import unittest
import run_body_chained_admission as C


class Admission(unittest.TestCase):
    def test_complete_inventory_and_import_donor(self):
        manifest, inventory = C.selection()
        self.assertEqual(C.expected_operations(manifest, C.MODES), 219)
        self.assertEqual(set(inventory['donors']), {'comparisons.my'})
        self.assertEqual(sum(s['status'] == 0 for s in manifest.values()), 21)

    def test_profile_cannot_replace_success_or_error(self):
        manifest, inventory = C.selection()
        for name in ('scalar.my', 'error_width.my'):
            changed = copy.deepcopy(manifest)
            changed[name]['status'] = 2
            with self.assertRaises(RuntimeError):
                C.require_selection(changed, inventory)

    def test_missing_case_and_reordered_inventory_are_rejected(self):
        manifest, inventory = C.selection()
        missing = dict(manifest)
        del missing['short_circuit.my']
        with self.assertRaises(RuntimeError):
            C.require_selection(missing, inventory)
        changed = copy.deepcopy(inventory)
        changed['source_cases'].reverse()
        with self.assertRaises(RuntimeError):
            C.require_selection(manifest, changed)

    def test_selected_tuple_must_be_byte_exact(self):
        C.require_match((0, b'', b''), (0, b'', b''))
        for candidate in ((2, b'', b'ComponentProfile'), (0, b'wrong', b''), (0, b'', b'warning')):
            with self.assertRaises(RuntimeError):
                C.require_match((0, b'', b''), candidate)

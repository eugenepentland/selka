import copy
import unittest
import run_body_structural_admission as A
import run_body_structural_hostile as H


class Structural(unittest.TestCase):
    def test_complete_frozen_inventory(self):
        manifest, inventory = A.selection()
        self.assertEqual(A.expected_operations(manifest, A.MODES), 222)
        self.assertEqual(inventory['counts'], A.COUNTS)

    def test_all_original_arrays_preserved(self):
        import run_body_array_controls as O
        manifest, _ = A.selection()
        for name, spec in O.selection().items():
            self.assertEqual(manifest[name], spec)

    def test_incomplete_and_profile_are_refused(self):
        manifest, inventory = A.selection()
        for name, replacement in (('array_alias.my', None), ('array_copy.my', 2)):
            changed = copy.deepcopy(manifest)
            if replacement is None:
                del changed[name]
            else:
                changed[name]['status'] = replacement
            with self.assertRaises(RuntimeError):
                A.require_selection(changed, inventory)

    def test_exact_selected_tuple(self):
        with self.assertRaises(RuntimeError):
            A.require_match((0, b'', b''), (2, b'', b'profile refusal'))

    def test_hostile_inventory(self):
        self.assertEqual(len(H.require_inventory()['hostile_names']), 13)
        with self.assertRaises(RuntimeError):
            H.bound_capture(b'', b'')

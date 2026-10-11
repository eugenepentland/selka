import copy
import unittest
import run_body_generic_admission as A


class GenericAdmission(unittest.TestCase):
    def test_complete_inventory(self):
        manifest, inventory = A.selection()
        self.assertEqual(A.expected_operations(manifest, A.MODES), 120)
        self.assertEqual(inventory['counts'], A.COUNTS)
        for name in ('recursive_reuse.my', 'explicit_before_child.my', 'forwarded_array_length.my',
                     'composite_tuple_signature.my', 'inference_conflict.my', 'unused_template_error.my'):
            self.assertIn(name, manifest)

    def test_missing_profile_and_diagnostic_loss_cannot_qualify(self):
        manifest, inventory = A.selection()
        for change in ('missing', 'profile', 'diagnostic'):
            altered = copy.deepcopy(manifest)
            if change == 'missing': del altered['recursive_reuse.my']
            elif change == 'profile': altered['recursive_reuse.my']['status'] = 2
            else: altered['inference_conflict.my']['diagnostics'] = []
            with self.assertRaises(RuntimeError): A.require_selection(altered, inventory)

    def test_successful_status_cannot_hide_shadow_or_metadata_failure(self):
        for result in ((2, b'', b'profile'), (0, b'changed', b''), (1, b'', b'error')):
            with self.assertRaises(RuntimeError): A.require_match((0, b'', b''), result)


if __name__ == '__main__': unittest.main()

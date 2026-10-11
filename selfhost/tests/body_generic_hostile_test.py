import unittest
import run_body_generic_hostile as H


class GenericHostile(unittest.TestCase):
    def test_closed_instance_authority_attack_inventory(self):
        inventory = H.require_inventory()
        self.assertEqual(len(inventory['hostile_names']), 7)
        self.assertIn('duplicate_instance', inventory['hostile_names'])
        self.assertIn('wrong_parameter_signature', inventory['hostile_names'])
        self.assertIn('wrong_return_signature', inventory['hostile_names'])

    def test_empty_or_unbound_capture_cannot_authorize_mutations(self):
        with self.assertRaises(RuntimeError): H.bound_capture(b'', b'')
        with self.assertRaises(RuntimeError): H.mutations(b'')


if __name__ == '__main__': unittest.main()

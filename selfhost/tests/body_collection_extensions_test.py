"""Guard extension selection and observable source/runtime comparisons."""
import unittest
from pathlib import Path
import run_body_collection_extensions as E


class CollectionExtensionsTest(unittest.TestCase):
    def test_inventory_includes_remaining_collection_routes(self):
        manifest = E.selection()
        self.assertEqual(len(manifest), 10)
        self.assertIn('dictionary_generator_pairs.my', manifest)
        self.assertIn('dictionary_augmentation_nested.my', manifest)
        self.assertIn('option_set_mutation.my', manifest)

    def test_check_command_keeps_build_flags_out_of_check(self):
        self.assertEqual(E.A.check_command(Path('source.my')),
                         ['check-project', Path('source.my'), '--no-cache', '--diagnostics=json'])

    def test_profile_and_diagnostic_are_not_native_success(self):
        for status in (1, 2):
            with self.assertRaises(RuntimeError):
                E.A.native_contract((status, b'', b''), {'status': 0})

    def test_shadow_mismatch_cannot_be_hidden_by_equal_exit_status(self):
        with self.assertRaises(RuntimeError):
            E.A.require_match((0, b'first', b''), (0, b'second', b''))
        with self.assertRaises(RuntimeError):
            E.A.require_match((0, b'', b''), (0, b'', b'warning'))

    def test_runtime_requires_assertions_result_and_clean_stderr(self):
        E.runtime_contract((7, b'7\n', b''))
        for result in ((0, b'7\n', b''), (7, b'', b''), (7, b'7\n', b'leaked')):
            with self.assertRaises(RuntimeError):
                E.runtime_contract(result)


if __name__ == '__main__':
    unittest.main()

"""Filesystem admission cannot lose fixtures, diagnostics or runtime coverage."""
import copy
import unittest
import run_body_filesystem_admission as C


class Admission(unittest.TestCase):
    def test_complete_inventory_and_both_original_file_controls(self):
        manifest, inventory = C.selection()
        self.assertEqual(C.expected_operations(manifest), 372)
        self.assertTrue(manifest['entry_text_profile.my']['runtime'])
        self.assertTrue(manifest['entry_write_profile.my']['runtime'])
        self.assertEqual(inventory['data_files'], {'text.txt': '736576656e21210a'})

    def test_profile_refusal_cannot_replace_an_admitted_case(self):
        manifest, inventory = C.selection()
        for name in ('open_r.my', 'whole_path_free.my'):
            changed = copy.deepcopy(manifest)
            changed[name]['status'] = 2
            with self.assertRaises(RuntimeError):
                C.require_selection(changed, inventory)

    def test_missing_source_or_runtime_trial_is_rejected(self):
        manifest, inventory = C.selection()
        missing = copy.deepcopy(manifest)
        del missing['open_r.my']
        with self.assertRaises(RuntimeError):
            C.require_selection(missing, inventory)
        changed = copy.deepcopy(manifest)
        changed['whole_path_free.my']['runtime'] = False
        with self.assertRaises(RuntimeError):
            C.require_selection(changed, inventory)

    def test_diagnostic_notes_and_repairs_remain_part_of_the_oracle(self):
        diagnostic = {'code': 'E_TEST', 'message': 'problem', 'location': {'bytes': [1, 2]},
                      'notes': [{'role': 'requirement', 'message': 'requirement', 'location': {'bytes': [3, 4]}}],
                      'fix': {'edits': [{'bytes': [1, 2], 'text': 'replacement'}]}}
        import json
        result = (1, b'', (json.dumps({'version': 'diagnostic-v1', 'kind': 'diagnostic',
                                     'diagnostic': {**diagnostic, 'severity': 'error'}}) + '\n').encode())
        spec = {'status': 1, 'diagnostics': [C.D.diagnostic_contract(diagnostic)]}
        C.native_contract(result, spec)
        changed = copy.deepcopy(spec)
        changed['diagnostics'][0]['notes'] = []
        with self.assertRaises(RuntimeError):
            C.native_contract(result, changed)
        changed = copy.deepcopy(spec)
        changed['diagnostics'][0]['edits'] = []
        with self.assertRaises(RuntimeError):
            C.native_contract(result, changed)

    def test_selected_success_must_preserve_all_bytes(self):
        C.require_match((0, b'graph', b''), (0, b'graph', b''))
        for result in ((2, b'', b'ComponentProfile'), (0, b'different', b''), (0, b'graph', b'warning')):
            with self.assertRaises(RuntimeError):
                C.require_match((0, b'graph', b''), result)

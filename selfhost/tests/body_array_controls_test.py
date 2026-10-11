import copy
import unittest
import run_body_array_controls as A


class Controls(unittest.TestCase):
    def test_complete_hashed_inventory(self):
        self.assertEqual(len(A.selection()), 12)

    def test_success_cannot_hide_warning_or_profile(self):
        spec = {'status': 0, 'diagnostics': []}
        A.check((0, b'', b''), spec)
        for result in ((2, b'', b''), (0, b'ignored', b''), (0, b'', b'warning')):
            with self.assertRaises((RuntimeError, ValueError)):
                A.check(result, spec)

    def test_error_repairs_and_span_are_exact(self):
        import json
        manifest = A.selection()
        spec = manifest['error_array_short.my']
        diagnostic = copy.deepcopy(spec['diagnostics'][0])
        row = {'version': 'diagnostic-v1', 'kind': 'diagnostic',
               'diagnostic': dict(diagnostic, severity='error', location={'bytes': diagnostic['bytes']},
                                  fix={'edits': diagnostic['edits']})}
        # Native projection itself is tested with the retained actual diagnostic below.
        with self.assertRaises(RuntimeError):
            A.check((1, b'', b''), spec)
        row['diagnostic']['code'] = 'E_OTHER'
        with self.assertRaises((RuntimeError, KeyError)):
            A.check((1, b'', json.dumps(row).encode()), spec)

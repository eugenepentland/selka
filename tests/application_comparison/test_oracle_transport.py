import json
import unittest
from experiments.application_comparison.oracle_transport import respond


class OracleTransportTests(unittest.TestCase):
    def test_unicode_scalar_values_in_keys_and_values(self):
        for raw in [b'{"cases":["\\ud800"]}', b'{"\\udc00":0}']:
            self.assertEqual(respond(raw, lambda _: {'parsed': True}), {'error': 'invalid-request'})
        self.assertEqual(respond(b'{"cases":["\\ud83d\\ude00"]}', lambda _: {'parsed': True}), {'parsed': True})

    def test_explicit_depth_boundary_and_escaped_string_delimiters(self):
        for depth in (63, 64, 65):
            raw = b'[' * depth + b'0' + b']' * depth
            result = respond(raw, lambda _: {'parsed': True})
            self.assertEqual(result, {'parsed': True} if depth <= 64 else {'error': 'invalid-request'})
        text = '[{' * 100 + '\\"' + ']}' * 100
        self.assertEqual(respond(json.dumps({'text': text}).encode(), lambda obj: obj), {'text': text})
        # Root object and cases array already consume two container levels.
        for nesting in (62, 63):
            raw = b'{"cases":[' + b'[' * nesting + b'0' + b']' * nesting + b']}'
            self.assertEqual(respond(raw, lambda _: {'parsed': True}),
                             {'parsed': True} if nesting == 62 else {'error': 'invalid-request'})


if __name__ == '__main__':
    unittest.main()

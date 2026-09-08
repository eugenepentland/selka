"""Equivalent transport readiness; placeholder application semantics are unscored."""
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / 'experiments/development_velocity/runtime'


class RuntimeTests(unittest.TestCase):
    def run_both(self, payload, expected):
        for language in ('my', 'python'):
            command = ([str(ROOT / 'zig-out/bin/mylang-io'), '--project', str(RUNTIME / language)]
                       if language == 'my' else ['/usr/bin/python3', '-B', str(RUNTIME / language / 'main.py')])
            with self.subTest(language=language, payload=payload[:100]):
                result = subprocess.run(command, input=payload, capture_output=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
                self.assertEqual(json.loads(result.stdout), expected)

    def test_valid_envelopes_and_escaped_text(self):
        self.run_both(b'{"requests":[]}', {'results': []})
        self.run_both(b'{"requests":[{"x":"\\ud83d\\ude00"},null,true,1.0]}', {'results': [{}] * 4})
        self.run_both(json.dumps({'requests': [0] * 64}).encode(), {'results': [{}] * 64})

    def test_transport_errors_do_not_enter_application(self):
        invalid = [b'', b'[]', b'{"requests":null}', b'{"requests":[],"x":0}',
                   b'{"requests":[],"requests":[]}', b'{"requests":[{"x":1,"\\u0078":2}]}',
                   b'{"requests":["\\ud800"]}', b'{"requests":["\xff"]}',
                   b'{"requests":[9223372036854775808]}', b'{"requests":[1e400]}',
                   b'{"requests":[NaN]}', b'{"requests":[]}{}',
                   json.dumps({'requests': [0] * 65}).encode(),
                   b' ' * 1048577]
        for payload in invalid:
            self.run_both(payload, {'error': 'invalid-envelope'})

    def test_depth_boundary(self):
        # Root object and requests array already occupy levels one and two.
        self.run_both(b'{"requests":[' + b'[' * 30 + b'0' + b']' * 30 + b']}', {'results': [{}]})
        self.run_both(b'{"requests":[' + b'[' * 31 + b'0' + b']' * 31 + b']}', {'error': 'invalid-envelope'})


if __name__ == '__main__':
    unittest.main()

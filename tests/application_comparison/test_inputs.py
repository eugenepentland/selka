import base64
import hashlib
from pathlib import Path
import tempfile
import unittest
from experiments.application_comparison.execution import evaluate, freeze_adapter
from experiments.application_comparison.inputs import decode_case, payload, MAX_INPUT_BYTES
from experiments.application_comparison.storage import snapshot


class InputTests(unittest.TestCase):
    def test_case_encoding_is_exclusive_bounded_and_lossless(self):
        raw = b'\xff\x00{"cases":[],"cases":[]}\n'
        encoded = base64.b64encode(raw).decode()
        self.assertEqual(decode_case({'request_base64': encoded, 'expected': 1}), (None, raw, 1))
        self.assertEqual(decode_case({'request': None, 'expected': 2}), (None, None, 2))
        for case in [{'request': 1, 'request_base64': '', 'expected': 1},
                     {'expected': 1}, {'request_base64': 'Zg=', 'expected': 1},
                     {'request_base64': 'Zh==', 'expected': 1},
                     {'request_base64': None, 'expected': 1}]:
            with self.assertRaises(ValueError):
                decode_case(case)
        with self.assertRaises(ValueError):
            payload(None, b'x' * (MAX_INPUT_BYTES + 1))
        with self.assertRaises(ValueError):
            payload({}, b'')
        self.assertNotEqual(payload(None)[1], payload(None, b'')[1])

    def test_isolated_execution_receives_exact_bytes_only_at_run(self):
        raw = b'\xff\x00{"x":1,"x":2}\r\n'
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            original = root / 'original'
            original.mkdir()
            (original / 'main.py').write_text(
                'import json,sys\nprint(json.dumps(list(sys.stdin.buffer.read())))\n')
            source = root / 'source'
            receipt = snapshot(original, source)
            adapter = freeze_adapter('python', {}, [
                {'phase': 'check', 'argv': ['/usr/bin/python3', '-c',
                                          'import sys;assert sys.stdin.buffer.read()==b""']},
                {'phase': 'run', 'argv': ['/usr/bin/python3', '-S', '-B', 'main.py']}])
            result = evaluate(source, receipt, adapter, None, root / 'execution', request_bytes=raw)
            self.assertEqual(result['outcome']['output'], list(raw))
            self.assertEqual(result['request_sha256'], hashlib.sha256(raw).hexdigest())
            self.assertEqual(base64.b64decode(result['input']['base64']), raw)
            self.assertTrue(all(step['isolated'] for step in result['steps']))


if __name__ == '__main__':
    unittest.main()

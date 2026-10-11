"""Fail-closed checks for genuine B7 runtime request generation."""
import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest
import generate_body_entry_requests as G


class RequestsTest(unittest.TestCase):
    def test_protocol_and_correlation(self):
        payload = b'SLKBKI01payload'
        header = b'SLKBCK01'+struct.pack('<IIII', 1, 7, 0, len(payload))+b'nonce123'+hashlib.sha256(payload).digest()
        request = header+payload
        reply = bytearray(request); struct.pack_into('<I', reply, 16, 1)
        G.validate_exchange('body-check', request, bytes(reply), {'protocol': 1, 'schema': 7})
        wrong = bytearray(request); wrong[:8] = b'SLKPRS01'
        with self.assertRaises(RuntimeError):
            G.validate_exchange('body-check', bytes(wrong), bytes(reply), {'protocol': 1, 'schema': 7})
        wrong = bytearray(reply); wrong[24] ^= 1
        with self.assertRaises(RuntimeError):
            G.validate_exchange('body-check', request, bytes(wrong), {'protocol': 1, 'schema': 7})
        with self.assertRaises(RuntimeError):
            G.validate_exchange('body-check', request, bytes(reply), {'protocol': 1, 'schema': 6})

    def test_missing_inventory_is_not_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root/'requests.json').write_text(json.dumps({'schema': 1, 'packages': {}}))
            with self.assertRaises(RuntimeError):
                G.E.request_inventory(root)

    def test_raw_protocol_selection_is_closed(self):
        self.assertEqual(G.replay_flag('test-index'), '--request')
        self.assertEqual(G.replay_flag('cache-plan'), '--request')
        self.assertEqual(G.replay_flag('body-check'), '--exchange')
        with self.assertRaises(RuntimeError):
            G.replay_flag('unknown')

    def test_commands_force_real_execution(self):
        from types import SimpleNamespace
        args = SimpleNamespace(compiler=Path('/host'), zig=Path('/zig'))
        self.assertIn('--no-cache', G.command(args, 'body-check', Path('/main.my')))
        self.assertIn('--force', G.command(args, 'cache-plan', Path('/main.my')))
        self.assertIn('main::test_entry', G.command(args, 'test-index', Path('/main.my')))

    def test_cache_work_is_not_a_test_outcome(self):
        value = {'version': 'native-tests-v1', 'passed': 1, 'failed': 0, 'skipped': 0,
                 'cached': 0, 'unsupported': 0, 'tests': [{'name': 'main::test_entry',
                 'status': 'passed', 'cache': {'nanoseconds': 1}}]}
        native = (0, json.dumps(value).encode(), b'')
        value['tests'][0]['cache'] = {'nanoseconds': 999, 'key': 'different'}
        self.assertTrue(G.baseline_equal('cache-plan', native, (0, json.dumps(value).encode(), b'')))
        value['tests'][0]['status'] = 'failed'
        self.assertFalse(G.baseline_equal('cache-plan', native, (0, json.dumps(value).encode(), b'')))
        value['cached'] = 1
        with self.assertRaises(RuntimeError):
            G.baseline_equal('cache-plan', native, (0, json.dumps(value).encode(), b''))

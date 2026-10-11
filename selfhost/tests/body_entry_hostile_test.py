"""Resource attack inventory and exact host-failure accounting."""
import json
import unittest
from unittest.mock import patch
import run_body_entry_hostile as H


class HostileTest(unittest.TestCase):
    def test_closed_inventory_does_not_attack_valid_flow_restore(self):
        self.assertEqual(len(H.NAMES), 15)
        self.assertEqual(len(set(H.NAMES)), 15)
        self.assertIn('sibling_owner', H.NAMES)
        self.assertIn('missing_scoped_file', H.NAMES)
        self.assertNotIn('initialized', H.NAMES)

    def test_exact_protocol_refusal_excludes_unrelated_host_errors(self):
        message = {'version': 'diagnostic-v1', 'kind': 'message', 'message':
                   'mylang: test-index component frame malformed, oversized, stale, or contains invalid IDs\n'}
        H.J.require_rejection((2, b'', json.dumps(message).encode()))
        for result in ((1, b'', json.dumps(message).encode()), (2, b'output', json.dumps(message).encode()),
                       (2, b'', b'ComponentMissing'), (2, b'', b'{}'), (2, b'', b'not JSON')):
            with self.assertRaises(RuntimeError):
                H.J.require_rejection(result)

    def test_missing_authentic_resource_rows_cannot_be_skipped(self):
        with patch.object(H.D, 'CapturedGraph', side_effect=RuntimeError('capture is not success')):
            with self.assertRaisesRegex(RuntimeError, 'capture is not success'):
                H.mutations(b'not an authentic success')

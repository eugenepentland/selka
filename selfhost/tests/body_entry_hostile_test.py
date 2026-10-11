"""Resource attack inventory and exact host-failure accounting."""
import json
import importlib.util
from pathlib import Path
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

    def test_gate_completion_requires_all_resource_and_source_work(self):
        spec = importlib.util.spec_from_file_location('body_entries_gate', Path(__file__).parents[1]/'test_body_entries.py')
        gate = importlib.util.module_from_spec(spec); spec.loader.exec_module(gate)
        captures = [{'phase': name+phase, 'mode': mode} for name in H.E.ENTRIES
                    for phase, modes in (('-source-check', ('shadow', 'component')),
                                         ('-generation1', ('shadow', 'component')),
                                         ('-generation2', ('component',))) for mode in modes]
        message = json.dumps({'version': 'diagnostic-v1', 'kind': 'message', 'message':
            'mylang: test-index component frame malformed, oversized, stale, or contains invalid IDs\n'}).encode().hex()
        report = {'complete': True, 'selected_admission': 'passed', 'operations': 349,
                  'expected_operations': 349, 'cases': 24, 'generations': [{}, {}],
                  'captures': captures, 'resource_forged': [{'name': name, 'status': 2,
                  'stdout_hex': '', 'stderr_hex': message} for name in H.NAMES], 'failed': 0, 'skipped': 0}
        gate.require_complete(report)
        report['resource_forged'].pop()
        with self.assertRaisesRegex(RuntimeError, 'resource attack selection'):
            gate.require_complete(report)
        report['operations'] = 348
        with self.assertRaisesRegex(RuntimeError, 'source-operation'):
            gate.require_complete(report)

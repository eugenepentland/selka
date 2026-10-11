import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import test_body_dictionaries as G


def reports():
    manifest, _ = G.A.selection()
    source = dict(complete=True, selected_admission='passed', body_schema=8, modes=list(G.A.MODES),
                  operations=246, expected_operations=246, failed=0, skipped=0, records=[])
    for name, spec in manifest.items():
        for mode in G.A.MODES:
            for phase in (('check', 'typed', 'runtime') if spec['status'] == 0 else ('check',)):
                source['records'].append(dict(name=name, mode=mode, phase=phase))
    import json
    error = json.dumps({'version': 'diagnostic-v1', 'kind': 'message',
                        'message': 'mylang: test-index component frame malformed, oversized, stale, or contains invalid IDs\n'}).encode().hex()
    hostile = dict(complete=True, selected_admission='passed', schema=8, hostile=27, failed=0,
                   skipped=0, records=[dict(name=n, status=2, stdout_hex='', stderr_hex=error) for n in G.H.NAMES])
    return source, hostile


class GateTests(unittest.TestCase):
    def test_exact_inventory(self):
        G.require_complete(*reports())

    def test_absent_duplicate_or_skipped_source_cannot_qualify(self):
        for mutation in ('missing', 'duplicate', 'skipped', 'schema'):
            source, hostile = reports()
            if mutation == 'missing': source['records'].pop()
            if mutation == 'duplicate': source['records'][-1] = source['records'][0]
            if mutation == 'skipped': source['skipped'] = 1
            if mutation == 'schema': source['body_schema'] = 7
            with self.assertRaises(RuntimeError): G.require_complete(source, hostile)

    def test_absent_duplicate_or_unrelated_host_failure_cannot_qualify(self):
        for mutation in ('missing', 'duplicate', 'status', 'stdout'):
            source, hostile = reports()
            if mutation == 'missing': hostile['records'].pop()
            if mutation == 'duplicate': hostile['records'][-1] = hostile['records'][0]
            if mutation == 'status': hostile['records'][0]['status'] = 1
            if mutation == 'stdout': hostile['records'][0]['stdout_hex'] = '78'
            with self.assertRaises(RuntimeError): G.require_complete(source, hostile)


if __name__ == '__main__': unittest.main()

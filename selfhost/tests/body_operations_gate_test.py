import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import test_body_operations as G


def source_report(name, release=False):
    manifest, expected = G.expected(name)
    records = []
    for source, mode, phase in sorted(expected):
        optimized = phase == 'runtime-release' if name == 'filesystem' else release
        records.append(dict(name=source, mode=mode, phase=phase,
            source_sha256=manifest[source]['source_sha256'],
            command=['compiler', 'run-project', source] + (['--release', '--verify-facts'] if optimized else [])))
    return dict(complete=True, selected_admission='passed', body_schema=G.D.SCHEMA, failed=0, skipped=0,
                operations=len(expected), expected_operations=len(expected), records=records,
                checks_only=False, lane='release' if release else 'normal')


def refusal():
    return json.dumps({'version': 'diagnostic-v1', 'kind': 'message',
        'message': 'mylang: test-index component frame malformed, oversized, stale, or contains invalid IDs\n'}).encode().hex()


class OperationsGateTests(unittest.TestCase):
    def test_complete_selections_and_both_runtime_modes(self):
        self.assertEqual({name: len(G.expected(name)[1]) for name in ('filesystem', 'sequence')},
                         {'filesystem': 372, 'sequence': 1338})
        for name in ('filesystem', 'sequence'):
            for release in (False, True):
                G.require_source(name, source_report(name, release), release)

    def test_missing_duplicate_wrong_schema_or_flags_cannot_qualify(self):
        for name in ('filesystem', 'sequence'):
            for change in ('missing', 'duplicate', 'schema', 'source', 'flags', 'skipped'):
                report = source_report(name)
                if change == 'missing': report['records'].pop()
                if change == 'duplicate': report['records'][-1] = copy.deepcopy(report['records'][0])
                if change == 'schema': report['body_schema'] -= 1
                if change == 'source': report['records'][0]['source_sha256'] = '0' * 64
                if change == 'skipped': report['skipped'] = 1
                if change == 'flags':
                    row = next(r for r in report['records'] if r['phase'] in ('runtime', 'runtime-normal'))
                    row['command'].extend(['--release', '--verify-facts'])
                with self.assertRaises(RuntimeError): G.require_source(name, report)

    def test_hostile_counts_cannot_replace_named_protocol_rejections(self):
        for module, field in [(G.H, 'operations'), (G.G, 'hostile')]:
            report = dict(complete=True, schema=G.D.SCHEMA, failed=0, skipped=0,
                          records=[dict(name=n, status=2, stdout_hex='', stderr_hex=refusal()) for n in module.NAMES])
            report[field] = len(module.NAMES)
            G.require_hostile(report, module, field)
            for change in ('duplicate', 'status', 'message'):
                changed = copy.deepcopy(report)
                if change == 'duplicate': changed['records'][-1] = copy.deepcopy(changed['records'][0])
                if change == 'status': changed['records'][0]['status'] = 1
                if change == 'message': changed['records'][0]['stderr_hex'] = b'ComponentProfile'.hex()
                with self.assertRaises(RuntimeError): G.require_hostile(changed, module, field)

    def test_filesystem_replays_and_both_mutation_modes_are_required(self):
        captures, records = [], []
        for source in G.F.H.SOURCES:
            names = ['mutation_' + str(i) for i in range(G.F.H.COUNTS[source])]
            captures.append(dict(name=source, mutations=names))
            for name in ['authentic', *names]:
                for mode in G.F.H.MODES:
                    records.append(dict(capture=source, name=name, mode=mode,
                        status=0 if name == 'authentic' else 2, stdout_hex='',
                        stderr_hex='' if name == 'authentic' else refusal()))
        report = dict(hostile_complete=True, hostile_expected=G.F.H.EXPECTED,
                      hostile_captures=captures, hostile_records=records)
        G.require_filesystem_hostile(report)
        for change in ('missing', 'duplicate', 'authentic', 'mutation'):
            altered = copy.deepcopy(report)
            if change == 'missing': altered['hostile_records'].pop()
            if change == 'duplicate': altered['hostile_records'][-1] = copy.deepcopy(altered['hostile_records'][0])
            if change == 'authentic': altered['hostile_records'][0]['status'] = 2
            if change == 'mutation': altered['hostile_records'][2]['status'] = 0
            with self.assertRaises(RuntimeError): G.require_filesystem_hostile(altered)


if __name__ == '__main__':
    unittest.main()

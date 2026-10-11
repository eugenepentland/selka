import copy
import json
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import test_body_closure as G


def source_report(name, release=True):
    manifest, selected = G.expected(name)
    report = dict(complete=True, selected_admission='passed', body_schema=G.D.SCHEMA,
                  failed=0, skipped=0, operations=len(selected), records=[], native_controls=False,
                  modes=list(G.LANES[name].MODES), release_facts_leaks=release,
                  runtime_mode='release' if release else 'normal')
    for source, mode, phase in sorted(selected):
        status, stdout = 0, b'typed oracle\n'
        if phase == 'check':
            status, stdout = manifest[source]['status'], b''
        elif phase == 'runtime':
            status = 8 if name == 'constants' and source == 'source_while.my' else 7
            stdout = (str(status) + '\n').encode()
        report['records'].append(dict(name=source, mode=mode, phase=phase, status=status,
            stdout_hex=stdout.hex(), stderr_hex='', source_sha256=manifest[source]['source_sha256']))
    return report


def hostile_report():
    error = json.dumps({'version': 'diagnostic-v1', 'kind': 'message',
        'message': 'mylang: test-index component frame malformed, oversized, stale, or contains invalid IDs\n'}).encode().hex()
    return dict(complete=True, selected_admission='passed', schema=G.H.SCHEMA, hostile=len(G.H.NAMES),
        failed=0, skipped=0, records=[dict(name=name, status=2, stdout_hex='', stderr_hex=error)
                                    for name in G.H.NAMES])


class ClosureGateTests(unittest.TestCase):
    def test_closed_operation_counts(self):
        self.assertEqual({name: len(G.expected(name)[1]) for name in G.LANES},
                         {'constants': 1422, 'structural': 222, 'iteration': 228, 'chained': 219})
        for name in G.LANES:
            G.require_source(name, source_report(name), True)
        G.require_source('constants', source_report('constants', False), False)
        G.require_hostile(hostile_report())

    def test_missing_duplicate_and_extra_work_are_rejected(self):
        for name in G.LANES:
            for mutation in ('missing', 'duplicate', 'extra'):
                report = source_report(name)
                if mutation == 'missing': report['records'].pop()
                if mutation == 'duplicate': report['records'][-1] = copy.deepcopy(report['records'][0])
                if mutation == 'extra': report['records'].append(copy.deepcopy(report['records'][0]))
                with self.assertRaises(RuntimeError): G.require_source(name, report, True)

    def test_incomplete_failed_skipped_native_only_and_old_schema_are_rejected(self):
        for name in G.LANES:
            for field, value in [('complete', False), ('failed', 1), ('skipped', 1),
                                 ('native_controls', True), ('body_schema', G.D.SCHEMA - 1),
                                 ('selected_admission', 'pending'), ('operations', 0)]:
                report = source_report(name); report[field] = value
                with self.assertRaises(RuntimeError): G.require_source(name, report, True)

    def test_wrong_guest_mode_and_source_identity_are_rejected(self):
        for name in G.LANES:
            report = source_report(name, False)
            with self.assertRaises(RuntimeError): G.require_source(name, report, True)
            report = source_report(name); report['records'][0]['source_sha256'] = '0' * 64
            with self.assertRaises(RuntimeError): G.require_source(name, report, True)

    def test_matching_counters_cannot_hide_different_transcripts(self):
        for name in G.LANES:
            for field, value in [('status', 2), ('stdout_hex', '78'), ('stderr_hex', '78')]:
                report = source_report(name); report['records'][0][field] = value
                with self.assertRaises(RuntimeError): G.require_source(name, report, True)

    def test_hostile_inventory_and_exact_protocol_refusal_are_required(self):
        for mutation in ('missing', 'duplicate', 'status', 'stdout', 'stderr', 'skipped'):
            report = hostile_report()
            if mutation == 'missing': report['records'].pop()
            if mutation == 'duplicate': report['records'][-1] = copy.deepcopy(report['records'][0])
            if mutation == 'status': report['records'][0]['status'] = 1
            if mutation == 'stdout': report['records'][0]['stdout_hex'] = '78'
            if mutation == 'stderr': report['records'][0]['stderr_hex'] = '78'
            if mutation == 'skipped': report['skipped'] = 1
            with self.assertRaises(RuntimeError): G.require_hostile(report)


if __name__ == '__main__':
    unittest.main()

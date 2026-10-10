#!/usr/bin/env python3
"""Retain compact results after both qualification drivers complete successfully."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import statistics


def read(path):
    return json.loads(path.read_text())


def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def spread(values):
    return dict(min=min(values), median=statistics.median(values), max=max(values))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--raw', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    pack_path = args.raw / 'pack-matrix/results.json'
    trace_path = args.raw / 'pack-matrix/lock-diagnostics.json'
    admission_path = args.raw / 'pack-admission/results.json'
    matrix_path = args.raw / 'verification-matrix/results.json'
    packed, traces, admission, matrix = map(read, [pack_path, trace_path, admission_path, matrix_path])
    samples = packed['results']
    if len(samples) != len(packed['plan']['cases']) or len(samples) != 24:
        raise ValueError('incomplete packed-store experiment')
    if any(row['exit'] != 0 or not row['verified'] for row in samples):
        raise ValueError('unverified packed-store sample')
    if not matrix['provenance'].get('completed') or len(matrix['runs']) != 8:
        raise ValueError('incomplete live verification matrix')
    grouped = []
    for packs in sorted({row['packs'] for row in samples}):
        for mode in ('refresh', 'contend'):
            arms = {}
            for arm in ('baseline', 'candidate'):
                rows = [row for row in samples if (row['packs'], row['mode'], row['arm']) == (packs, mode, arm)]
                if len(rows) != 3:
                    raise ValueError('expected three rounds per arm')
                arms[arm] = {name: spread([row[name] / divisor for row in rows]) for name, divisor in
                             [('work_ns', 1e9), ('process_wall_s', 1), ('rss_kib', 1), ('user_s', 1), ('system_s', 1)]}
                arms[arm]['work_s'] = arms[arm].pop('work_ns')
            grouped.append(dict(packs=packs, mode=mode, arms=arms,
                                work_reduction_percent=100 * (1 - arms['candidate']['work_s']['median'] /
                                                               arms['baseline']['work_s']['median'])))
    runs = []
    for row in matrix['runs']:
        report = row['report']
        failed = row['name'] == 'added-test-failing'
        if (row['exit_status'] == 0) == failed or bool(report['success']) == failed:
            raise ValueError('unexpected live verification status')
        executed = sorted(item['id'] for item in report['actions'] if item['state'] == 'execute')
        if row['name'] != 'cold-force' and executed != row['expected_executed_cacheable']:
            raise ValueError('unexpected invalidation set')
        if failed and not row['receipts_equal']:
            raise ValueError('failure changed success receipts')
        runs.append({name: row[name] for name in ('name', 'exit_status', 'resources', 'log_sha256',
                    'time_sha256', 'receipts_equal', 'unittest_counts')} |
                    dict(states=dict(Counter(item['state'] for item in report['actions'])),
                         executed=executed, admissions=report['admissions'], timings=report['timings'],
                         build_observed_held_s=report['build_admitted_seconds'],
                         gate_observed_held_s=report['gate_admitted_seconds'],
                         coordinator_elapsed_s=report['elapsed_seconds'], inputs_stable=report['inputs_stable']))
    frozen = read(args.output / 'qualified-inputs.json')
    root = args.output.resolve().parents[1]
    changed = [name for name, expected in frozen['qualified_files'].items() if digest(root / name) != expected]
    if changed:
        raise ValueError('qualification inputs changed: ' + repr(changed))
    full_log = (args.raw / 'verification-matrix/cold-force.log').read_text(errors='replace')
    native = [json.loads(value) for value in re.findall(r'guardian/test: RESULT (.*)', full_log)]
    gate = dict(build_summaries=re.findall(r'^Build Summary:.*$', full_log, re.M),
                native_results=native, native_passed=sum(row['passed'] for row in native),
                native_failed=sum(row['failed'] for row in native),
                python_test_counts=[int(value) for value in re.findall(r'Ran (\d+) tests? in', full_log)])
    result = dict(method='Three-round packed-store microbenchmark plus one live qualification edit matrix. '
                  'Trace timings are intrusive diagnostics; live matrix is operational qualification, not a paired speedup. '
                  'RSS is maximum individual process RSS, not simultaneous process-tree RSS. '
                  'Queue waiting is distinct from observed lock occupancy.',
                  packed_store=grouped, packed_samples=samples, pack_admission=admission,
                  lock_diagnostics=traces, verification_provenance=matrix['provenance'], verification=runs,
                  frozen_inputs_match=True, full_gate=gate,
                  raw_hashes={str(path): digest(path) for path in (pack_path, trace_path, admission_path, matrix_path)})
    destination = args.output / 'qualification-summary.json'
    destination.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(destination)


if __name__ == '__main__':
    main()

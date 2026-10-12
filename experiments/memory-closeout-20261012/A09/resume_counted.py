#!/usr/bin/env python3
"""Resume completed source groups using the unchanged counted helper and bounded leases."""
import argparse
import json
import os
from pathlib import Path
import time

import counted_inputs
import measure


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument('--zig', type=lambda p: Path(p).resolve(), required=True)
    args = parser.parse_args()
    if os.environ.get('MYLANG_ADMISSION_KIND'):
        parser.error('this harness owns admission')
    path = args.output / 'results.json'
    report = json.loads(path.read_text())
    if report.get('passed') or 'continuation' in report:
        parser.error('existing complete or resumed evidence is immutable')
    assert measure.digest(counted_inputs.__file__) == report['harness_sha256']
    assert measure.digest(args.zig) == report['zig_sha256']
    args.compiler = Path(report['compiler'])
    args.ownership = report['ownership']
    assert measure.digest(args.compiler) == report['compiler_sha256']
    groups = {}
    for manifest, expected in report['input_builds'].items():
        assert measure.digest(manifest) == expected
        for case in json.loads(Path(manifest).read_text())['cases']:
            assert measure.digest(case['binary']) == case['binary_sha256']
            assert measure.source_inputs(Path(case['source'])) == case['source_inputs_sha256']
            groups.setdefault(case['source'], []).append(case)
    all_groups = list(groups.values())
    for index, old in enumerate(report['groups']):
        assert [case['id'] for case in old['cases']] == [case['id'] for case in all_groups[index]]
    pending = all_groups[len(report['groups']):]
    assert pending
    # A canceled unadmitted lease has no partial source directory. Refuse a
    # partial native action rather than overwrite or infer it completed.
    assert not any((args.output / cases[0]['id']).exists() for cases in pending)
    snapshot = args.output / 'before-continuation.json'
    with snapshot.open('x') as output:
        output.write(path.read_text())
    report['continuation'] = {'previous_results_sha256': measure.digest(snapshot),
                              'harness_sha256': measure.digest(__file__),
                              'unchanged_group_helper_sha256': measure.digest(counted_inputs.__file__),
                              'admission_leases': []}
    census = counted_inputs.module('a09_resume_census', 'experiments/memory-closeout-20261012/A03/census.py')
    audit = counted_inputs.module('a09_resume_audit', 'experiments/zero-rc-20261011/audit.py')
    admission = counted_inputs.module('a09_resume_admission', 'scripts/build_admission.py')
    while pending:
        waiting = time.monotonic_ns()
        with admission.admission('build'):
            admitted = time.monotonic_ns()
            count = 0
            while pending:
                started = time.monotonic_ns()
                result = counted_inputs.group(args, pending.pop(0), census, audit)
                result['admitted_work_ns'] = time.monotonic_ns() - started
                result['queue_wait_ns'] = admitted - waiting if count == 0 else 0
                report['groups'].append(result)
                count += 1
                measure.save(path, report)
                if count == 4 or time.monotonic_ns() - admitted >= 30_000_000_000:
                    break
            lease = {'groups': count, 'queue_wait_ns': admitted - waiting,
                     'admitted_work_ns': time.monotonic_ns() - admitted}
        report['continuation']['admission_leases'].append(lease)
        measure.save(path, report)
    report['passed'] = all(item['status'] == 'passed' for item in report['groups'])
    measure.save(path, report)
    if not report['passed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()

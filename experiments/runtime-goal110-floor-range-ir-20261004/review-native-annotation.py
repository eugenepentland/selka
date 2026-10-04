#!/usr/bin/env python3
"""Independently replay actual LLVM/QBE range-annotation process evidence."""
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
TREE = ROOT.parent / 'goal110-floor-result-range-20261004'
REPORT = TREE / '.mylang-cache/goal110-floor-result-range-diagnostic/native-matrix/native-differential.json'
LOW, HIGH, MOD = -(1 << 63), (1 << 63) - 1, 1000000007
HASHES = {}


def sha(path):
    path = Path(path)
    if path not in HASHES:
        HASHES[path] = hashlib.sha256(path.read_bytes()).hexdigest()
    return HASHES[path]


def bound(item):
    assert sha(item['path']) == item['sha256']


def floor(value, divisor):
    return value - divisor * (value // divisor)


def oracle(case):
    kind, value, other, phase = case
    if kind <= 4:
        return floor(value, (1, 2, 3, MOD, HIGH)[kind]), ''
    if kind == 5:
        unsigned = floor(abs(value), 3)
        return (-unsigned if value < 0 else unsigned), ''
    if kind in (6, 7, 12):
        divisor = -3 if kind == 6 else other if kind == 7 else 0
        return (floor(value, divisor), '') if divisor else (None, 'R_DIVISION_BY_ZERO')
    if kind == 13:
        return 0, ''
    if kind == 11:
        updated = value + other
        return (floor(updated, 3), '') if LOW <= updated <= HIGH else (None, 'R_OVERFLOW')
    count = max(other, 0)
    initial = 0 if kind == 8 else value
    if not count:
        return initial, ''
    # After the first remainder, later ±17/23 or 0/1 steps cannot overflow.
    # Closed-form sums independently check the sequential native loops.
    if kind in (8, 9):
        first = int(phase == 0)
        total = (count + 1) // 2 if phase == 0 else count // 2 if phase == 1 else 0
    elif kind == 10:
        first = -17
        negatives = (count + 2) // 3
        total = -17 * negatives + 23 * (count - negatives)
    else:
        assert kind == 14
        first, total = -17, -17 * count
    if not LOW <= initial + first <= HIGH:
        return None, 'R_OVERFLOW'
    return floor(initial + total, MOD), ''


def main():
    report = json.loads(REPORT.read_text())
    assert report['status'] == 'passed'
    assert report['source_revision'] == '0311796e84e192e3ac1e4fd0bb9d5824b55be1e2'
    bound(report['runner'])
    bound(report['fixture'])
    for item in report['tools'].values():
        bound(item)
    for arm, host in report['compiler_receipts'].items():
        bound(host['artifact'])
        receipt = json.loads(Path(host['artifact']['path']).read_text())
        assert receipt == host['receipt'] and receipt['exit_status'] == 0
        assert receipt['status'] == 'complete'
        assert receipt['sources_before'] == receipt['sources_after']
        assert sha(receipt['compiler_path']) == receipt['compiler_sha256']
        for path, digest in receipt['sources_after'].items():
            assert sha(Path(receipt['source_root']) / path) == digest
        assert receipt['compiler_optimize'] == ('Debug' if arm == 'after' else 'ReleaseFast')
    builds = {}
    for build in report['builds']:
        bound(build['binary'])
        bound(build['manifest'])
        assert build['result']['status'] == 0
        meta = json.loads(Path(build['manifest']['path']).read_text())
        assert meta['backend'] == ('qbe' if '-qbe-' in build['config'] else 'llvm')
        if meta['backend'] == 'llvm':
            assert str(meta['optimization']) == '3' and meta['lto'] and not meta['thin_lto']
        builds[build['config'], build['arm']] = build['binary']['path']
    assert len(builds) == 14
    counts, policies = Counter(), Counter()
    for row in report['comparisons']:
        before, after = (row['outcomes'][arm] for arm in ('before', 'after'))
        assert all(before[key] == after[key] for key in ('status', 'stdout', 'stderr'))
        for arm, outcome in row['outcomes'].items():
            assert outcome['command'] == [builds[row['config'], arm], *map(str, row['case'])]
        policies[row['config']] += 1
        if row['oracle'] is None:
            assert after['status'] == 1
            env = row['environment']
            if env.get('MYLANG_MEMORY_LIMIT') == '1':
                expected = 'R_MEMORY_BUDGET: memory budget exhausted\n'
                if row['config'] == 'rc-v5-sites-llvm-accounted0':
                    expected = 'MYLANG_RC_SITES {"version":1,"runtime":"rc-v5-sites","sites":0,"events":0,"calls":0,"shown":0,"report":null}\n' + expected
                assert after['stdout'] == '' and after['stderr'] == expected
                counts['startup_memory'] += 1
            else:
                code = 'R_STEP_LIMIT' if '--max-steps=' in env['MYLANG_OPTIONS'] else 'R_FRAME_LIMIT'
                assert 'error[' + code + ']' in after['stderr'] and '\n  in ' in after['stderr']
                counts[code] += 1
            continue
        value, code = oracle(row['case'])
        if code:
            assert row['oracle'] == {'failure': code}
            assert after['status'] == 1 and after['stdout'] == '41\n'
            assert re.search(r'error\[([^]]+)\]', after['stderr']).group(1) == code
            counts[code] += 1
        else:
            assert after['status'] == 0 and after['stdout'] == f'41\n{value}\n43\n0\n'
            assert row['oracle']['value'] == value
            assert after['stderr'] == '' or 'MYLANG_RC_COUNTS ' in after['stderr']
            counts['success'] += 1
    assert counts == dict(success=2604, R_OVERFLOW=70, R_DIVISION_BY_ZERO=70,
                          startup_memory=7, R_STEP_LIMIT=6, R_FRAME_LIMIT=6)
    assert sum(policies.values()) == report['comparison_count'] == 2763
    result = dict(status='pass', reviewed_utc=datetime.now(timezone.utc).isoformat(),
                  source_revision=report['source_revision'], pairs=2763, executions=5526,
                  counts=dict(counts), policies=dict(policies), live_file_bindings=len(HASHES),
                  report_path=str(REPORT), report_sha256=sha(REPORT), script_sha256=sha(__file__),
                  limitations=['Saved process outcomes and current artifacts; no new executions.',
                               'Host policies differ: G4 ReleaseFast control and pinned Debug candidate, with normal optimized guests.',
                               'No runtime benchmark or goal acceptance claim.'])
    with Path(sys.argv[1]).open('x') as target:
        target.write(json.dumps(result, indent=2) + '\n')
    print('PASS 2763 native pairs, 14 exact guest identities and independent closed-form oracles')


if __name__ == '__main__':
    main()

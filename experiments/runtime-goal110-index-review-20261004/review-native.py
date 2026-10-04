#!/usr/bin/env python3
"""Independently replay the final index-update diagnostic process evidence."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re

TREE = Path('/home/epentland/ai/canopy/mylang-worktrees/goal110-index-forward-20261004')
BASE = TREE / '.mylang-cache/goal110-index-update/static/final-checks'
HASHES = {}


def digest(path):
    path = Path(path)
    if path not in HASHES:
        HASHES[path] = hashlib.sha256(path.read_bytes()).hexdigest()
    return HASHES[path]


def binding(item):
    assert digest(item['path']) == item['sha256']


def oracle(args):
    kind, index, delta = args[0], int(args[1]), int(args[2])
    if kind == 'repeat' and delta <= 0:
        return 18, None
    at = index + 2 if index < 0 else index
    if not 0 <= at < 2:
        return None, 'R_LIST_BOUNDS'
    held = (7, 11)[at]
    if kind.startswith('modulo'):
        if delta == 0:
            return None, 'R_DIVISION_BY_ZERO'
        return (held + 1) % delta + (held * 100 if kind.endswith('shared') else 0), None
    if kind == 'quotient':
        value = (-(1 << 63), 11)[at] // delta
        return (None, 'R_OVERFLOW') if value >= 1 << 63 else (value, None)
    value = held + delta
    if not -(1 << 63) <= value < 1 << 63:
        return None, 'R_OVERFLOW'
    if kind.startswith('checksum'):
        value %= 1000003
        return (29 + value) % 1000000007 + value + (11, 7)[at] + (held * 100 if kind.endswith('shared') else 0), None
    if kind in ('shared', 'alias'):
        value += held * 100
    elif kind == 'callback':
        value = held
    elif kind in ('distinct', 'changed'):
        value = held + 3
    elif kind == 'managed_prefix':
        value += value if at == 0 else 7
    elif kind == 'shared_read':
        value += held + value + (11, 7)[at]
    elif kind == 'repeat':
        total = 0
        value = held
        for step in range(delta):
            value += step + 1
            total += value
        value += total + (11, 7)[at]
    else:
        assert kind in ('unique', 'provenance', 'rebound', 'resized'), kind
    return value, None


def outcome(arm):
    binding(arm['artifact'])
    if 'stdout_path' not in arm:
        return arm['returncode'], arm['stdout'], arm['stderr']
    for stream in ('stdout', 'stderr'):
        assert digest(arm[stream + '_path']) == arm[stream + '_sha256']
    return arm['returncode'], Path(arm['stdout_path']).read_text(), Path(arm['stderr_path']).read_text()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    review_path = BASE / 'review-final-source.json'
    review = json.loads(review_path.read_text())
    assert digest(review_path) == '8af48fb8a1bcddf7b10c2551316a9218e0a452757572d63dcc8471eadcb77162'
    for item in review['source_files']:
        assert digest(TREE / item['path']) == item['sha256']
    for item in review['validation'].values():
        binding(item)
    binding(review['compiler'])
    binding(review['source_binding'])
    summary = json.loads(Path(review['validation']['focused-10-summary.json']['path']).read_text())
    assert [row['result']['passed'] for row in summary] == [22, 15, 17]
    assert all(row['exit'] == 0 and not row['resource_error'] and row['result']['failed'] == 0 for row in summary)
    active = json.loads((BASE / 'active02/active-receipt.json').read_text())
    counts = {'success': 0, 'failure': 0, 'memory_refusal': 0, 'instrumentation': 0}
    for row in active['comparisons']:
        before, after = (outcome(row['arms'][arm]) for arm in ('before', 'after'))
        assert before == after
        if row.get('kind') == 'memory_refusal':
            assert before[0] == 1 and before[1] == '41\n' and 'error[R_MEMORY_BUDGET]' in before[2]
            counts['memory_refusal'] += 1
            continue
        expected, code = oracle(row['args'])
        assert (expected, code) == (row['expected'], row['expected_code'])
        if code:
            assert before[0] == 1 and before[1] == '41\n'
            assert re.search(r'error\[([^]]+)\]', before[2]).group(1) == code
            assert '\n  in ' in before[2]
            counts['failure'] += 1
        else:
            assert before == (expected % 256, f'41\n{expected}\n', '')
            counts['success'] += 1
    instrumentation = json.loads((BASE / 'native-receipt.json').read_text())
    for row in instrumentation['comparisons']:
        before, after = (outcome(row['arms'][arm]) for arm in ('before', 'after'))
        assert before == after
        assert before[0:2] == (90, '41\n1114\n') and 'MYLANG_RC_' in before[2]
        counts['instrumentation'] += 1
    assert counts['success'] + counts['failure'] == 136
    assert counts['memory_refusal'] == 2 and counts['instrumentation'] == 4
    output = {'status': 'pass', 'reviewed_utc': datetime.now(timezone.utc).isoformat(),
              'counts': counts, 'focused_unique_tests': 30, 'source_review_sha256': digest(review_path),
              'live_file_bindings': len(HASHES), 'timing': False,
              'limitations': ['Diagnostic host only; official ReleaseFast build and benchmark timing remain pending.',
                              'Same-policy instrumentation equivalence is distinct from optimization-enabled behavior.'],
              'script_sha256': digest(Path(__file__))}
    with args.output.open('x') as target:
        target.write(json.dumps(output, indent=2) + '\n')
    print('PASS', counts, 'and 30 unique bounded focused tests')


if __name__ == '__main__':
    main()

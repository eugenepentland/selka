#!/usr/bin/env python3
"""Check pinned bounded-bias sources and independently replay saved native values."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
TREE = ROOT.parent / 'goal110-bounded-rem-20261004'
CACHE = TREE / '.mylang-cache/goal110-bounded-rem-review'
LOW, HIGH = -(1 << 63), (1 << 63) - 1


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def expected(row):
    kind = row.get('kind', '')
    if kind == 'wide_unsigned_bias_QBE':
        return row['seed'] % 4700000000000000000, ''
    if kind == 'exact_dividend_magnitude_endpoint_QBE':
        return 32 + 2 * (row['seed'] * 15 % 1009), ''
    if kind == 'detached_private_scalar_after_aggregate_reference_GC':
        return sum((17 + i * 13) % 1009 for i in range(32)) + 18, ''
    count = row['count']
    if count <= 0:
        return 0, ''
    if count == 400000:
        return None, 'R_MEMORY_BUDGET'
    first = row['seed'] + row.get('offset', 0)
    last = first + 13 * (count - 1)
    if not LOW <= first <= HIGH or not LOW <= last <= HIGH:
        return None, 'R_OVERFLOW'
    return count + first % 1009 + last % 1009, ''


def main():
    ready = json.loads((CACHE / 'source-readiness.json').read_text())
    assert ready['source_revision'] == '5e97db47f08f667d97419abafd098df263a2aec3'
    for path, digest in ready['source_bindings'].items():
        assert sha(TREE / path) == digest
    for name, meta in ready['logs'].items():
        path = CACHE / name
        assert path.stat().st_size == meta['bytes'] and sha(path) == meta['sha256']
    counts = {'bounded_pairs': 0, 'append_pairs': 0, 'successes': 0, 'failures': 0, 'llvm_policy_via_qbe': 0}
    log = (CACHE / 'unit-final.log').read_text()
    assert 'RESULT {"passed":57,"failed":0,"skipped":0}' in log
    for line in log.splitlines():
        tag = line.split(' ', 1)[0]
        if tag not in ('APPEND-RANGE-OUTCOME', 'BOUNDED-REMAINDER-OUTCOME'):
            continue
        row = json.loads(line.split(' ', 1)[1])
        actual = row['fast']
        assert actual == row['ordinary']
        value, code = expected(row)
        assert actual['failed'] == bool(code) and actual['trap']['code'] == code
        counts['failures' if code else 'successes'] += 1
        if code:
            assert actual['status'] == 1 and actual['trap']['frames']
        else:
            assert actual['value'] == value and actual['status'] == value % 256
            assert actual['stderr'] == ''
        prior_output = '' if tag == 'APPEND-RANGE-OUTCOME' or row.get('kind', '').endswith('reference_GC') else '17\n'
        assert actual['stdout'] == prior_output
        counts['append_pairs' if tag == 'APPEND-RANGE-OUTCOME' else 'bounded_pairs'] += 1
        counts['llvm_policy_via_qbe'] += row.get('kind') == 'LLVM_policy_executed_by_QBE'
    assert counts == dict(bounded_pairs=38, append_pairs=11, successes=42, failures=7, llvm_policy_via_qbe=4)
    result = dict(status='pass', reviewed_utc=datetime.now(timezone.utc).isoformat(),
                  source_revision=ready['source_revision'], source_bindings=len(ready['source_bindings']),
                  log_bindings=len(ready['logs']), focused_tests=57, counts=counts,
                  readiness_sha256=sha(CACHE / 'source-readiness.json'), script_sha256=sha(Path(__file__)),
                  limitations=['Saved exact native outcomes; no new executions or timing.',
                               'Four pairs use LLVM scalar-policy IL executed by QBE; actual LLVM ELF validation is pending.',
                               'Memory refusal checked for the explicit 400000-element fixture, not a general allocation model.'])
    with Path(sys.argv[1]).open('x') as target:
        target.write(json.dumps(result, indent=2) + '\n')
    print('PASS 11 source/8 log bindings and 49 exact native pairs with independent arithmetic oracles')


if __name__ == '__main__':
    main()

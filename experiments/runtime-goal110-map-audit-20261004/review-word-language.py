#!/usr/bin/env python3
"""Replay typed dictionary language outcomes with an independent state model."""
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
TREE = ROOT.parent / 'goal110-dict-word-integrated-20261004'
REPORT = TREE / '.mylang-cache/goal110-dict-word/language/official-proof-01/report.json'
REVISIONS = {'before': '1a3980631e79bc65f048acd063d7250800f01901',
             'after': 'a2dfdfa994e19ac3c80373a443913c7ecdef23d7'}
HASHES = {}


def sha(path):
    path = Path(path)
    if path not in HASHES:
        HASHES[path] = hashlib.sha256(path.read_bytes()).hexdigest()
    return HASHES[path]


def bound(item):
    assert sha(item['path']) == item['sha256']
    if 'bytes' in item:
        assert Path(item['path']).stat().st_size == item['bytes']


def expected(case):
    operation, key, delta = case
    values = {-1: 7, 0: 11, 1: 13}
    prefix = '41\n'
    if operation in (0, 4) and key not in values:
        return prefix, None, 'R_MISSING_KEY'
    if operation == 0:
        result = values[key]
    elif operation == 1:
        prefix += '43\n'
        result = values.get(key, delta)
    elif operation == 2:
        snapshot = values.copy()
        values[key] = delta
        result = snapshot.get(key, 23) + values[key]
    elif operation == 3:
        values[key] = 17
        result = values[key]
    elif operation == 4:
        result = values.pop(key) + values.get(key, 23)
    elif operation == 5:
        snapshot = values.copy()
        values.update({k: k + 5 for k in range(128)})
        result = snapshot[0] + values[127]
    elif operation == 6:
        if delta == (1 << 63) - 1:
            return prefix, None, 'R_OVERFLOW'
        result = values.get(key, delta + 1)
    elif operation == 7:
        values[key] = values.get(key, 0) + 1
        result = values[key]
    elif operation == 8:
        result = 71
    elif operation == 9:
        result = {0: 29}.get(key, delta)
    elif operation == 10:
        result = 31
    elif operation == 11:
        result = len({1: 'abc'}.get(key, 'defgh'))
    elif operation == 12:
        result = delta
    elif operation == 13:
        captured = values.copy()
        values.clear()
        values[1] = 17
        result = captured.get(key, 19)
    elif operation == 14:
        values.clear()
        values[-1] = delta
        result = values.get(-1, 99) + values.get(0, 3)
    else:
        assert operation == 15
        result = 73
    if not -(1 << 63) <= result < (1 << 63):
        return prefix, None, 'R_OVERFLOW'
    return prefix + str(result) + '\n', result % 256, ''


def main():
    doc = json.loads(REPORT.read_text())
    assert doc['status'] == 'passed' and doc['timing'] is False
    for item in [doc['fixture'], doc['driver'], *doc['tools'].values()]:
        bound(item)
    for side, host in doc['receipts'].items():
        bound(host['artifact'])
        receipt = json.loads(Path(host['artifact']['path']).read_text())
        assert receipt == host['document'] and receipt['source_revision'] == REVISIONS[side]
        assert receipt['exit_status'] == 0 and receipt['status'] == 'complete'
        assert receipt['compiler_optimize'] == 'Debug'
        assert receipt['sources_before'] == receipt['sources_after']
        assert sha(receipt['compiler_path']) == receipt['compiler_sha256']
        for path, digest in receipt['sources_after'].items():
            assert sha(Path(receipt['source_root']) / path) == digest
    for call in doc['invocations']:
        bound(call['executable'])
        assert call['executable'] == call['executable_after']
        assert call['command'][0] == call['executable']['path']
    binaries, emissions = {}, {}
    for row in doc['builds']:
        bound(row['binary'])
        bound(row['sidecar'])
        policy = json.loads(Path(row['sidecar']['path']).read_text())
        assert policy == row['policy']
        assert policy['backend'] == ('qbe' if '-qbe-' in row['config'] else 'llvm')
        if policy['backend'] == 'llvm':
            assert str(policy['optimization']) == '3' and policy['lto'] and not policy['thin_lto']
        binaries[row['config'], row['arm']] = row['binary']['path']
    for row in doc['emissions']:
        bound(row['artifact'])
        text = Path(row['artifact']['path']).read_text()
        count = text.count('call $myl_native_dictionary_read_word(')
        diagnostic = 'counting' in row['config'] or 'sites' in row['config']
        assert count == row['word_read_calls'] == (16 if row['arm'] == 'after' and not diagnostic else 0)
        emissions[row['config'], row['arm']] = text
        if diagnostic and row['arm'] == 'after':
            assert text == emissions[row['config'], 'before']
    assert len(binaries) == len(emissions) == 14
    counts, seen = Counter(), set()
    for row in doc['comparisons']:
        key = row['config'], tuple(row.get('case', [])), row.get('options', '')
        assert key not in seen
        seen.add(key)
        before, after = row['results']['before'], row['results']['after']
        assert all(before[k] == after[k] for k in ('status', 'stdout', 'stderr'))
        case = row.get('case', [0, 0, 0])
        for side, actual in row['results'].items():
            assert actual['command'] == [binaries[row['config'], side], *map(str, case)]
        if 'expected_failure' in row:
            code = 'R_STEP_LIMIT' if '--max-steps=1' in row['options'] else 'R_FRAME_LIMIT'
            assert code == row['expected_failure'] and after['status'] != 0
            assert 'error[' + code + ']' in after['stderr'] and '\n  in ' in after['stderr']
            counts[code] += 1
            continue
        stdout, status, failure = expected(case)
        assert after['stdout'] == stdout
        if failure:
            assert after['status'] == 1 and row['oracle']['failure'] == failure
            assert re.search(r'error\[([^]]+)\]', after['stderr']).group(1) == failure
            assert '\n  in ' in after['stderr']
            counts[failure] += 1
        else:
            assert after['status'] == status == row['oracle']['status']
            assert row['oracle']['stdout'] == stdout
            assert not after['stderr'] or 'MYLANG_RC_COUNTS ' in after['stderr'] or 'MYLANG_RC_SITES ' in after['stderr']
            counts['success'] += 1
    assert len(seen) == doc['comparison_count'] == 368 and doc['execution_count'] == 736
    assert counts['success'] == 294 and counts['R_STEP_LIMIT'] == counts['R_FRAME_LIMIT'] == 2
    assert counts['R_MISSING_KEY'] + counts['R_OVERFLOW'] == 70
    result = dict(status='pass', reviewed_utc=datetime.now(timezone.utc).isoformat(),
                  source_revision=REVISIONS['after'], pairs=len(seen), executions=736,
                  counts=dict(counts), live_bindings=len(HASHES),
                  report_sha256=sha(REPORT), script_sha256=sha(__file__),
                  limitations=['Saved direct native outcomes, no new execution or timing.',
                               'Exact streams check provenance/accounting parity; state model independently checks language results.',
                               'Emission manifests establish selection; actual benchmark machine code is reviewed separately.'])
    with Path(sys.argv[1]).open('x') as output:
        output.write(json.dumps(result, indent=2) + '\n')
    print('PASS 368 native language pairs, 14 builds, 14 emissions and independent state oracles')


if __name__ == '__main__':
    main()

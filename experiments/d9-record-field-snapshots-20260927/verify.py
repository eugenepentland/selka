#!/usr/bin/env python3
"""Verify archived record-field snapshot outputs, identities and RC balances."""
from pathlib import Path
import gzip
import hashlib
import json

root = Path(__file__).resolve().parent

def read(name):
    return json.loads(gzip.decompress((root / (name + '.json.gz')).read_bytes()))

def balanced(counts):
    assert not counts['saturated']
    assert counts['heap_allocate'] == counts['retire']
    assert counts['owner_acquire'] + counts['heap_allocate'] == counts['owner_release']
    assert counts['hold_acquire'] == counts['hold_release']

identity = json.loads((root / 'identity.json').read_text())
for name, digest in identity['artifacts'].items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, name
assert identity['compiler_sha256'] == '4261318ea8a67676786f9488d9ca834e653177ee63c31b4c6fdd79b14475b790'
assert identity['source_patch_sha256'] == hashlib.sha256(gzip.decompress((root / 'source.patch.gz').read_bytes())).hexdigest()
for name, count in [('guests',20), ('controls',16)]:
    data = read(name)
    assert data['compiler_sha256'] == identity['compiler_sha256']
    assert len(data['runs']) == count
    for row in data['runs']:
        assert row['build_exit'] == row['exit'] == 0 and row['stdout'] == row['expected']
        assert row['manifest']['backend'] == row['backend']
        assert row['manifest']['lto'] == (row['backend'] == 'llvm')
        if row['mode'] == 'rc':
            balanced(row['counts'])
    for row in data['runs']:
        if row['mode'] == 'rc' and row['backend'] == 'qbe':
            other = next(x for x in data['runs'] if x['name'] == row['name'] and x['mode'] == 'rc' and x['backend'] == 'llvm')
            assert row['counts'] == other['counts']
before = read('before-heap')
assert before['compiler_sha256'] == identity['prior_compiler_sha256']
assert len(before['runs']) == 4
for row in before['runs']:
    assert row['build_exit'] == row['exit'] == 0
    assert row['manifest']['backend'] == row['backend']
    assert row['stdout'] == ('[12, 14]\n[12, 14]\n' if row['mode'] == 'gc' else '[12]\n[12, 14]\n')
    if row['mode'] == 'rc':
        balanced(row['counts'])
for name, output in [('baseline-arena-minimal', '[12, 14]\n[12, 14]\n'),
                     ('baseline-arena-diagnostic', '11\nFalse\n8\nTrue\n[12, 14]\n[12, 14]\n')]:
    rows = read(name)['runs']
    assert len(rows) == 8
    for row in rows:
        assert row['exit'] == 0 and row['stdout'] == output
        assert row['manifest']['backend'] == row['backend']
        assert row['compiler_sha256'] == identity['prior_compiler_sha256' if row['arm'] == 'before' else 'original_performance_compiler_sha256']
        if row['mode'] == 'rc':
            balanced(json.loads(next(line.removeprefix('MYLANG_RC_COUNTS ') for line in row['stderr'].splitlines() if line.startswith('MYLANG_RC_COUNTS '))))
initial = read('baseline-guests-arena-initial')['runs']
assert len(initial) == 1 and initial[0]['stdout'] == 'True\n' * 5 + 'False\n'
traps = read('traps')
assert len(traps['runs']) == 16
codes = dict(overflow='R_OVERFLOW', budget='R_MEMORY_BUDGET', frames='R_FRAME_LIMIT', steps='R_STEP_LIMIT')
for row in traps['runs']:
    assert row['build_exit'] == 0 and row['exit'] == 1
    assert row['stdout'] == 'before\n' and codes[row['case']] in row['stderr']
    assert row['manifest']['backend'] == row['backend']
    if row['mode'] == 'rc':
        balanced(row['counts'])
old = json.loads((root / 'ownership-before.json').read_text())
new = json.loads((root / 'ownership-after.json').read_text())
assert next(x for x in old['locals'] if x['name']=='saved')['role'] == 'borrowed'
assert next(x for x in new['locals'] if x['name']=='saved')['role'] == 'owned'
assert not next(x for x in old['copies'] if x['site']=='assign')['copy']
assert next(x for x in new['copies'] if x['site']=='assign')['copy']
print('record-field snapshots: native outputs, 188 assertions, 16 traps and RC balances verified')

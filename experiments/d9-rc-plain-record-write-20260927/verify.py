#!/usr/bin/env python3
"""Verify frozen outputs, counters, backend identities and raw instruction receipts."""
from pathlib import Path
import gzip
import hashlib
import json
import statistics

root = Path(__file__).resolve().parent

def read(name):
    return json.loads(gzip.decompress((root / (name + '.gz')).read_bytes()))

def balanced(counts):
    assert not counts['saturated']
    assert counts['heap_allocate'] == counts['retire']
    assert counts['owner_acquire'] + counts['heap_allocate'] == counts['owner_release']
    assert counts['hold_acquire'] == counts['hold_release']

def measured(row):
    line = next(line for line in row['stderr'].splitlines() if ',cpu_core/instructions/u,' in line)
    fields = line.split(',')
    assert int(fields[0]) == row['instructions']
    assert int(fields[3]) == row['event_runtime_ns'] > 0
    assert float(fields[4]) == row['event_running_percent'] == 100.0
    assert row['exit'] == 0 and not row['timeout']

identity = json.loads((root / 'identity.json').read_text())
for name, digest in identity['artifacts'].items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, name
assert identity['compiler_sha256'] == 'ca907dc060c537aa9c527cbedab0494ad04c35828a14266a4a54e0ba6e345d52'
assert identity['source_patch_sha256'] == hashlib.sha256(gzip.decompress((root / 'source.patch.gz').read_bytes())).hexdigest()
guest = read('guests-final.json')
assert len(guest['runs']) == 4
for row in guest['runs']:
    assert row['manifest']['backend'] == row['backend']
    assert row['exit'] == 0 and row['stdout'] == 'True\n' * 5
    if row['mode'] == 'rc':
        balanced(row['counts'])
traps = read('traps.json')
assert len(traps['runs']) == 16
codes = dict(overflow='R_OVERFLOW', budget='R_MEMORY_BUDGET', frames='R_FRAME_LIMIT', steps='R_STEP_LIMIT')
for row in traps['runs']:
    assert row['manifest']['backend'] == row['backend']
    assert row['exit'] == 1 and row['stdout'] == 'before\n' and codes[row['case']] in row['stderr']
    if row['mode'] == 'rc':
        balanced(row['counts'])
steps = read('step-harness.json')
assert len(steps['runs']) == 8
for row in steps['runs']:
    assert row['exit'] == 0 and row['manifest']['backend'] == row['backend']
    boundary = 18 if row['mode'] == 'gc' else 19
    expected = ''.join(f'{limit} 1 {limit} R_STEP_LIMIT {41 if limit < boundary else 42} 91\n' for limit in range(17,21))
    assert row['stdout'] == expected
    counts = [json.loads(line.removeprefix('MYLANG_RC_COUNTS ')) for line in row['stderr'].splitlines() if line.startswith('MYLANG_RC_COUNTS ')]
    assert len(counts) == (4 if row['mode'] == 'rc' else 0)
    for count in counts:
        balanced(count)
codegen = read('codegen.json')
assert [(r['arm'], r['loan_sites'], r['markers']) for r in codegen] == [('before',94,0),('after',58,18)]
for row in codegen:
    text = gzip.decompress((root / f"vm-run-{row['arm']}.il.gz").read_bytes())
    assert hashlib.sha256(text).hexdigest() == row['sha256']
reduced = read('lox.json')
assert len(reduced['builds']) == 8 and len(reduced['runs']) == 32
for row in reduced['builds']:
    assert row['exit'] == 0 and row['manifest']['backend'] == row['backend']
for row in reduced['runs']:
    assert row['exit'] == 0 and not row['timeout']
    assert row['stdout'] == (root / f"expected-n{row['n']}.txt").read_text()
    assert row['script_sha256'] == hashlib.sha256((root / f"binary_trees_n{row['n']}.lox").read_bytes()).hexdigest()
    balanced(row['counts']) if row['counted'] else measured(row)
arena = read('arena-diagnostic.json')
assert len(arena['runs']) == 8
for row in arena['runs']:
    assert row['exit'] == 0 and row['manifest']['backend'] == row['backend']
    assert row['stdout'] == '11\nFalse\n8\nTrue\n[12, 14]\n[12, 14]\n'
    assert row['stdout'] != (root / 'expected-arena-diagnostic.txt').read_text()
    if row['mode'] == 'rc':
        balanced(json.loads(next(line.removeprefix('MYLANG_RC_COUNTS ') for line in row['stderr'].splitlines() if line.startswith('MYLANG_RC_COUNTS '))))
full = read('full.json')
assert len(full['runs']) == 16
assert full['input_sha256'] == hashlib.sha256((root / 'binary_trees_n10.lox').read_bytes()).hexdigest()
for row in full['runs']:
    assert row['exit'] == 0 and not row['timeout']
    assert row['stdout'] == (root / 'expected-n10.txt').read_text()
    balanced(row['counts']) if row['counted'] else measured(row)
for backend in ('qbe','llvm'):
    for data, n in ((reduced,4),(reduced,5),(full,10)):
        rows = [r for r in data['runs'] if r['backend'] == backend and r.get('n',10) == n and not r['counted']]
        before = [r['instructions'] for r in rows if r['arm'] == 'before']
        after = [r['instructions'] for r in rows if r['arm'] == 'after']
        assert len(before) == len(after) == 3
        print(f'{backend} N{n}: {statistics.median(before):,} -> {statistics.median(after):,}; ratio {statistics.median(after)/statistics.median(before):.6f}')
print('Historical defect preserved: eight preexisting arena snapshot failures remain correctness work')
print('PASS: outputs, balanced counters, internal step boundary, codegen and 36 raw instruction receipts')

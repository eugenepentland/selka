#!/usr/bin/env python3
"""Recreate a manual branch-choice static assembly walk; never executes guests."""
from pathlib import Path
import hashlib, json, re

lane = Path(__file__).resolve().parents[2]
work = lane/'.tmp-lox-vm-stack-read-v2-20261003'
v1 = lane/'.tmp-lox-vm-stack-read-20261003/qbe-vm-equal_stack.asm'
v1_match = work/'qbe-v1-values_equal.asm'
v2 = work/'qbe-equal_stack.asm'

def trace(path, decisions):
    code = []
    for line in path.read_text().splitlines():
        m = re.match(r'\s*([0-9a-f]+):\s+(\S+)\s*(.*)', line)
        if m:
            code.append((int(m[1], 16), m[2], m[3]))
    indices = {address: i for i, (address, _, _) in enumerate(code)}
    i, choices, visited, calls, taken = 0, iter(decisions), [], [], []
    while True:
        address, op, argument = code[i]
        visited.append(hex(address))
        if op == 'ret':
            break
        assert op != 'ud2', 'failure path'
        if op == 'call':
            calls.append(argument)
        if op.startswith('j'):
            yes = True if op == 'jmp' else next(choices)
            taken.append({'address': hex(address), 'branch': op, 'taken': yes})
            i = indices[int(argument.split()[0], 16)] if yes else i + 1
        else:
            i += 1
        assert len(visited) < 300
    assert list(choices) == [], 'unused branch decisions'
    return {'count': len(visited), 'instruction_addresses': visited, 'branches': taken, 'calls': calls}

prefix1, prefix2 = [False, False, True, False, True], [False, True, False, True]
body = {'nil': [True, True], 'boolean': [False, True, False, True], 'number': [False, False, True, False, False, True], 'obj': [False, False, False, False, False, False, False, False]}
rows = []
for tag, decisions in body.items():
    a, b, c = trace(v1, prefix1), trace(v1_match, decisions), trace(v2, prefix2 + decisions)
    assert len(a['calls']) == 1 and not b['calls'] and not c['calls']
    rows.append({'same_tag': tag, 'v1_helper': a, 'v1_comparison': b, 'v2_helper': c, 'v1_count': a['count'] + b['count'], 'v2_count': c['count'], 'delta': c['count'] - a['count'] - b['count']})
assert [r['v1_count'] for r in rows] == [51, 63, 72, 71]
assert [r['v2_count'] for r in rows] == [47, 59, 68, 67]
sha = lambda f: hashlib.sha256(f.read_bytes()).hexdigest()
result = {'method': 'Manual branch-choice walk of emitted static assembly; no execution or performance measurement. Choices select nonnegative/in-range top-1/top-2 and same valid tags. Counts exclude unchanged caller; include old nested call and comparison entry/return. Payload outcomes use set instructions and do not branch.', 'files': {str(f): sha(f) for f in [v1, v1_match, v2]}, 'rows': rows, 'limits': ['Static path counts are not dynamic PMU or wall measurements.', 'Both V2 operand copies are included.', 'No exact exhausted native frame/step budget or forged-tag equivalence claim.']}
print(json.dumps(result, indent=2))

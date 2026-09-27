#!/usr/bin/env python3
"""Verify immutable receipts; --live additionally hashes original artifacts."""
from pathlib import Path
import gzip, hashlib, json, statistics, sys
ROOT = Path(__file__).resolve().parent
sha = lambda value: hashlib.sha256(value).hexdigest()
def bits(name): return gzip.decompress((ROOT / (name + '.gz')).read_bytes())
def read(name): return json.loads(bits(name + '.json'))
def balanced(c):
    assert not c['saturated'] and c['runtime'] == 'rc-v3-counting'
    assert c['heap_allocate'] == c['retire']
    assert c['owner_acquire'] + c['heap_allocate'] == c['owner_release']
    assert c['hold_acquire'] == c['hold_release']
def backend(row):
    assert row['manifest']['backend'] == row['backend']
    if row['backend'] == 'llvm':
        assert row['manifest']['optimization'] == '3' and row['manifest']['lto']
for name, item in json.loads((ROOT / 'files.json').read_text()).items():
    value = bits(name)
    assert len(value) == item['bytes'] and sha(value) == item['sha256'], name
m = read('measurements')
assert len(m['runs']) == 22 and len(m['builds']) == 8
assert sha(bits('bench--parity--micro--bytes_scan.my')) == m['source']['sha256']
for row in m['builds']:
    assert row['status'] == 0
    backend(row)
for row in m['runs']:
    assert row['status'] == 0 and row['stdout'] == '8388728\n'
    if row.get('stats'):
        balanced(row['counts'])
        continue
    active = [x.split(',') for x in row['perf'].splitlines() if 'instructions' in x and x.split(',')[0].isdigit()]
    assert len(active) == 1 and float(active[0][4]) == 100.0
    assert int(active[0][0]) == row['instructions']
for kind in ['qbe', 'llvm']:
    for side in ['before', 'after', 'gc']:
        rows = [r['instructions'] for r in m['runs'] if r['side'] == side and r['backend'] == kind and 'instructions' in r]
        assert len(rows) == 3
        assert statistics.median(rows) == m['medians'][side + '-' + kind]
    assert m['medians']['after-' + kind] / m['medians']['gc-' + kind] <= 1.3
counts = [r['counts'] for r in m['runs'] if r.get('stats')]
assert len(counts) == 4 and all(c == counts[0] for c in counts)
assert counts[0]['heap_allocate'] == 12 and counts[0]['hold_acquire'] == 0
assert b'RC-LOOP-OPERANDS-ISOLATED' not in bits('before-main.ssa')
assert b'RC-LOOP-OPERANDS-ISOLATED 118 s0=s3 s1=s4' in bits('after-main.ssa')
c = read('controls')
assert len(c['runs']) == 32 and len(c['builds']) == 8
for row in c['builds']:
    assert row['status'] == 0
    backend(row)
for row in c['runs']:
    balanced(row['counts'])
    if row['case'] in ['positive', 'heap']:
        assert row['status'] == 0 and row['stdout'] == ('12\n' if row['case'] == 'positive' else '11\n')
    else:
        code = {'bounds':'R_LIST_BOUNDS','heap-bounds':'R_LIST_BOUNDS','overflow':'R_OVERFLOW','steps':'R_STEP_LIMIT','frames':'R_FRAME_LIMIT','floor':'R_FRAME_LIMIT'}[row['case']]
        assert row['status'] == 1 and code in row['stderr']
    if row['side'] == 'before':
        other = next(x for x in c['runs'] if x['side'] == 'after' and all(x[k] == row[k] for k in ['backend','case','accounted']))
        trace = lambda x: '\n'.join(y for y in x['stderr'].splitlines() if not y.startswith('MYLANG_RC_COUNTS '))
        assert (row['status'],row['stdout'],trace(row)) == (other['status'],other['stdout'],trace(other))
        if row['case'] != 'floor': assert row['counts'] == other['counts']
assert all(x['heap_isolated'] == 0 and x['scan_isolated'] == (x['side'] == 'after') for x in c['emission'])
g = read('guests')
assert len(g['runs']) == 8
for row in g['runs']:
    backend(row)
    assert row['build_status'] == row['status'] == 0
    assert row['stdout'] == ('220\n' if 'guard_context' in row['source'] else '12\n')
    if row['mode'] == 'rc': balanced(row['counts'])
for name in ['rc_loop_guard_context', 'rc_loop_operand_isolation']:
    assert bits(name + '-before-gc-emission.json') == bits(name + '-after-gc-emission.json')
r = read('reentrant')
assert len(r['runs']) == 4
for row in r['runs']:
    backend(row)
    assert row['build_status'] == row['status'] == 0
    assert row['stdout'] == 'status=0 phase=2 observed=1 bad=0 result=30\n'
    balanced(row['counts'])
assert all(x['counts'] == r['runs'][0]['counts'] for x in r['runs'])
assert b'RC-LOOP-OPERANDS-ISOLATED' in bits('reentrant-after.ssa')
assert b'RC-LOOP-OPERANDS-ISOLATED' not in bits('reentrant-before.ssa')
if '--live' in sys.argv:
    for item in m['compilers'].values():
        assert sha(Path(item['path']).read_bytes()) == item['sha256']
    assert sha(Path(m['source']['path']).read_bytes()) == m['source']['sha256']
    for row in m['runs']:
        assert sha(Path(row['command'][-1]).read_bytes()) == row['binary_sha256']
    repo = ROOT.parent.parent
    for path, digest in read('source-identity')['production'].items():
        assert sha((repo/path).read_bytes()) == digest
print('Verified18 full-size instruction observations,4 identical count records,32 paired controls,8 guests and4 actual fast-copy finalizer reentries.')

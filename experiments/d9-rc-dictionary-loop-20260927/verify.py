from pathlib import Path
import gzip
import hashlib
import json
import statistics

p = Path(__file__).resolve().parent

def load(name):
    return json.loads(gzip.decompress((p / (name + '.json.gz')).read_bytes()))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def balanced(c):
    assert c['runtime'] == 'rc-v3-counting' and not c['saturated']
    assert c['heap_allocate'] == c['retire']
    assert c['owner_acquire'] + c['heap_allocate'] == c['owner_release']
    assert c['hold_acquire'] == c['hold_release']

def backend(m, target, release=False):
    assert m['backend'] == target
    if target == 'llvm' and release:
        assert m['optimization'] == '3' and m['lto'] and not m['thin_lto']

def trace(row):
    return '\n'.join(x for x in row['stderr'].splitlines() if not x.startswith('MYLANG_RC_COUNTS '))

def paired(rows, keys):
    for row in rows:
        assert row['status'] in [0, 1]
        balanced(row['counts'])
        if row['side'] != 'before':
            continue
        other = next(x for x in rows if x['side'] == 'after' and all(x[k] == row[k] for k in keys))
        assert (row['status'], row['stdout'], trace(row)) == (other['status'], other['stdout'], trace(other))

identity = json.loads((p / 'identity.json').read_text())
assert sha(p / 'dict_count.my') == identity['source_sha256']
for name, value in identity['fixtures'].items():
    assert sha(p / (name + '.my')) == value
assert (p / 'dict_count.expected').read_text() == identity['expected_stdout']
gc = load('accepted-gc-builds')
d = load('measurements')
assert d['compilers'] == identity['compilers']
assert d['source']['sha256'] == identity['source_sha256']
assert len(d['builds']) == 8 and len(d['runs']) == 22
for row in d['builds']:
    assert row['status'] == 0
    backend(row['manifest'], row['backend'], True)
for row in d['runs']:
    assert row['status'] == 0 and row['stdout'] == identity['expected_stdout']
    if row.get('stats'):
        balanced(row['counts'])
    else:
        active = [line.split(',') for line in row['perf'].splitlines()
                  if 'instructions' in line and line.split(',')[0].isdigit()]
        assert len(active) == 1 and 'cpu_core' in active[0][2]
        assert int(active[0][0]) == row['instructions'] and float(active[0][4]) == 100.0
        assert row['command'][:3] == ['taskset', '-c', '11']
    if row['side'] == 'gc':
        assert row['binary_sha256'] == gc['builds']['parity-micro-dict_count.' + row['backend']]['sha256']
for target in ['qbe', 'llvm']:
    for side in ['gc', 'before', 'after']:
        rows = [x for x in d['runs'] if x['backend'] == target and x['side'] == side and not x.get('stats')]
        assert len(rows) == 3
        assert statistics.median(x['instructions'] for x in rows) == d['medians'][side + '-' + target]
    before, after = [next(x['counts'] for x in d['runs']
                         if x['backend'] == target and x['side'] == side and x.get('stats'))
                     for side in ['before', 'after']]
    assert before['unique_check'] == 2001000 and after['unique_check'] == 1001
    for key in before:
        if key != 'unique_check':
            assert before[key] == after[key]
    assert after['heap_allocate'] == 2029 and after['clone_shell'] == 0
    assert after['owner_acquire'] == after['hold_acquire'] == 2001
for side in ['before', 'after']:
    rows = [x['counts'] for x in d['runs'] if x['side'] == side and x.get('stats')]
    assert rows[0] == rows[1]

before, after = load('emission')
assert not before['entry34'] and after['entry34']
assert not before['fast34'] and not after['fast34']
assert before['body_unique'] == 1 and after['body_unique'] == 0
assert before['key_markers'] == after['key_markers'] == 2
assert before['tail_markers'] == after['tail_markers'] == 1
assert before['calls'] == after['calls'] and before['native_calls'] == after['native_calls']
for row in [before, after]:
    il = gzip.decompress((p / (row['side'] + '-main.ssa.gz')).read_bytes())
    assert len(il) == row['bytes'] and hashlib.sha256(il).hexdigest() == row['il_sha256']
    assert row['compiler_sha256'] == identity['compilers'][row['side']]['sha256']
    measured = next(x for x in d['builds'] if x['side'] == row['side'] and x['backend'] == 'qbe' and not x['stats'])
    assert row['native_binary_sha256'] == measured['binary_sha256']

small = load('counters-initial')
assert len(small['runs']) == 4
for row in small['runs']:
    assert row['status'] == 0 and row['stdout'] == '117800\n'
    balanced(row['counts'])
for target in ['qbe', 'llvm']:
    before, after = [next(x['counts'] for x in small['runs'] if x['backend'] == target and x['side'] == side)
                     for side in ['before', 'after']]
    assert before['unique_check'] == 21000 and after['unique_check'] == 1001
    assert {k:v for k,v in before.items() if k != 'unique_check'} == {k:v for k,v in after.items() if k != 'unique_check'}

guests = load('guests')
assert guests['compiler_sha256'] == identity['compilers']['after']['sha256']
assert len(guests['runs']) == 12
for row in guests['runs']:
    result = json.loads(row['stdout'])
    assert row['status'] == 0 and result['failed'] == result['cached'] == 0
    assert row['source_sha256'] == identity['fixtures'][row['name']]
assert sum(json.loads(x['stdout'])['passed'] for x in guests['runs']) == 100

controls = load('controls')
assert len(controls['builds']) == 24 and len(controls['runs']) == 56
assert all(x['entry'] and not x['fast'] for x in controls['emission'])
for row in controls['emission']:
    assert sha(p / 'controls' / (row['case'] + '.my')) == row['sha256']
for row in controls['builds']:
    assert row['status'] == 0
    backend(row['manifest'], row['backend'])
paired(controls['runs'], ['backend', 'case', 'budget', 'options'])
for target in ['qbe', 'llvm']:
    rows = [x for x in controls['runs'] if x['side'] == 'after' and x['backend'] == target and x['case'] == 'growth']
    assert any(x['status'] == 1 and 'growth.my:8:9' in x['stderr'] for x in rows)
    assert any(x['status'] == 0 for x in rows)

arena = load('arena-extra')
assert sha(p / 'controls/arena-heap-keys.my') == arena['source_sha256']
assert len(arena['builds']) == 4 and len(arena['runs']) == 16
for row in arena['builds']:
    assert row['status'] == 0
    backend(row['manifest'], row['backend'])
paired(arena['runs'], ['backend', 'budget'])
for row in arena['runs']:
    if row['budget'] == '512K':
        assert row['status'] == 0 and row['stdout'] == 'before\n1000\n'
    else:
        assert row['status'] == 1 and 'R_MEMORY_BUDGET' in row['stderr'] and 'arena-heap-keys.my:6:9' in row['stderr']

rows = load('reentrant')['runs']
assert len(rows) == 4
assert b'\n@ce' in gzip.decompress((p / 'reentrant.ssa.gz').read_bytes())
for row in rows:
    assert row['build_status'] == row['status'] == 0
    assert row['stdout'] == 'status=0 phase=2 observed=1 bad=0 result=10\n'
    backend(row['manifest'], row['backend'])
    balanced(row['counts'])
print('Verified 18 full-size instruction receipts at 100% running, six medians, four counted runs, '
      '100 uncached assertions, 72 paired trap/budget executions, four finalizer reentries, '
      'reduced counters and emitted/native identities.')

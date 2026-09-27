from pathlib import Path
import collections
import gzip
import hashlib
import json
import statistics

p = Path(__file__).resolve().parent


def load(name):
    return json.loads(gzip.decompress((p / (name + '.json.gz')).read_bytes()))


def balanced(c):
    assert c['runtime'] == 'rc-v3-counting' and not c['saturated']
    assert c['heap_allocate'] == c['retire']
    assert c['owner_acquire'] + c['heap_allocate'] == c['owner_release']
    assert c['hold_acquire'] == c['hold_release']


def backend(m, name, release=False):
    assert m['backend'] == name
    if name == 'llvm' and release:
        assert m['optimization'] == '3' and m['lto'] and not m['thin_lto']


identity = json.loads((p / 'identity.json').read_text())
assert hashlib.sha256((p / 'dict_count.my').read_bytes()).hexdigest() == identity['source_sha256']
assert hashlib.sha256((p / 'rc_dictionary_keys.my').read_bytes()).hexdigest() == identity['fixture_sha256']
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
    for key in ['owner_acquire', 'owner_release']:
        assert before[key] - after[key] == 2000000
    for key in ['hold_acquire', 'hold_release']:
        assert before[key] - after[key] == 4000000
    for key in before:
        if key not in ['owner_acquire', 'owner_release', 'hold_acquire', 'hold_release']:
            assert before[key] == after[key]
    assert after['heap_allocate'] == 2029 and after['clone_shell'] == 0
    assert after['unique_check'] == 2001000 and after['owner_acquire'] == after['hold_acquire'] == 2001
for side in ['before', 'after']:
    rows = [x['counts'] for x in d['runs'] if x['side'] == side and x.get('stats')]
    assert rows[0] == rows[1]

before, after = load('emission-final')
assert before['key_markers'] == 0 and after['key_markers'] == 2
assert before['tail_markers'] == after['tail_markers'] == 1
for row in [before, after]:
    il = gzip.decompress((p / (row['side'] + '-final-main.ssa.gz')).read_bytes())
    assert len(il) == row['bytes'] and hashlib.sha256(il).hexdigest() == row['il_sha256']
    assert row['compiler_sha256'] == identity['compilers'][row['side']]['sha256']
for table in ['calls', 'native_calls']:
    for key, delta in [('myl_rc_native_loan', 2), ('myl_rc_native_retain', 1), ('myl_rc_hold_acquire', 1)]:
        assert before[table][key] - after[table][key] == delta
    for key in ['myl_qbe_rc_unique_local', 'myl_native_dictionary_write', 'myl_qbe_rc_frame_enter']:
        assert before[table][key] == after[table][key]
assert gzip.decompress((p / 'tail-main.ssa.gz').read_bytes()) == gzip.decompress((p / 'before-final-main.ssa.gz').read_bytes())

initial, final = load('guests-initial'), load('guests-keys-final')
assert len(initial['runs']) == 16 and len(final['runs']) == 4
for group in [initial, final]:
    assert group['compiler_sha256'] == identity['compilers']['after']['sha256']
    for row in group['runs']:
        result = json.loads(row['stdout'])
        assert row['status'] == 0 and result['failed'] == result['cached'] == 0
for row in final['runs']:
    assert row['source_sha256'] == identity['fixture_sha256']
assert sum(json.loads(x['stdout'])['passed'] for x in initial['runs']) == 148
assert sum(json.loads(x['stdout'])['passed'] for x in final['runs']) == 44
current = [x for x in initial['runs'] if x['name'] != 'rc_dictionary_keys'] + final['runs']
assert sum(json.loads(x['stdout'])['passed'] for x in current) == 152

controls = load('controls')
assert len(controls['builds']) == 41 and len(controls['runs']) == 118
for row in controls['builds']:
    assert row['status'] == 0
    backend(row['manifest'], row['backend'])
assert collections.Counter(x['status'] for x in controls['runs']) == {0: 26, 1: 92}
codes = {'bounds': 'R_LIST_BOUNDS', 'arena': 'R_LIST_BOUNDS', 'overflow': 'R_OVERFLOW',
         'steps': 'R_STEP_LIMIT', 'frames': 'R_FRAME_LIMIT', 'floor': 'R_FRAME_LIMIT',
         'growth': 'R_MEMORY_BUDGET'}
for row in controls['runs']:
    if row['status'] == 1:
        assert codes[row['case']] in row['stderr']
    if row['case'] != 'growth':
        assert row['status'] == 1 and row['stdout'] == 'before\n'
    if row['mode'] == 'rc':
        balanced(row['counts'])
    if row['side'] != 'before' or row['case'] == 'floor':
        continue
    other = next(x for x in controls['runs'] if x['side'] == 'prototype' and x['mode'] == 'rc'
                 and all(x[k] == row[k] for k in ['case', 'backend', 'budget', 'options']))
    assert (row['status'], row['stdout']) == (other['status'], other['stdout'])
    if row['case'] != 'growth':
        def trace(x):
            return '\n'.join(y for y in x['stderr'].splitlines() if not y.startswith('MYLANG_RC_COUNTS '))
        assert trace(row) == trace(other)
for target in ['qbe', 'llvm']:
    rows = [x for x in controls['runs'] if x['backend'] == target and x['side'] == 'prototype'
            and x['mode'] == 'rc' and x['case'] == 'growth']
    assert any(x['status'] == 1 and x['stdout'] == 'before\n' for x in rows)
    assert any(x['status'] == 0 for x in rows)
assert controls['excluded_diagnostics'][0]['status'] == 'timeout'
same = load('gc-floor-identity')
assert same['status'] == 0 and same['identical_text']
assert same['binaries']['before']['sha256'] == same['binaries']['after']['sha256']
assert same['binaries']['before']['text_sha256'] == same['binaries']['after']['text_sha256']

rows = load('reentrant')['runs']
assert len(rows) == 4
for row in rows:
    assert row['build_status'] == row['status'] == 0
    assert row['stdout'] == 'status=0 phase=2 observed=1 bad=0 result=10\n'
    backend(row['manifest'], row['backend'])
    balanced(row['counts'])

print('Verified 18 full-size instruction receipts at 100% running, 6 medians, 4 counted runs, '
      '152 current uncached assertions, 118 trap/budget executions, 4 finalizer reentries, '
      'emission/native identity and byte-identical before/after GC timeout binaries.')

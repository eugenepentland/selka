from pathlib import Path
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


def backend(m, name):
    assert m['backend'] == name
    if name == 'llvm':
        assert m['optimization'] == '3' and m['lto'] and not m['thin_lto']


identity = json.loads((p / 'identity.json').read_text())
assert hashlib.sha256((p / 'dict_count.my').read_bytes()).hexdigest() == identity['source_sha256']
gc = load('accepted-gc-builds')
for name in ['measurements', 'measurements-final']:
    d = load(name)
    assert len(d['builds']) == 8 and len(d['runs']) == 22
    assert d['source']['sha256'] == identity['source_sha256']
    for row in d['builds']:
        assert row['status'] == 0
        backend(row['manifest'], row['backend'])
    for row in d['runs']:
        assert row['status'] == 0 and row['stdout'] == identity['expected_stdout']
        if row.get('stats'):
            balanced(row['counts'])
        else:
            active = [line.split(',') for line in row['perf'].splitlines()
                      if 'instructions' in line and line.split(',')[0].isdigit()]
            assert len(active) == 1
            assert int(active[0][0]) == row['instructions'] and float(active[0][4]) == 100.0
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
        if name == 'measurements':
            assert before == after
        else:
            assert before['unique_check'] - after['unique_check'] == 2000000
            assert before['hold_acquire'] - after['hold_acquire'] == 7999998
            assert before['owner_acquire'] == after['owner_acquire'] == 2002001
            assert before['heap_allocate'] == 2030 and after['heap_allocate'] == 2029
            assert before['clone_shell'] == after['clone_shell'] == 0
    for side in ['before', 'after']:
        rows = [x['counts'] for x in d['runs'] if x['side'] == side and x.get('stats')]
        assert rows[0] == rows[1]
    if name == 'measurements-final':
        assert d['compilers']['after']['sha256'] == identity['final_compiler_sha256']

for name in ['emission', 'emission-native']:
    before, after = load(name)
    assert before['marker'] == 0 and after['marker'] == 1
    for key in ['unique', 'begin', 'pin', 'end']:
        assert after[key] == before[key] - 1
    for key in ['write', 'frame', 'loan']:
        assert after[key] == before[key]
before, after = load('native-selection')
for key in ['myl_qbe_rc_unique_local', 'myl_qbe_rc_scope_begin', 'myl_qbe_rc_scope_pin', 'myl_qbe_rc_scope_end']:
    assert after['calls'][key] == before['calls'][key] - 1
for key in ['myl_native_dictionary_write', 'myl_qbe_rc_frame_enter', 'myl_rc_native_loan']:
    assert after['calls'][key] == before['calls'][key]

guest = load('guests-final')
assert guest['compiler_sha256'] == identity['final_compiler_sha256']
assert len(guest['runs']) == 28
for row in guest['runs']:
    result = json.loads(row['stdout'])
    assert row['status'] == 0 and result['failed'] == 0 and result['cached'] == 0
assertions = sum(json.loads(x['stdout'])['passed'] for x in guest['runs'])
assert assertions == 188

traps = {'growth': ('R_MEMORY_BUDGET', 'before\n'), 'overflow': ('R_OVERFLOW', '7\n'),
         'steps': ('R_STEP_LIMIT', 'before\n'), 'arena': ('R_LIST_BOUNDS', '7\n')}
for name, total in [('controls', 32), ('controls-final', 16)]:
    rows = load(name)['runs']
    assert len(rows) == total
    for row in rows:
        assert row['build_status'] == 0 and row['status'] == 1
        backend(row['manifest'], row['backend'])
        code, output = traps[row['case']]
        assert code in row['stderr'] and row['stdout'] == output
        if row['mode'] == 'rc':
            balanced(row['counts'])
        if name.endswith('final'):
            assert row['compiler_sha256'] == identity['final_compiler_sha256']

for name, total in [('reentrant', 4), ('reentrant-final', 2)]:
    rows = load(name)['runs']
    assert len(rows) == total
    for row in rows:
        assert row['build_status'] == row['status'] == 0
        assert row['stdout'] == 'status=0 phase=2 observed=1 bad=0 result=10\n'
        backend(row['manifest'], row['backend'])
        balanced(row['counts'])
        if name.endswith('final'):
            assert row['compiler_sha256'] == identity['final_compiler_sha256']

print('Verified final 188 uncached assertions, 16 final traps, 2 final reentry controls, '
      '18 final full-size timing receipts, 4 balanced counted runs, native helper identity, '
      'accepted GC hashes, and the separately preserved unchanged first attempt.')

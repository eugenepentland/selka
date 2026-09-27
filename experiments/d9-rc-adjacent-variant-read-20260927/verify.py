#!/usr/bin/env python3
"""Check frozen adjacent-variant evidence without rebuilding or benchmarking."""
from pathlib import Path
import gzip
import hashlib
import json
import statistics

root = Path(__file__).resolve().parent
identity = json.loads((root / 'identity.json').read_text())
def read(name):
    return json.loads(gzip.decompress((root / (name + '.json.gz')).read_bytes()))
def balanced(c):
    assert not c['saturated']
    assert c['heap_allocate'] == c['retire']
    assert c['owner_acquire'] + c['heap_allocate'] == c['owner_release']
    assert c['hold_acquire'] == c['hold_release']
def manifest(row):
    assert row['manifest']['backend'] == row['backend']
    assert row['manifest']['lto'] == (row['backend'] == 'llvm')
for name, digest in identity['artifacts'].items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, name
assert hashlib.sha256(gzip.decompress((root / 'source.patch.gz').read_bytes())).hexdigest() == identity['source_patch_sha256']
validation = read('validation')
assert validation['after_sha256'] == identity['compiler_sha256']
assert validation['before_sha256'] == identity['prior_compiler_sha256']
assert len(validation['runs']) == 8
for row in validation['runs']:
    manifest(row)
    assert row['build_exit'] == row['exit'] == 0 and row['stdout'] == 'True\n' * 8
    if row['mode'] == 'rc': balanced(row['counts'])
    else: assert row['environment']['MYLANG_OPTIONS'] == '--gc-stress'
# Preserve the historical rows without falsely calling them GC stress.
ordinary = read('validation-ordinary-gc')
assert len(ordinary['runs']) == 8
assert (root / 'README.md').read_text().find('MYLANG_GC_STRESS') >= 0
traps = read('traps')['runs']
assert len(traps) == 16
assert sum(len(row['runs']) for row in traps) == 1448
for row in traps:
    manifest(row)
    assert row['build_exit'] == 0
    assert row['compiler_sha256'] == identity['compiler_sha256' if row['arm']=='after' else 'prior_compiler_sha256']
    for run in row['runs']:
        if row['case'] == 'bounds':
            assert run['exit'] == 1 and 'R_LIST_BOUNDS' in run['stderr'] and run['stdout'] == 'before\n'
        else:
            assert (run['exit'] == 1 and 'R_STEP_LIMIT' in run['stderr']) or (run['exit'] == 0 and run['stdout'] == 'before\n6\n')
        if row['mode'] == 'rc': balanced(run['counts'])
        else: assert '--gc-stress' in run['environment']['MYLANG_OPTIONS']
    peer = next(x for x in traps if (x['case'],x['mode'],x['backend'],x['arm']) == (row['case'],row['mode'],row['backend'],'before' if row['arm']=='after' else 'after'))
    assert [(x['budget'],x['exit'],x['stdout']) for x in row['runs']] == [(x['budget'],x['exit'],x['stdout']) for x in peer['runs']]
retains = read('retain-harness')['runs']
assert len(retains) == 4
for row in retains:
    manifest(row)
    assert row['build_exit'] == row['exit'] == 0
    assert row['stdout'] == '1 R_MEMORY_BUDGET made=1 guard=0 rows=(nil)\n'
    balanced(row['counts'])
    if row['arm']=='after': assert row['admitted'] == 1
builds = read('lox-builds')
assert builds['compiler_sha256'] == identity['compiler_sha256']
assert len(builds['builds']) == 4
assert sum(x['count'] for x in builds['admission'].values()) == 37
for row in builds['builds']:
    manifest(row)
    assert row['exit'] == 0
for name, count in [('heap::string_obj',1),('heap::set_object_field',1),('vm::load_frame',2),('vm::get_property',1)]:
    assert builds['admission'][name]['count'] == count
reference=json.loads((root/'accepted-gc-reference.json').read_text())
for backend, item in reference['samples'].items():
    assert len(item['samples'])==3
    assert statistics.median(x['counters']['cpu_core/instructions/u'] for x in item['samples'])==item['median']
    assert len(item['binary_sha256_at_archive'])==64
    for row in item['samples']:
        fields=next(x.split(',') for x in row['stderr'].splitlines() if ',cpu_core/instructions/u,' in x)
        assert float(fields[4])==100.0
for name, nrows in [('reduced',32),('full',16)]:
    data = read(name)
    assert data['before_compiler'] == identity['prior_compiler_sha256'] and data['after_compiler'] == identity['compiler_sha256']
    assert len(data['runs']) == nrows and data['cpu'] == 10
    for row in data['runs']:
        assert row['exit'] == 0 and not row['timeout']
        assert hashlib.sha256(row['stdout'].encode()).hexdigest() == row['expected_sha256']
        if row['counted']:
            balanced(row['counts'])
            other = next(x for x in data['runs'] if (x['n'],x['backend'],x['counted'],x['arm']) == (row['n'],row['backend'],True,'before' if row['arm']=='after' else 'after'))
            for key in row['counts']:
                if key not in ('hold_acquire','hold_release'): assert row['counts'][key] == other['counts'][key], key
            if row['arm']=='after': assert row['counts']['hold_acquire'] < other['counts']['hold_acquire']
        else: assert row['event_running_percent'] == 100.0 and row['instructions'] > 0
    for n in sorted({x['n'] for x in data['runs']}):
        for backend in ('qbe','llvm'):
            def median(arm): return statistics.median(x['instructions'] for x in data['runs'] if x['n']==n and x['backend']==backend and not x['counted'] and x['arm']==arm)
            assert median('after') < median('before')
            print(n, backend, 'instruction ratio', median('after')/median('before'))
assert '88 check(s) passed' in (root/'guardian-full.log').read_text()
assert '16/16 tests passed' in gzip.decompress((root/'focused-final-2.log.gz').read_bytes()).decode()
print('Adjacent variant reads: exact outputs, actual backends, traps, counts, instruction events verified (wrapper RSS is not guest-RSS acceptance).')

#!/usr/bin/env python3
"""Validate immutable named-record receipts without rebuilding or timing."""
from pathlib import Path
import gzip
import hashlib
import json
import statistics

root = Path(__file__).resolve().parent
identity = json.loads((root/'identity.json').read_text())
def read(name):
    return json.loads(gzip.decompress((root/(name+'.json.gz')).read_bytes()))
def balanced(c):
    assert not c['saturated']
    assert c['heap_allocate'] == c['retire']
    assert c['owner_acquire'] + c['heap_allocate'] == c['owner_release']
    assert c['hold_acquire'] == c['hold_release']
def manifest(row):
    assert row['manifest']['backend'] == row['backend']
    assert row['manifest']['lto'] == (row['backend'] == 'llvm')
for name, digest in identity['artifacts'].items():
    assert hashlib.sha256((root/name).read_bytes()).hexdigest() == digest, name
assert hashlib.sha256(gzip.decompress((root/'source.patch.gz').read_bytes())).hexdigest() == identity['source_patch_sha256']
validation = read('validation')
assert validation['before_sha256'] == identity['prior_compiler_sha256']
assert validation['after_sha256'] == identity['compiler_sha256']
assert len(validation['runs']) == 8
for row in validation['runs']:
    manifest(row)
    assert row['build_exit'] == row['exit'] == 0 and row['stdout'] == 'True\n'*8
    if row['mode'] == 'rc': balanced(row['counts'])
    else: assert row['environment']['MYLANG_OPTIONS'] == '--gc-stress'
traps = read('traps')
assert traps['before_sha256'] == identity['prior_compiler_sha256'] and traps['after_sha256'] == identity['compiler_sha256']
assert len(traps['rows']) == 24 and sum(len(x['runs']) for x in traps['rows']) == 48
for row in traps['rows']:
    manifest(row)
    assert row['build_exit'] == 0
    for run in row['runs']:
        if row['case'] == 'steps' and run['budget'] == 0:
            assert run['exit'] == 0 and run['stdout'] == 'before\n6\n'
        else:
            tag = {'steps':'R_STEP_LIMIT','memory':'R_MEMORY_BUDGET','overflow':'R_OVERFLOW'}[row['case']]
            assert run['exit'] == 1 and tag in run['stderr'] and run['stdout'] == 'before\n'
        if row['mode'] == 'rc': balanced(run['counts'])
        else: assert '--gc-stress' in run['environment']['MYLANG_OPTIONS']
    peer = next(x for x in traps['rows'] if (x['case'],x['mode'],x['backend'],x['arm']) == (row['case'],row['mode'],row['backend'],'before' if row['arm']=='after' else 'after'))
    assert [(x['budget'],x['exit'],x['stdout']) for x in row['runs']] == [(x['budget'],x['exit'],x['stdout']) for x in peer['runs']]
counts = read('counter')
assert len(counts['rows']) == 4
for row in counts['rows']:
    manifest(row)
    assert row['build_exit'] == 0 and len(row['runs']) == 3
    for run in row['runs']:
        assert run['exit'] == 0
        balanced(run['counts'])
for backend in ('qbe','llvm'):
    b = next(x for x in counts['rows'] if x['backend']==backend and x['arm']=='before')
    a = next(x for x in counts['rows'] if x['backend']==backend and x['arm']=='after')
    for br, ar in zip(b['runs'],a['runs']):
        assert br['stdout']==ar['stdout']
        commits=int(ar['stdout'])
        assert br['counts']['owner_acquire']-ar['counts']['owner_acquire']==3*commits
        assert br['counts']['hold_acquire']-ar['counts']['hold_acquire']==6*commits
admission = json.loads((root/'admission-final.json').read_text())
assert admission['before_compiler_sha256']==identity['prior_compiler_sha256'] and admission['after_compiler_sha256']==identity['compiler_sha256']
assert admission['vm_tail_before']==18 and admission['vm_tail_after']==22
assert sum(admission['vm_before'].values())==58 and sum(admission['vm_after'].values())==50
for key,value in admission['vm_after'].items(): assert admission['vm_before'][key]==value
assert {x['name']:x['after']-x['before'] for x in admission['changes']}=={'vm::run':4,'compiler::init_compiler':1}
for arm in ('before','after'):
    builds = read('lox-'+arm+'-builds')
    assert builds['compiler_sha256']==identity['prior_compiler_sha256' if arm=='before' else 'compiler_sha256']
    assert len(builds['builds'])==4
    for row in builds['builds']:
        manifest(row)
        assert row['exit']==0
reference=json.loads((root/'accepted-gc-reference.json').read_text())
for backend,item in reference['samples'].items():
    assert statistics.median(x['counters']['cpu_core/instructions/u'] for x in item['samples'])==item['median']
    for row in item['samples']:
        fields=next(x.split(',') for x in row['stderr'].splitlines() if ',cpu_core/instructions/u,' in x)
        assert float(fields[4])==100.0
for name,nrows in [('reduced',32),('full',16)]:
    data=read(name)
    assert data['before_compiler']==identity['prior_compiler_sha256'] and data['after_compiler']==identity['compiler_sha256']
    assert len(data['runs'])==nrows and data['cpu']==10
    for row in data['runs']:
        assert row['exit']==0 and not row['timeout']
        assert hashlib.sha256(row['stdout'].encode()).hexdigest()==row['expected_sha256']
        if row['counted']:
            balanced(row['counts'])
            other=next(x for x in data['runs'] if (x['n'],x['backend'],x['counted'],x['arm'])==(row['n'],row['backend'],True,'before' if row['arm']=='after' else 'after'))
            for key in row['counts']:
                if key not in ('owner_acquire','owner_release','hold_acquire','hold_release'): assert row['counts'][key]==other['counts'][key],key
            if row['arm']=='after':
                assert row['counts']['owner_acquire']<other['counts']['owner_acquire']
                assert other['counts']['hold_acquire']-row['counts']['hold_acquire']==2*(other['counts']['owner_acquire']-row['counts']['owner_acquire'])
        else:
            fields=next(x.split(',') for x in row['stderr'].splitlines() if ',cpu_core/instructions/u,' in x)
            assert int(fields[0])==row['instructions'] and float(fields[4])==row['event_running_percent']==100.0
    for n in sorted({x['n'] for x in data['runs']}):
        for backend in ('qbe','llvm'):
            def median(arm):return statistics.median(x['instructions'] for x in data['runs'] if x['n']==n and x['backend']==backend and not x['counted'] and x['arm']==arm)
            assert median('after')<median('before')
            print(n,backend,'ratio',median('after')/median('before'))
assert '88 check(s) passed' in (root/'guardian-full.log').read_text()
for name in ('focused-controls','focused-caller'):
    assert '15/15 tests passed' in gzip.decompress((root/(name+'.log.gz')).read_bytes()).decode()
print('Named-record writes: actual backend outputs, traps, exact traffic, admission and raw instructions verified; no guest-RSS acceptance claim.')

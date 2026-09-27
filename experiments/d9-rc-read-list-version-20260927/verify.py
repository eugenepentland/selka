#!/usr/bin/env python3
"""Verify every raw sample, preserved native control and immutable identity."""
import gzip,hashlib,json,statistics,sys
from pathlib import Path
root=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def load(name):
 p=root/name;return json.loads(gzip.decompress(p.read_bytes()) if p.suffix=='.gz' else p.read_bytes())
def balanced(n):
 assert not n['saturated']
 assert n['heap_allocate']==n['retire'] and n['owner_acquire']+n['heap_allocate']==n['owner_release'] and n['hold_acquire']==n['hold_release']
def instruction(s):
 f=next(s.split(',') for s in s.splitlines() if ',cpu_core/instructions/u,' in s)
 assert float(f[4])==100;return int(f[0])
i=load('identity.json');assert i['cpu']==3
assert hashlib.sha256(gzip.decompress((root/'source.patch.gz').read_bytes())).hexdigest()==i['patch_sha256']
c=load('controls.json.gz');assert len(c['samples'])==12 and len(c['counts'])==24 and len(c['builds'])==32
for key,e in c['samples'].items():
 assert len(e['samples'])==6
 for side in ('before','after'):
  rows=[r for r in e['samples'] if r['side']==side];assert len(rows)==3
  values=[instruction(r['stderr']) for r in rows]
  assert statistics.median(values)==e['medians'][side]
  assert values==[r['counters']['cpu_core/instructions/u'] for r in rows]
  for r in rows:
   if key.startswith('schematic/'):
    assert r['stdout'] in ('','0\n')
   elif '--live' in sys.argv:
    prog=next(p for p in c['identity']['programs'] if key.startswith(p['id']+'|'))
    assert r['stdout']==Path(prog['expected_path']).read_text()
 assert e['after_over_before']==e['medians']['after']/e['medians']['before']
 a,b=[c['counts'][key+'|'+side]['counts'] for side in ('before','after')];assert a==b;balanced(a)
for b in c['builds'].values():
 m=b['manifest']
 if m['backend']=='llvm':assert m['optimization']=='3' and m['lto'] and not m['thin_lto']
 if '--live' in sys.argv:assert sha(b['command'][b['command'].index('-o')+1])==b['sha256']
v=load('validation.json.gz');assert len(v['runs'])==16
for a in v['runs']:
 if a['side']!='before':continue
 b=next(b for b in v['runs'] if b['side']=='after' and b['backend']==a['backend'] and b['source']==a['source'])
 assert a['status']==b['status']==0 and a['stdout']==b['stdout'] and a['counts']==b['counts'];balanced(a['counts'])
e=load('embedding.json.gz');assert len(e['runs'])==56
for a in e['runs']:
 if a['side']!='before':continue
 b=next(b for b in e['runs'] if b['side']=='after' and b['backend']==a['backend'] and b['mode']==a['mode'])
 assert a['status']==b['status']==0 and a['stdout']==b['stdout'] and a['counts']==b['counts'];balanced(a['counts'])
for a in load('accounted.json.gz')['rows']:
 if a['side']!='before':continue
 b=next(b for b in load('accounted.json.gz')['rows'] if b['side']=='after' and b['backend']==a['backend'] and b['options']==a['options'])
 clean=lambda s:'\n'.join(x for x in s.splitlines() if not x.startswith('build-slot:'))
 assert a['status']==b['status']!=0 and clean(a['stderr'])==clean(b['stderr']) and a['counts']==b['counts'];balanced(a['counts'])
g=load('guard.json');assert len(g['rows'])==22 and sha(root/'guard.ssa')==g['source_sha256']
for row in g['rows']:assert row['fast']==int(row['live']==1 and row['role'] in (2,8))
em=load('unaccounted-emission.json');assert len(em)==4
for row in em:
 before=row['sides']['before'];after=row['sides']['after']
 assert all(f['markers']==0 for f in before['functions'])
 if row['id'].startswith('parity/'):
  assert row['changed']==['main'] and sum(f['markers'] for f in after['functions'])==1
assert load('residual-assembly.json')[0]['instructions']==31
refs=load('accepted-gc-reference.json')['medians']
for key in c['samples']:assert refs[key]>0
if '--live' in sys.argv:
 for d in i['compilers'].values():assert sha(d['path'])==d['sha256']
 for p,h in i['inputs'].items():assert sha(p)==h
 for p,h in i['outputs'].items():assert sha(p)==h and h in i['schematic_expected'].values()
 assert sha(i['harness']['path'])==i['harness']['sha256']
 for b in v['builds']:assert sha(b['binary'])==b['binary_sha256']
 for b in e['builds']:assert sha(b['binary'])==b['sha256'] and sha(b['source'])==b['source_sha256']
 for row in em:
  for side in row['sides'].values():assert sha(side['path'])==side['sha256']
for p,h in load('archive-sha256.json').items():assert sha(root/p)==h
print('verified72 raw production samples at100%,24 exact counted runs,28 native embedding pairs,6 accounted trap pairs,22 emitted guard cases and16 guest runs'+(' plus live identities' if '--live' in sys.argv else ''))

#!/usr/bin/env python3
"""Recompute raw medians and paired semantic checks; optional live identity audit."""
import gzip,hashlib,json,statistics,sys
from pathlib import Path
root=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def load(name):
 p=root/name;return json.loads(gzip.decompress(p.read_bytes()) if p.suffix=='.gz' else p.read_bytes())
def balanced(n):
 assert not n['saturated']
 assert n['heap_allocate']==n['retire'] and n['owner_acquire']+n['heap_allocate']==n['owner_release'] and n['hold_acquire']==n['hold_release']
def instruction(stderr):
 f=next(s.split(',') for s in stderr.splitlines() if ',cpu_core/instructions/u,' in s)
 assert float(f[4])==100;return int(f[0])
identity=load('identity.json');assert identity['cpu']==3 and hashlib.sha256(gzip.decompress((root/'source.patch.gz').read_bytes())).hexdigest()==identity['patch_sha256']
c=load('controls.json.gz');assert len(c['samples'])==12 and len(c['counts'])==24 and len(c['builds'])==32
for key,entry in c['samples'].items():
 assert len(entry['samples'])==6
 for side in ('before','after'):
  rows=[s for s in entry['samples'] if s['side']==side];assert len(rows)==3
  values=[instruction(s['stderr']) for s in rows]
  assert values==[s['counters']['cpu_core/instructions/u'] for s in rows]
  assert statistics.median(values)==entry['medians'][side]
 assert entry['after_over_before']==entry['medians']['after']/entry['medians']['before']
 a,b=[c['counts'][key+'|'+side]['counts'] for side in ('before','after')];assert a==b;balanced(a)
for build in c['builds'].values():
 m=build['manifest'];assert any(x in ('--rc-runtime','--rc-runtime=stats') for x in build['command'])
 if m['backend']=='llvm':assert m['optimization']=='3' and m['lto'] and not m['thin_lto']
 if '--live' in sys.argv:
  command=build['command'];binary=Path(command[command.index('-o')+1]);assert sha(binary)==build['sha256']
l=load('lox-results.json');assert len(l['runs'])==16 and l['cpu']==3
for backend,med in l['medians'].items():
 rows=[s for s in l['runs'] if s['backend']==backend]
 assert all(s['exit']==0 and s['stdout']==(root/'expected-n10.txt').read_text() for s in rows)
 for side in ('before','after'):
  raw=[s for s in rows if s['side']==side and not s['counted']];assert len(raw)==3
  assert statistics.median(instruction(s['stderr']) for s in raw)==med[side]
 a,b=[s['counts'] for s in rows if s['counted']];assert a==b;balanced(a)
 assert med['after_over_before']==med['after']/med['before']
 if '--live' in sys.argv:
  for s in rows:assert sha(Path(s['command'][-3]))==s['binary_sha256']
for build in load('lox-builds.json.gz')['builds']:
 assert build['status']==0
 if build['backend']=='llvm':assert build['manifest']['optimization']=='3' and build['manifest']['lto']
 if '--live' in sys.argv:assert sha(Path(build['binary']))==build['binary_sha256']
e=load('embedding-final.json')['runs'];assert len(e)==52
for backend in ('qbe','llvm'):
 for mode in range(1,14):
  a,b=[s for s in e if s['backend']==backend and s['mode']==mode]
  assert a['status']==b['status']==0 and a['stdout']==b['stdout'] and a['counts']==b['counts'];balanced(a['counts'])
v=load('validation.json.gz');guests=[s for s in v['runs'] if s['source']!='embed.my'];assert len(guests)==8
for backend in ('qbe','llvm'):
 for source in ('rc_append_loops.my','rc_plain_appends.my'):
  a,b=[s for s in guests if s['backend']==backend and s['source']==source]
  assert a['status']==b['status']==0 and a['stdout']==b['stdout'] and a['counts']==b['counts'];balanced(a['counts'])
g=load('gc-controls.json');assert len(g)==4 and all(s['status']==0 for s in g)
f=load('heap-frame-size.json');assert f['added_physical_slot']==8 and f['after']-f['before']==f['added_reservation']==16
em=load('lox-emission.json.gz');assert em['changed']==['object::new_closure'];assert all(len(r['functions'])==405 for r in em['rows'])
a,b=[{f['symbol']:f for f in r['functions']} for r in em['rows']];assert [a[k]['name'] for k in a if a[k]!=b[k]]==em['changed']
refs=load('accepted-gc-reference.json')['medians']
for key,entry in c['samples'].items():assert refs[key]>0
if '--live' in sys.argv:
 for value in identity['compilers'].values():assert sha(Path(value['path']))==value['sha256']
 for build in v['builds']:assert sha(Path(build['binary']))==build['binary_sha256'] and sha(Path(build['source']))==build['source_sha256']
 for source,expected in em['sources'].items():assert sha(Path(em['rows'][0]['cwd'])/source)==expected
for path,expected in load('archive-sha256.json').items():assert sha(root/path)==expected
print('verified 84 raw production instruction samples at 100%, 28 counted runs, 26 exact embedding pairs, 72 guest assertions, frame accounting and live identities' if '--live' in sys.argv else 'verified archived production medians,counts,embedding/guest controls and proof identities')

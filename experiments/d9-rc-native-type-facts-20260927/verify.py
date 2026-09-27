#!/usr/bin/env python3
"""Verify archived raw observations; --live also verifies surviving original files."""
import gzip,hashlib,json,re,statistics,sys
from pathlib import Path
root=Path(__file__).resolve().parent
live='--live' in sys.argv
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def read(name):
 p=root/name;return json.loads(gzip.decompress(p.read_bytes()) if name.endswith('.gz') else p.read_text())
def instructions(stderr):
 rows=[x.split(',') for x in stderr.splitlines() if ',cpu_core/instructions/u,' in x]
 assert len(rows)==1 and float(rows[0][4])==100,rows
 return int(rows[0][0])
def counts(stderr):
 rows=[json.loads(x.split(' ',1)[1]) for x in stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')]
 assert len(rows)==1
 c=rows[0];assert not c['saturated'] and c['heap_allocate']==c['retire'] and c['hold_acquire']==c['hold_release']
 return c
def existing(path,digest):
 if live:assert sha(Path(path))==digest,path
checksums=read('archive-sha256.json')
for name,digest in checksums.items():assert sha(root/name)==digest,name
identity=read('identity.json')
for c in identity['compilers'].values():existing(c['path'],c['sha256'])
for name,digest in identity['sources'].items():existing(Path(identity['worktree'])/name,digest)
assert sha(root/'source.patch')==identity['source_patch_sha256']
expected=(root/'expected-n10.txt').read_text();lox=read('lox-results.json');gc=read('accepted-gc-observations.json')
assert len(lox['runs'])==16 and sha(root/'binary_trees.tree.lox')==lox['input_sha256'];existing(lox['input'],lox['input_sha256'])
for side in ['before','after']:
 builds=read(side+'-builds.json.gz');assert len(builds['builds'])==4
 assert builds['compiler_sha256']==identity['compilers'][side]['sha256']
 for row in builds['builds']:
  assert row['exit']==0 and row['manifest']['backend']==row['backend']
  if row['backend']=='llvm':assert row['manifest']['optimization']=='3' and row['manifest']['lto'] and not row['manifest']['thin_lto']
  matches=[r for r in lox['runs'] if r['side']==side and r['backend']==row['backend'] and r['counted']==row['counted']]
  assert matches and all(r['binary_sha256']==row['binary_sha256'] for r in matches)
for backend in ['qbe','llvm']:
 allrows=[r for r in lox['runs'] if r['backend']==backend];actual={}
 for side in ['before','after']:
  rows=[r for r in allrows if r['side']==side and not r['counted']];assert len(rows)==3
  for r in rows:
   assert r['exit']==0 and r['stdout']==expected and instructions(r['stderr'])==r['instructions'] and r['event_running_percent']==100
   existing(r['command'][r['command'].index('--')+1],r['binary_sha256'])
  actual[side]=statistics.median(instructions(r['stderr']) for r in rows)
  c=[r for r in allrows if r['side']==side and r['counted']];assert len(c)==1 and c[0]['exit']==0 and c[0]['stdout']==expected
  assert counts(c[0]['stderr'])==c[0]['counts'];existing(c[0]['command'][3],c[0]['binary_sha256'])
 assert allrows[-1]['counts']==allrows[-2]['counts']
 med=lox['medians'][backend];assert all(med[k]==v for k,v in actual.items())
 assert med['after_over_before']==actual['after']/actual['before']
 denominator=gc['samples']['lox/vm/binary_trees|'+backend]['medians']['instructions']
 assert denominator==lox['accepted_gc_medians'][backend]
 assert med['before_over_gc']==actual['before']/denominator and med['after_over_gc']==actual['after']/denominator
validation=read('validation.json.gz');assert len(validation['runs'])==32
assert sum(int(re.search(r'(\d+) passed, 0 cached, 0 failed',r['stdout'])[1]) for r in validation['runs'])==264
for r in validation['runs']:
 assert r['status']==0
 assert ('--release' in r['command'])==(r['backend']=='llvm')
 existing(r['command'][4],r['source_sha256'])
for path,record in read('output-checks.json').items():
 existing(path,record['sha256'])
 if 'expected_sha256' in record:assert record['sha256']==record['expected_sha256']
layout=read('layout.json')
for mode in [0,1]:assert layout['before'+str(mode)]['layout']==layout['after'+str(mode)]['layout']
for row in layout.values():assert row['layout']['flat']==72 and row['layout']['binding']==128 and row['layout']['count']==64 and row['layout']['loanable']==68
controls=read('controls.json.gz');assert len(controls['builds'])==32 and len(controls['emitted'])==8
assert len(controls['samples'])==12 and len(controls['counts'])==24
for label,row in controls['builds'].items():
 backend='llvm' if '-llvm-' in label else 'qbe';m=row['manifest'];assert m['backend']==backend
 if backend=='llvm':assert m['optimization']=='3' and m['lto'] and not m['thin_lto']
 if live:existing(Path(identity['worktree'])/'.tmp-mut-argument/type-facts/controls'/label,row['sha256'])
for label,row in controls['emitted'].items():
 p=root/'emissions'/(label+'-emitted.json.gz');assert hashlib.sha256(gzip.decompress(p.read_bytes())).hexdigest()==row['sha256']
 if label.endswith('-before'):assert row['sha256']==controls['emitted'][label[:-7]+'-after']['sha256']
for label,row in controls['samples'].items():
 assert len(row['samples'])==6
 med={side:statistics.median(instructions(s['stderr']) for s in row['samples'] if s['side']==side) for side in ['before','after']}
 assert med==row['medians'] and row['after_over_before']==med['after']/med['before']
 for side in ['before','after']:
  c=controls['counts'][label+'|'+side];assert counts(c['stderr'])==c['counts']
 assert controls['counts'][label+'|before']['counts']==controls['counts'][label+'|after']['counts']
 assert len({s['stdout'] for s in row['samples']})==1
for label,row in gc['samples'].items():
 assert row['checks']['ok'] and len(row['observations']['perf'])==3
 raw=row['observations']['perf'];assert all(r['status']==0 and r['ok'] and instructions(r['stderr'])==r['instructions'] for r in raw)
 assert statistics.median(r['instructions'] for r in raw)==row['medians']['instructions']
# Guard against copying any inherited host environment into the archive.
def envs(value):
 if isinstance(value,dict):
  for k,v in value.items():
   if k in ['env','environment'] and isinstance(v,dict):assert all(n.startswith('MYLANG_') for n in v)
   envs(v)
 elif isinstance(value,list):
  for v in value:envs(v)
for p in root.rglob('*'):
 if p.name.endswith(('.json','.json.gz')):envs(read(str(p.relative_to(root))))
print('verified: 84 matched raw samples, 28 exact counted runs, 42 archival GC samples, 264 guest assertions, compiler/binary identities'+(' (live)' if live else ''))

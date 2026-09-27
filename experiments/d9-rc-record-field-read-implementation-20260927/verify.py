#!/usr/bin/env python3
"""Check exact compiled controls, paired full N10 events and optional live files."""
from pathlib import Path
import gzip, hashlib, json, statistics, sys
here=Path(__file__).resolve().parent;repo=here.parents[1];live='--live' in sys.argv
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def read(name):
 p=here/name;return json.loads(gzip.decompress(p.read_bytes()) if name.endswith('.gz') else p.read_bytes())
def existing(path,digest):
 if live:assert sha(Path(path))==digest,path
def counters(stderr):
 rows=[json.loads(line.split(' ',1)[1]) for line in stderr.splitlines() if line.startswith('MYLANG_RC_COUNTS ')]
 assert len(rows)==1,stderr
 c=rows[0];assert not c['saturated'] and c['heap_allocate']==c['retire'] and c['heap_allocate']+c['owner_acquire']==c['owner_release'] and c['hold_acquire']==c['hold_release'],c
 return c
for name,digest in read('archive-sha256.json').items():assert sha(here/name)==digest,name
before=read('before-identity.json');after=read('identity-after.json')
for identity in (before,after):existing(identity['compiler'],identity['compiler_sha256'])
correction=read('proof-accounting-identity.json')
existing(correction['compiler'],correction['compiler_sha256'])
assert correction['patch_sha256']==sha(here/'proof-accounting.patch')
for name,digest in after['production_and_test_sources'].items():existing(repo/name,correction['sources'].get(name,digest))
for name,digest in after['control_sources'].items():existing(name,digest)
existing(after['embedding_driver']['path'],after['embedding_driver']['sha256'])
assert after['patch_sha256']==sha(here/'implementation.patch')
for name,digest in before['sources'].items():existing(Path(before['guest'])/name,digest)
existing(before['input']['path'],before['input']['sha256'])
assert sha(here/'binary_trees.tree.lox')==before['input']['sha256']
expected=(here/'expected-n10.txt').read_text();data=read('paired-results.json.gz');assert len(data['runs'])==16
builds={}
for side,name in (('before','builds-before.json.gz'),('after','builds-after.json.gz')):
 b=read(name);expected_compiler=before if side=='before' else after
 assert b['compiler_sha256']==expected_compiler['compiler_sha256']
 for row in b['builds']:
  assert row['exit']==0
  builds[(side,row['backend'],row['counted'])]=row
  existing(row['binary'],row['binary_sha256']);assert row['manifest']['backend']==row['backend']
  if row['backend']=='llvm':assert row['manifest']['optimization']=='3' and row['manifest']['lto'] and not row['manifest']['thin_lto']
for r in data['runs']:
 assert r['exit']==0 and r['stdout']==expected
 b=builds[(r['side'],r['backend'],r['counted'])];assert b['binary_sha256']==r['sha256'];existing(r['binary'],r['sha256'])
 if r['counted']:assert counters(r['stderr'])==r['counts']
 else:
  fields=[line.split(',') for line in r['stderr'].splitlines() if ',cpu_core/instructions/u,' in line]
  assert len(fields)==1 and float(fields[0][4])==100 and int(fields[0][0])==r['instructions']
gc=read('accepted-gc-observations.json');gc_identity=read('accepted-gc-identities.json')
existing(gc_identity['compiler'],gc_identity['compiler_sha256'])
gc_sources={k.split('/benchmarks/lox/ports/mylang/',1)[1]:v for k,v in gc_identity['inputs'].items() if '/benchmarks/lox/ports/mylang/' in k}
assert all(gc_sources.get(k)==v for k,v in before['sources'].items())
for backend in ('qbe','llvm'):
 reference=gc['samples']['lox/vm/binary_trees|'+backend]
 existing(reference['run']['argv'][0],gc_identity['builds']['lox.'+backend]['sha256'])
 gc_values=[]
 for row in reference['observations']['perf']:
  fields=[line.split(',') for line in row['stderr'].splitlines() if ',cpu_core/instructions/u,' in line]
  assert len(fields)==1 and float(fields[0][4])==100
  gc_values.append(int(fields[0][0]))
 assert len(gc_values)==3
 s=data['summary'][backend];med={}
 for side in ('before','after'):
  vals=[r['instructions'] for r in data['runs'] if r['backend']==backend and r['side']==side and not r['counted']];assert len(vals)==3
  med[side]=statistics.median(vals);assert vals==s['samples'][side]
 assert med==s['medians'] and med['after']/med['before']==s['after_before']
 assert statistics.median(gc_values)==s['accepted_gc_archival_median']
 assert med['after']/s['accepted_gc_archival_median']==s['after_gc']
 assert med['before']/s['accepted_gc_archival_median']==s['before_gc']
 counts={r['side']:r['counts'] for r in data['runs'] if r['backend']==backend and r['counted']}
 assert counts['before']['hold_acquire']==184812386 and counts['after']['hold_acquire']==160905294
 for key in counts['before']:
  if key not in ('hold_acquire','hold_release'):assert counts['before'][key]==counts['after'][key],key
# Complete source bodies, including labels and temporary numbering, retain fallback.
for mode in ('plain','accounted'):
 bodies={side:{f['name']:f['il'] for f in read(side+'-'+mode+'.json.gz')['functions']} for side in ('before','after')}
 for name in ('floating','captured_callback'):assert bodies['before'][name]==bodies['after'][name]
 for name in ('read','read_from','adjacent','arithmetic','heap_frame'):
  assert 'RC-RECORD-FIELD-READ-1' in bodies['after'][name]
for side,want in (('before',50),('after',48)):
 text=gzip.decompress((here/('vm-run-'+side+'.il.gz')).read_bytes()).decode();assert text.count('call $myl_rc_native_loan')==want
 assert text.count('RC-RECORD-FIELD-READ-1')==(side=='after')
assert (here/'driver.my').read_text().count('    assert test_')==9
g=read('guests.json.gz');assert len(g['rows'])==6
for path,digest in g['sources'].items():existing(path,digest)
for side,row in g['compilers'].items():assert row['sha256']==(before if side=='before' else after)['compiler_sha256']
for r in g['rows']:
 assert r['exit']==0 and r['run']['exit']==0
 existing(r['binary'],r['sha256']);assert r['manifest']['backend']==r['backend']
 if r['backend']=='llvm':assert r['manifest']['optimization']=='3' and r['manifest']['lto'] and not r['manifest']['thin_lto']
 if r['mode']=='rc':counters(r['run']['stderr'])
e=read('embedding.json.gz');assert len(e['builds'])==4 and len(e['runs'])==56
for b in e['builds']:
 assert b['exit']==0 and b['manifest']['backend']==b['backend'];existing(b['binary'],b['sha256'])
for r in e['runs']:
 assert r['exit']==0;counters(r['stderr'])
 if r['side']=='before':
  other=next(x for x in e['runs'] if x['side']=='after' and x['backend']==r['backend'] and x['mode']==r['mode'])
  if r['mode']==13:
   assert 'R_REFERENCE_COUNT_LIMIT line=14' in r['stdout'] and 'status=0 ' in other['stdout']
  else:assert r['stdout']==other['stdout']
assert 'PASS — 208 passed' in (here/'focused-rc.log').read_text()
fixed=read('proof-final-builds.json.gz')
assert fixed['compiler_sha256']==correction['compiler_sha256'] and len(fixed['builds'])==4
for row in fixed['builds']:
 assert row['exit']==0 and row['manifest']['backend']==row['backend']
 original=builds[('after',row['backend'],row['counted'])]
 assert row['binary_sha256']==original['binary_sha256']
 existing(row['binary'],row['binary_sha256'])
fixed=read('proof-controls.json.gz')
assert fixed['compiler_sha256']==correction['compiler_sha256'] and len(fixed['builds'])==6 and len(fixed['runs'])==32 and len(fixed['emissions'])==2
for row in fixed['builds']:
 assert row['exit']==0 and row['sha256']==row['original_sha256']
 existing(row['binary'],row['sha256']);existing(row['original'],row['original_sha256'])
for row in fixed['runs']:
 assert row['exit']==0
 if row['kind']=='guest':
  old=next(x for x in g['rows'] if x['side']=='after' and x['backend']==row['backend'] and x['mode']==row['mode'])['run']
 else:
  old=next(x for x in e['runs'] if x['side']=='after' and x['backend']==row['backend'] and x['mode']==row['mode'])
 assert (row['stdout'],row['stderr'])==(old['stdout'],old['stderr'])
for row in fixed['emissions']:
 original=gzip.decompress((here/('after-'+row['mode']+'.json.gz')).read_bytes())
 assert row['exit']==0 and row['sha256']==hashlib.sha256(original).hexdigest()
assert '209/209 tests passed' in (here/'focused-accounted-fixed.log').read_text()
print('verified10 byte-identical corrected binaries and32 repeated controls;12 raw100%events,4 exact full counts,54 guest assertions,26 matched embedding pairs+4 temporary-H cases,50→48 loans and exact refused bodies'+(' with live identities' if live else ''))

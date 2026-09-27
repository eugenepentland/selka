#!/usr/bin/env python3
"""Verify closed incoming-lifetime controls and exact paired N10 observations."""
from pathlib import Path
import gzip,hashlib,json,statistics,sys
here=Path(__file__).resolve().parent;repo=here.parents[1];live='--live' in sys.argv
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def read(name):
 p=here/name;return json.loads(gzip.decompress(p.read_bytes()) if name.endswith('.gz') else p.read_bytes())
def existing(p,digest):
 if live:assert sha(Path(p))==digest,str(p)
def counts(stderr):
 lines=[x for x in stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')];assert len(lines)==1
 c=json.loads(lines[0].split(' ',1)[1]);assert not c['saturated'] and c['heap_allocate']==c['retire'] and c['heap_allocate']+c['owner_acquire']==c['owner_release'] and c['hold_acquire']==c['hold_release'];return c
for p,digest in read('archive-sha256.json').items():assert sha(here/p)==digest,p
identity=read('identity.json');existing(identity['compiler'],identity['compiler_sha256']);existing(identity['before_compiler'],identity['before_compiler_sha256'])
fixed=read('proof-correction-identity.json');existing(fixed['compiler'],fixed['compiler_sha256'])
assert sha(here/'final-source.patch')==fixed['patch_sha256']
for p,digest in fixed['sources'].items():existing(repo/p,digest)
for p,digest in identity['sources'].items():existing(Path(identity['guest'])/p,digest)
assert sha(here/'implementation.patch')==identity['patch_sha256']
existing(identity['embedding_driver']['path'],identity['embedding_driver']['sha256'])
builds={}
for side,name in [('before','builds-before.json.gz'),('after','candidate-builds.json.gz')]:
 d=read(name);assert d['compiler_sha256']==identity['before_compiler_sha256' if side=='before' else 'compiler_sha256'];assert len(d['builds'])==4
 for row in d['builds']:
  assert row['exit']==0;assert row['manifest']['backend']==row['backend'];existing(row['binary'],row['binary_sha256'])
  if row['backend']=='llvm':assert row['manifest']['optimization']=='3' and row['manifest']['lto'] and not row['manifest']['thin_lto']
  builds[side,row['backend'],row['counted']]=row
expected=(here/'expected-n10.txt').read_text();data=read('paired-results.json.gz');assert len(data['runs'])==16
existing(data['input'],data['input_sha256']);assert sha(here/'binary_trees.tree.lox')==data['input_sha256']
for row in data['runs']:
 assert row['exit']==0 and row['stdout']==expected
 b=builds[row['side'],row['backend'],row['counted']];assert row['sha256']==b['binary_sha256'];existing(row['binary'],row['sha256'])
 if row['counted']:assert counts(row['stderr'])==row['counts']
 else:
  raw=[x.split(',') for x in row['stderr'].splitlines() if ',cpu_core/instructions/u,' in x];assert len(raw)==1 and float(raw[0][4])==100 and int(raw[0][0])==row['instructions']
gc=read('accepted-gc-observations.json');gc_identity=read('accepted-gc-identities.json');existing(gc_identity['compiler'],gc_identity['compiler_sha256'])
gc_sources={k.split('/benchmarks/lox/ports/mylang/',1)[1]:v for k,v in gc_identity['inputs'].items() if '/benchmarks/lox/ports/mylang/' in k}
assert all(gc_sources.get(k)==v for k,v in identity['sources'].items())
for backend in ('qbe','llvm'):
 med={side:statistics.median([row['instructions'] for row in data['runs'] if row['side']==side and row['backend']==backend and not row['counted']]) for side in ('before','after')}
 s=data['summary'][backend];assert med==s['medians'] and med['after']/med['before']==s['after_before']
 ref=gc['samples']['lox/vm/binary_trees|'+backend];existing(ref['run']['argv'][0],gc_identity['builds']['lox.'+backend]['sha256']);observed=[]
 for row in ref['observations']['perf']:
  raw=[x.split(',') for x in row['stderr'].splitlines() if ',cpu_core/instructions/u,' in x];assert len(raw)==1 and float(raw[0][4])==100;observed.append(int(raw[0][0]))
 assert len(observed)==3 and statistics.median(observed)==s['accepted_gc_archival_median']
 assert med['after']/statistics.median(observed)==s['after_gc'] and med['before']/statistics.median(observed)==s['before_gc']
 c={row['side']:row['counts'] for row in data['runs'] if row['backend']==backend and row['counted']}
 assert c['before']['hold_acquire']==160905294 and c['after']['hold_acquire']==146041398
 for key in c['before']:
  if key not in ('hold_acquire','hold_release'):assert c['before'][key]==c['after'][key],key
# Complete project bodies retain all non-target lowering exactly.
a={f['name']:f['il'] for f in read('project-before.json.gz')['functions']};b={f['name']:f['il'] for f in read('emitted.json.gz')['functions']}
assert a.keys()==b.keys();assert sorted(n for n in a if a[n]!=b[n])==['vm::make_closure','vm::read_byte']
for n,old,new in [('vm::read_byte',2,0),('vm::make_closure',3,1),('vm::read_short',4,4),('vm::read_constant',2,2),('vm::run',48,48)]:
 assert a[n].count('call $myl_rc_native_loan')==old and b[n].count('call $myl_rc_native_loan')==new
for mode in ('plain','accounted'):
 bodies={side:{f['name']:f['il'] for f in read(side+'-'+mode+'.json.gz')['functions']} for side in ('before','after')}
 for n in ('readonly','callback'):assert bodies['before'][n]==bodies['after'][n]
 for n in ('advance','read_only_inout','replace_after','cross','overflow_after','heap_frame'):
  assert 'RC-CALLER-FIELD-READ-1' not in bodies['before'][n] and 'RC-CALLER-FIELD-READ-1' in bodies['after'][n]
 assert 'call $myl_qbe_frame_allocate' in bodies['after']['heap_frame']
g=read('guests.json.gz');assert len(g['rows'])==6 and (here/'driver.my').read_text().count('    assert test_')==8
for p,digest in g['sources'].items():existing(p,digest)
for row in g['rows']:
 assert row['exit']==0 and row['run']['exit']==0;assert row['manifest']['backend']==row['backend'];existing(row['binary'],row['sha256'])
 if row['mode']=='rc':counts(row['run']['stderr'])
 if row['backend']=='llvm':assert row['manifest']['optimization']=='3' and row['manifest']['lto']
e=read('embedding.json.gz');assert len(e['builds'])==4 and len(e['runs'])==64
for b in e['builds']:assert b['exit']==0 and b['manifest']['backend']==b['backend'];existing(b['binary'],b['sha256'])
for row in e['runs']:
 assert row['exit']==0;counts(row['stderr'])
 if row['side']=='before':
  other=next(x for x in e['runs'] if x['side']=='after' and x['backend']==row['backend'] and x['mode']==row['mode'])
  if row['mode']==13:assert 'R_REFERENCE_COUNT_LIMIT' in row['stdout'] and 'status=0 ' in other['stdout']
  else:assert row['stdout']==other['stdout']
assert '119/119 tests passed' in (here/'focused-rc.log').read_text()
correction=read('proof-final-builds.json.gz');assert correction['compiler_sha256']==fixed['compiler_sha256'] and len(correction['builds'])==4
for row in correction['builds']:
 assert row['exit']==0 and row['binary_sha256']==builds['after',row['backend'],row['counted']]['binary_sha256'];existing(row['binary'],row['binary_sha256'])
correction=read('proof-controls.json.gz');assert correction['compiler_sha256']==fixed['compiler_sha256'] and len(correction['builds'])==6 and len(correction['runs'])==36
for row in correction['builds']:
 assert row['exit']==0 and row['sha256']==row['original_sha256'];existing(row['binary'],row['sha256']);existing(row['original'],row['original_sha256'])
for row in correction['runs']:
 original=(next(x for x in g['rows'] if x['side']=='after' and x['backend']==row['backend'] and x['mode']==row['mode'])['run'] if row['kind']=='guest' else next(x for x in e['runs'] if x['side']=='after' and x['backend']==row['backend'] and x['mode']==row['mode']))
 assert row['exit']==0 and (row['stdout'],row['stderr'])==(original['stdout'],original['stderr'])
assert len(correction['emissions'])==2
for row in correction['emissions']:assert row['exit']==0 and row['sha256']==hashlib.sha256(gzip.decompress((here/('after-'+row['mode']+'.json.gz')).read_bytes())).hexdigest()
assert '20/20 tests passed' in (here/'focused-proof-final.log').read_text()
assert '88 check(s) passed' in (here/'guardian-full.log').read_text()
print('verified10 byte-identical corrected binaries+36 repeated controls;12 raw100%events,4 exact full counts,48 guest assertions,30 exact embedding pairs+4 removed-H-limit controls; only2 Lox bodies changed'+(' with live identities' if live else ''))

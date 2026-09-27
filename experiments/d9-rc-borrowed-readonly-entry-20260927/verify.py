#!/usr/bin/env python3
"""Verify immutable borrowed/immortal entry evidence; never rerun benchmarks."""
from pathlib import Path
import argparse,gzip,hashlib,json,re,statistics
H=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def rawbytes(name):
 p=H/name
 return gzip.decompress(p.read_bytes()) if p.suffix=='.gz' else p.read_bytes()
def read(name):return json.loads(rawbytes(name))
def receipt(name):return read('receipts/'+name+'.json.gz')
def balanced(n):
 assert not n['saturated'] and n['owner_limit']==n['hold_limit']==0
 assert n['heap_allocate']==n['retire'] and n['owner_release']==n['owner_acquire']+n['heap_allocate']
 assert n['hold_acquire']==n['hold_release']
def counts(row):
 parsed=[json.loads(s.split(' ',1)[1]) for s in row['stderr'].splitlines() if s.startswith('MYLANG_RC_COUNTS ')]
 assert parsed==[row['counts']];balanced(parsed[0])
def native(data):
 for row in data['builds']:
  assert row['status']==0
  c=row['command'];m=row['manifest'];backend=next(s.split('=',1)[1] for s in c if s.startswith('--backend='));assert m['backend']==backend
  if backend=='llvm':
   level=next(s.split('=',1)[1] for s in c if s.startswith('--llvm-opt='));assert str(m['optimization'])==level
   assert bool(m['lto'])==('--lto' in c)
def perf(row):
 assert row['status']==0 and row['ok'];got=[]
 for line in row['stderr'].splitlines():
  f=line.split(',')
  if len(f)>4 and f[0].isdigit() and any(s in f[2] for s in ('instructions','cycles')):
   assert float(f[4])==100.0
   if 'instructions' in f[2]:got.append(int(f[0]))
 assert got==[row['instructions']] and row['instructions']>0
 return row['instructions']
def clean(row):return '\n'.join(s for s in row['stderr'].splitlines() if not s.startswith('MYLANG_RC_COUNTS '))
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--live',action='store_true');a=p.parse_args()
 for name,h in read('archive-sha256.json').items():assert sha(H/name)==h,name
 d=read('schematic.json.gz');assert d['complete'] and d['cpu']==2 and d['diagnostic_only'] and not d['rss_measured']
 assert len(d['samples'])==6 and len(d['counted'])==12 and len(d['builds'])==8
 gc=read('accepted-gc.json.gz');assert hashlib.sha256(rawbytes('accepted-gc.json.gz')).hexdigest()==d['accepted_gc_receipt_sha256']
 total=0
 for key,row in d['samples'].items():
  for side in ('before','after'):
   obs=row['observations'][side];assert len(obs)==3;total+=len(obs)
   assert row['medians'][side]==statistics.median(perf(r) for r in obs)
   check=row['checks'][side];assert check['ok'] and check['status']==0
   svg=rawbytes('svg/'+key.replace('/','-').replace('|','-')+'-'+side+'.svg.gz')
   assert hashlib.sha256(svg).hexdigest()==check['svg_sha256'] and len(svg)==check['svg_bytes']
  assert row['checks']['before']['svg_sha256']==row['checks']['after']['svg_sha256']
  assert row['after_before']==row['medians']['after']/row['medians']['before']
  assert row['accepted_gc']==gc['samples'][key]['medians']['gc']['instructions']
  assert row['after_gc']==row['medians']['after']/row['accepted_gc']
 assert total==36
 for row in d['builds'].values():
  assert row['ok']
  if row['manifest']['backend']=='llvm':assert str(row['manifest']['optimization'])=='3' and row['manifest']['lto']
 for key,row in d['counted'].items():
  assert row['check']['ok'] and row['check']['status']==0;counts(dict(row['check'],counts=row['counts']))
  assert row['check']['svg_sha256']==d['samples'][key.rsplit('|',1)[0]]['checks'][key.rsplit('|',1)[1]]['svg_sha256']
 for workload in ('fixture','changed-net','changed-value'):
  allcounts=[d['counted'][f'schematic/{workload}|{b}|{s}']['counts'] for b in ('qbe','llvm') for s in ('before','after')];assert all(x==allcounts[0] for x in allcounts)
 c=receipt('controls');assert c['complete'] and len(c['runs'])==8;native(c)
 for row in c['runs']:
  assert row['status']==0 and row['stdout']=='True\nTrue\nTrue\n'
  if row['runtime']=='rc':counts(row)
  else:assert row['options']=='--gc-stress'
 c=receipt('abi');assert c['complete'] and len(c['runs'])==8;native(c)
 for row in c['runs']:assert row['status']==0;counts(row)
 initial=receipt('reentrant');assert initial['complete'] and len(initial['runs'])==8;native(initial)
 for row in initial['runs']:assert row['status']==0 and 'observed=1 inside=0 bad=0 answer=114' in row['stdout'];counts(row)
 floor=receipt('native-floor');assert floor['complete'] and len(floor['runs'])==4
 for row in floor['runs']:assert row['status']==0 and 'code=R_FRAME_LIMIT' in row['stdout'];counts(row)
 bridge=receipt('final-control-bridge');assert not bridge.get('complete',False) and len(bridge['runs'])==6;native(bridge)
 assert bridge['compiler_sha256']==d['compilers']['after']['sha256']
 for row in bridge['runs']:
  assert row['status']==0;counts(row)
  assert ('code=R_FRAME_LIMIT' if row['mode']==2 else 'observed=1 inside=0 bad=0 answer=114') in row['stdout']
 assert len(bridge['trap_identities'])==1
 assert bridge['trap_identities'][0]['original_sha256']!=bridge['trap_identities'][0]['replacement_sha256']
 traps=receipt('traps');final=receipt('traps-final');assert traps['complete'] and final['complete'];assert len(traps['runs'])==28 and len(final['runs'])==14
 native(traps);native(final);assert final['compilers']['after']['sha256']==d['compilers']['after']['sha256']
 for data in (traps,final):
  for row in data['runs']:
   counts(row);assert row['expected_trap'] in row['stderr']
   assert row['status']==(1 if row['expected_trap'] else 10 if row['case']=='fallback' else 12)
 for row in final['runs']:
  before=next(r for r in traps['runs'] if r['side']=='before' and r['backend']==row['backend'] and r['case']==row['case'])
  assert clean(row)==clean(before) and row['stdout']==before['stdout']
 old=receipt('identity-bridge');assert not old.get('complete',False) and len(old['rows'])==9
 for row in old['rows'][:8]:assert row['status']==0 and row['original_sha256']==row['replacement_sha256']
 assert old['rows'][8]['original_sha256']!=old['rows'][8]['replacement_sha256']
 assert b'AssertionError' in rawbytes('receipts/identity-bridge.log.gz') and b'AssertionError' in rawbytes('receipts/final-control-bridge.log.gz')
 cache=read('cache/results.json.gz');assert cache['complete'] and len(cache['emissions'])==6 and len(cache['runs'])==4;native(cache)
 for label in ('constant','changed','allocated'):
  maps=[{f['symbol']:f for f in read('cache/'+label+'-'+warm+'.json.gz')['functions']} for warm in ('warm','cold')]
  assert {s:f['il'] for s,f in maps[0].items()}=={s:f['il'] for s,f in maps[1].items()}
  for name in ('middle','selected'):
   f=next(f for f in maps[0].values() if f['name']==name and not f['symbol'].endswith(('_rc_borrow','_rc_immortal')))
   assert ('call $myl_qbe_rc_frame_enter' in f['il'])==(label=='allocated')
 for row in cache['runs']:assert row['status']==3;counts(row)
 admission=read('admission.json')
 for name,n in [('sexpr::at',1),('layout::partPin',2)]:
  before=next(r for r in admission if r['state']=='initial' and r['name']==name and r['alternate']=='borrow')
  after=next(r for r in admission if r['state']=='final' and r['name']==name and r['alternate']=='borrow')
  assert before['frames']==1 and after['frames']==after['loan']==after['retain']==0 and after['immortal_calls']==n
 immortal=next(r for r in admission if r['state']=='final' and r['alternate']=='immortal' and r['name']=='text::empty')
 assert immortal['frames']==immortal['loan']==immortal['retain']==immortal['immortal_calls']==0
 for log,n in [('focused-immortal-oom2.log',18),('focused-readonly-immortal3.log',26),('focused-raw-final.log',15)]:
  assert f'"passed":{n},"failed":0' in rawbytes('receipts/'+log+'.gz').decode()
 assert b'88' in rawbytes('receipts/guardian-whole.log.gz')
 ident=read('identity.json')
 for name,h in ident['source_files'].items():assert hashlib.sha256(rawbytes('source/'+name+'.gz')).hexdigest()==h,name
 assert hashlib.sha256(rawbytes('source.patch.gz')).hexdigest()==ident['candidate_source_patch_sha256']
 assert hashlib.sha256(rawbytes('receipts/frozen-source.json.gz')).hexdigest()==d['source_manifest_sha256']
 if a.live:
  for name,h in ident['live_files'].items():assert sha(name)==h,name
  for name,h in d['inputs'].items():assert sha(name)==h,name
 print('Verified 36 unscaled instruction samples, 12 unchanged balanced workload counts, 24 guest assertions, 8 return-ABI controls, final-compiler finalizer/floor and exact Debug traps, cache invalidation, actual alternate admission, and preserved identity failures.')
if __name__=='__main__':main()

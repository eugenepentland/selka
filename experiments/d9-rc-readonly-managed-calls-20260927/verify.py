#!/usr/bin/env python3
"""Check managed-readonly receipts without rerunning the benchmark."""
from pathlib import Path
import argparse,gzip,hashlib,json,statistics
H=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(name):
 p=H/name
 return json.loads(gzip.decompress(p.read_bytes()) if p.suffix=='.gz' else p.read_bytes())
def balanced(n):
 assert not n['saturated'] and n['owner_limit']==n['hold_limit']==0
 assert n['heap_allocate']==n['retire']
 assert n['owner_release']==n['owner_acquire']+n['heap_allocate']
 assert n['hold_acquire']==n['hold_release']
def counts(row):
 parsed=[json.loads(s.split(' ',1)[1]) for s in row['stderr'].splitlines() if s.startswith('MYLANG_RC_COUNTS ')]
 expected=row['counts'] if isinstance(row['counts'],list) else [row['counts']]
 assert parsed==expected and len(parsed)==1
 balanced(parsed[0])
def native_builds(data):
 for row in data['builds']:
  assert row['status']==0
  command=row['command'];m=row['manifest'];backend=next(s.split('=',1)[1] for s in command if s.startswith('--backend='))
  assert backend==m['backend']
  if backend=='llvm':
   expected='0' if '--mode=Debug' in command else '3'
   assert str(m['optimization'])==expected
   if expected=='3':assert m['lto'] and not m['thin_lto']
def raw(row):
 assert row['status']==0 and row['ok']
 found=[]
 for s in row['stderr'].splitlines():
  f=s.split(',')
  if len(f)>4 and 'instructions' in f[2] and 'cpu_atom' not in f[2]:
   assert f[0].isdigit() and float(f[4])==100.0
   found.append(int(f[0]))
 assert found==[row['instructions']] and found[0]>0
 return found[0]
def guest(data,expected,runs):
 assert len(data['runs'])==runs
 for row in data['runs']:
  assert row['status']==0 and row['stdout']==expected
  if 'counts' in row:counts(row)
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--live',action='store_true');args=p.parse_args()
 for n,h in read('archive-sha256.json').items():assert sha(H/n)==h,n
 d=read('schematic.json.gz');assert d['complete'] and len(d['samples'])==6 and len(d['counted'])==12
 assert d['cpu']==10 and d['diagnostic_only'] and not d['rss_measured']
 gc=read('accepted-gc.json.gz');assert sha(H/'accepted-gc.json.gz')
 n=0
 for key,row in d['samples'].items():
  assert row['checks']['before']['svg_sha256']==row['checks']['after']['svg_sha256']
  for side in ('before','after'):
   observations=row['observations'][side];assert len(observations)==3
   assert row['medians'][side]==statistics.median(raw(r) for r in observations)
   assert row['checks'][side]['ok'] and row['checks'][side]['status']==0;n+=3
  assert row['after_before']==row['medians']['after']/row['medians']['before']
  assert row['accepted_gc']==gc['samples'][key]['medians']['gc']['instructions']
  assert row['after_gc']==row['medians']['after']/row['accepted_gc']
 assert n==36
 for row in d['counted'].values():
  assert row['check']['ok'] and row['check']['status']==0
  counts(dict(row['check'],counts=row['counts']))
 for row in d['builds'].values():
  assert row['ok']
  if row['manifest']['backend']=='llvm':assert str(row['manifest']['optimization'])=='3' and row['manifest']['lto']
 for workload in ('fixture','changed-net','changed-value'):
  for side in ('before','after'):
   assert d['counted']['schematic/'+workload+'|qbe|'+side]['counts']==d['counted']['schematic/'+workload+'|llvm|'+side]['counts']
 before=read('controls.json.gz');after=read('controls-after.json.gz')
 for controls in (before,after):
  guest(controls,'True\nTrue\nTrue\n',3)
  native_builds({'builds':controls['builds'][:-1]})
  failed=controls['builds'][-1]
  assert failed['backend']=='llvm' and failed['runtime']=='rc' and failed['status']==2
  assert 'frame-map position names another guest function' in failed['stderr']
  assert not controls.get('complete',False)
 for backend in ('qbe','llvm'):
  x=next(r for r in before['builds'] if r['runtime']=='gc' and r['backend']==backend)
  y=next(r for r in after['builds'] if r['runtime']=='gc' and r['backend']==backend)
  assert x['binary_sha256']==y['binary_sha256']
 fresh=read('baseline-llvm-fresh.json.gz');assert fresh['status']==2 and 'frame-map position names another guest function' in fresh['stderr']
 debug=read('controls-debug.json.gz');assert debug['complete'];native_builds(debug);guest(debug,'True\nTrue\nTrue\n',2)
 split=read('split-controls.json.gz');assert split['complete'];native_builds(split);guest(split,'True\n',4)
 octets=read('controls-bytes.json.gz');assert octets['complete'];native_builds(octets);guest(octets,'True\nTrue\nTrue\n',8)
 for backend in ('qbe','llvm'):
  rows=[r for r in octets['builds'] if r['runtime']=='gc' and r['backend']==backend]
  assert len(rows)==2 and rows[0]['binary_sha256']==rows[1]['binary_sha256']
 traps=read('traps.json.gz');assert traps['complete'] and len(traps['runs'])==24;native_builds(traps)
 for r in traps['runs']:
  assert r['status']==(1 if r['expected_trap'] else 97)
  assert r['expected_trap'] in r['stderr'];counts(r)
 for backend in ('qbe','llvm'):
  for case in ('upper','lower','steps54','steps55','frames','success'):
   rows=[r for r in traps['runs'] if r['backend']==backend and r['case']==case]
   cleaned=['\n'.join(x for x in r['stderr'].splitlines() if not x.startswith('MYLANG_RC_COUNTS ')) for r in rows]
   assert len(rows)==2 and cleaned[0]==cleaned[1] and rows[0]['stdout']==rows[1]['stdout']
 cache=read('cache-control.json.gz');assert cache['complete'] and len(cache['emissions'])==6 and len(cache['runs'])==4;native_builds(cache)
 for state in ('plain','changed','allocated'):
  values=[read('cache/'+state+'-'+side+'.json.gz') for side in ('warm','cold')]
  il=[{f['name']:f['il'] for f in m['functions']} for m in values];assert il[0]==il[1]
  for name in ('selected','middle'):assert ('call $myl_qbe_rc_frame_enter' in il[0][name])==(state=='allocated')
 for row in cache['runs']:assert row['status']==100;counts(row)
 for kind,names in [('schematic',('layout::nearest',)),('lox',('table::get','resolver::resolve_local'))]:
  manifests=[read('emissions/'+kind+'-bytes-'+side+'-emitted.json.gz') for side in ('before','after')]
  maps=[{f['name']:f for f in m['functions']} for m in manifests];assert maps[0].keys()==maps[1].keys()
  for name in names:assert maps[0][name]['il']==maps[1][name]['il']
  if kind=='schematic':
   form=maps[1]['sexpr::form']['il'];assert form.count('_rc_borrow(l %ctx')==2
   for symbol in ('myl_rc_native_loan','myl_rc_native_retain','myl_qbe_rc_frame_enter'):assert 'call $'+symbol not in form
 identity=read('identity.json')
 for path,digest in identity['source_files'].items():assert sha(H/'source'/path)==digest,path
 assert hashlib.sha256(gzip.decompress((H/'source.patch.gz').read_bytes())).hexdigest()==identity['candidate_source_patch_sha256']
 if args.live:
  for path,digest in identity['live_files'].items():assert sha(path)==digest,path
 print('Verified36 unscaled instruction samples,12 balanced workload counts,52 guest assertions,20 exact traps+4 successes, cache invalidation, prior-v1 IL stability, and explicit paired baseline build failure.')
if __name__=='__main__':main()

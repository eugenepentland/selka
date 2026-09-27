from pathlib import Path
import concurrent.futures,hashlib,importlib.util,json,os,statistics,subprocess

ROOT=Path.cwd();W=ROOT/'.tmp-managed-readonly/performance';W.mkdir(exist_ok=True)
PERF=ROOT.parent/'d9-rc-performance'
spec=importlib.util.spec_from_file_location('core',PERF/'experiments/d9-rc-ownership-joined-20260927/measurement_core.py')
M=importlib.util.module_from_spec(spec);spec.loader.exec_module(M)
M.CPU=10;A,PC=M.A,M.PC
os.environ['TMPDIR']=str(ROOT/'.tmp-managed-readonly/tmp')
os.environ['ZIG_LOCAL_CACHE_DIR']=str(ROOT/'.tmp-managed-readonly/guest-zig-cache')
C={'before':ROOT/'.tmp-managed-readonly/install-before/bin/mylang',
   'after':ROOT/'.tmp-managed-readonly/install-bytes/bin/mylang'}
P=[p for p in A.programs() if p['kind']=='schematic'];assert len(P)==3
baseline_path=A.WORK/'gc-builds.json'
baseline=json.loads(baseline_path.read_text())
assert baseline['compiler_sha256']==A.GC_SHA==A.sha(baseline['compiler'])
assert baseline['inputs']==A.inputs()
historical=json.loads((A.WORK/'ownership-joined-e5d47d20/results.json').read_text())
D={'compilers':{s:{'path':str(c),'sha256':A.sha(c)} for s,c in C.items()},'cpu':10,'inputs':A.inputs(),
   'accepted_gc_receipt':{'path':str(A.WORK/'ownership-joined-e5d47d20/results.json'),'sha256':A.sha(A.WORK/'ownership-joined-e5d47d20/results.json'),'manifest_sha256':A.sha(baseline_path)},'driver_sha256':A.sha(__file__),'builds':{},'samples':{},'counted':{},'diagnostic_only':True,'rss_measured':False}
def save():A.write(W/'results.json',D)
jobs={}
for side,c in C.items():
 for backend in ('qbe','llvm'):
  for stats in (False,True):
   key=side+'.'+backend+('.stats' if stats else '');binary=W/key
   command,cwd=PC.build_command(P[0],str(c),backend,binary,W/('cache-'+side))
   command+=['--rc-runtime=stats' if stats else '--rc-runtime']
   jobs[key]={'bin':binary,'cmd':[str(ROOT/'scripts/build-slot.sh'),'build',*command],'cwd':cwd}
save()
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
 pending={pool.submit(PC.do_build,job):key for key,job in jobs.items()}
 for future in concurrent.futures.as_completed(pending):
  key=pending[future];D['builds'][key]=future.result();save();assert D['builds'][key]['ok'],D['builds'][key]
  manifest=json.loads(Path(str(jobs[key]['bin'])+'.qbe-manifest.json').read_text())
  assert manifest['backend']==key.split('.')[1]
  D['builds'][key]['manifest']=manifest;save();print('built',key,flush=True)
declared=historical['schematic_declared']
for p in P:
 for backend in ('qbe','llvm'):
  key=p['id']+'|'+backend;runs={s:PC.run_spec(p,W/(s+'.'+backend),'managed-readonly-'+s+'-'+backend,declared) for s in C}
  checks={s:M.checked(p,r) for s,r in runs.items()};assert all(c['ok'] for c in checks.values()),checks
  observations={s:[] for s in C}
  for repetition in range(3):
   for side in (('before','after') if repetition%2==0 else ('after','before')):
    receipt=M.counters(runs[side]);observations[side].append(receipt);assert receipt['ok'],receipt
  medians={s:statistics.median(r['instructions'] for r in rows) for s,rows in observations.items()}
  gc=historical['samples'][key]['medians']['gc']['instructions']
  D['samples'][key]={'checks':checks,'runs':{s:M.receipt(r) for s,r in runs.items()},'observations':observations,
                     'medians':medians,'after_before':medians['after']/medians['before'],'accepted_gc':gc,'after_gc':medians['after']/gc}
  save();print(key,D['samples'][key]['after_before'],D['samples'][key]['after_gc'],flush=True)
  for side in C:
   run=PC.run_spec(p,W/(side+'.'+backend+'.stats'),'managed-readonly-counted-'+side+'-'+backend,declared)
   run['argv']=['taskset','-c','10',*run['argv']]
   checked=M.checked(p,run);assert checked['ok'],checked
   counts=[json.loads(s.split(' ',1)[1]) for s in checked['stderr'].splitlines() if s.startswith('MYLANG_RC_COUNTS ')]
   assert len(counts)==1,checked
   n=counts[0]
   assert not n['saturated'] and n['hold_acquire']==n['hold_release']
   assert n['heap_allocate']==n['retire'] and n['owner_release']==n['owner_acquire']+n['heap_allocate']
   D['counted'][key+'|'+side]={'check':checked,'counts':n,'run':M.receipt(run)};save()
assert A.inputs()==D['inputs']
assert all(A.sha(c)==D['compilers'][s]['sha256'] for s,c in C.items())
assert all(A.sha(jobs[k]['bin'])==b['sha256'] for k,b in D['builds'].items())
D['complete']=True;save()

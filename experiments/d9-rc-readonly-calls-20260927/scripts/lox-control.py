from pathlib import Path
import concurrent.futures,importlib.util,json,os,statistics
R=Path.cwd();W=R/'.tmp-readonly/lox-control';W.mkdir(exist_ok=True)
P=R.parent/'d9-rc-performance'
spec=importlib.util.spec_from_file_location('core',P/'experiments/d9-rc-ownership-joined-20260927/measurement_core.py')
M=importlib.util.module_from_spec(spec);spec.loader.exec_module(M);M.CPU=2;A,PC=M.A,M.PC
os.environ['TMPDIR']=str(R/'.tmp-readonly/tmp');os.environ['ZIG_LOCAL_CACHE_DIR']=str(R/'.zig-cache-readonly-guests')
C=R/'.tmp-readonly/install-after/bin/mylang'
old=A.WORK/'ownership-joined-e5d47d20';prior=json.loads((old/'results.json').read_text())
p=next(p for p in A.programs() if p['id']=='lox/vm/binary_trees')
D={'compiler_sha256':A.sha(C),'driver_sha256':A.sha(__file__),'cpu':2,'inputs':A.inputs(),'program':p,
   'builds':{},'samples':{},'counted':{},'diagnostic_only':True,'rss_measured':False}
def save():A.write(W/'results.json',D)
jobs={}
for backend in ('qbe','llvm'):
 for stats in (False,True):
  key=backend+('.stats' if stats else '');binary=W/key
  command,cwd=PC.build_command(p,str(C),backend,binary,W/'cache')
  command+=['--rc-runtime=stats' if stats else '--rc-runtime']
  jobs[key]={'bin':binary,'cmd':[str(R/'scripts/build-slot.sh'),'build',*command],'cwd':cwd}
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
 pending={pool.submit(PC.do_build,job):key for key,job in jobs.items()}
 for future in concurrent.futures.as_completed(pending):
  key=pending[future];D['builds'][key]=future.result();save();assert D['builds'][key]['ok'],D['builds'][key]
  D['builds'][key]['manifest']=json.loads(Path(str(jobs[key]['bin'])+'.qbe-manifest.json').read_text());save();print('built',key,flush=True)
for backend in ('qbe','llvm'):
 key=p['build_key']+'.'+backend
 bins={'before':old/'bin'/key,'after':W/backend}
 assert A.sha(bins['before'])==prior['builds'][key]['sha256']
 runs={s:PC.run_spec(p,b,'readonly-lox-'+s+'-'+backend) for s,b in bins.items()}
 checks={s:M.checked(p,r) for s,r in runs.items()};assert all(c['ok'] for c in checks.values()),checks
 observations={s:[] for s in bins}
 for repetition in range(3):
  for side in (('before','after') if repetition%2==0 else ('after','before')):
   row=M.counters(runs[side]);observations[side].append(row);assert row['ok'],row
 medians={s:statistics.median(r['instructions'] for r in rows) for s,rows in observations.items()}
 gc=prior['samples'][p['id']+'|'+backend]['medians']['gc']['instructions']
 D['samples'][backend]={'checks':checks,'observations':observations,'medians':medians,'runs':{s:M.receipt(r) for s,r in runs.items()},
                        'before_binary_sha256':A.sha(bins['before']),'after_before':medians['after']/medians['before'],'accepted_gc':gc,'after_gc':medians['after']/gc}
 save();print('measured',backend,D['samples'][backend]['after_before'],D['samples'][backend]['after_gc'],flush=True)
 for side,binary in [('before',old/'bin'/(key+'.stats')),('after',W/(backend+'.stats'))]:
  run=PC.run_spec(p,binary,'readonly-lox-counted-'+side+'-'+backend);run['argv']=['taskset','-c','2',*run['argv']]
  check=M.checked(p,run);assert check['ok'],check
  counts=[json.loads(s.split(' ',1)[1]) for s in check['stderr'].splitlines() if s.startswith('MYLANG_RC_COUNTS ')]
  assert len(counts)==1,check
  n=counts[0];assert not n['saturated'] and n['heap_allocate']==n['retire'] and n['owner_release']==n['owner_acquire']+n['heap_allocate'] and n['hold_acquire']==n['hold_release']
  D['counted'][backend+'|'+side]={'check':check,'counts':n,'run':M.receipt(run),'binary_sha256':A.sha(binary)};save()
assert A.inputs()==D['inputs'] and A.sha(C)==D['compiler_sha256']
D['complete']=True;save()

from pathlib import Path
import os,json,hashlib,subprocess
r=Path.cwd();w=r/'.tmp-rc/dict-tail';e={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};e['TMPDIR']=str(r/'.tmp-rc/tmp')
d={'runs':[]}
for case,trap,output in [('growth','R_MEMORY_BUDGET','before\n'),('overflow','R_OVERFLOW','7\n'),('steps','R_STEP_LIMIT','before\n'),('arena','R_LIST_BOUNDS','7\n')]:
 for backend in ('qbe','llvm'):
  for side in ('before','after'):
   c=r/f'.tmp-rc/install-dict-tail-{side}/bin/mylang'
   for mode in ('gc','rc'):
    b=w/f'{case}-{side}-{mode}-{backend}';cmd=[str(r/'scripts/build-slot.sh'),'build',str(c),'build',str(w/'controls'/f'{case}.my'),'-o',str(b),'--cache-dir='+str(w/f'control-cache-{side}'),'--backend='+backend,'--mode=Debug','--rc-runtime=stats' if mode=='rc' else '--gc-runtime']
    if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
    p=subprocess.run(cmd,env=e,text=True,capture_output=True);row=dict(case=case,side=side,backend=backend,mode=mode,compiler_sha256=hashlib.sha256(c.read_bytes()).hexdigest(),build=cmd,build_status=p.returncode,build_stderr=p.stderr);d['runs'].append(row);(w/'controls.json').write_text(json.dumps(d,indent=2)+'\n');assert p.returncode==0,row
    manifest=json.loads(Path(str(b)+'.qbe-manifest.json').read_text());assert manifest['backend']==backend;row['manifest']=manifest
    run_env=dict(e);run_env['MYLANG_MEMORY_LIMIT']='1M' if case=='growth' else '128M';run_env['MYLANG_OPTIONS']=' '.join(x for x in ['--gc-stress' if mode=='gc' else '', '--max-steps=150' if case=='steps' else ''] if x)
    p=subprocess.run([str(b)],env=run_env,text=True,capture_output=True,timeout=60);row.update(status=p.returncode,stdout=p.stdout,stderr=p.stderr,binary_sha256=hashlib.sha256(b.read_bytes()).hexdigest(),environment={k:v for k,v in run_env.items() if k.startswith('MYLANG_')});(w/'controls.json').write_text(json.dumps(d,indent=2)+'\n');assert p.returncode==1 and trap in p.stderr and p.stdout==output,row
    if mode=='rc':
     counts=json.loads(next(x.removeprefix('MYLANG_RC_COUNTS ') for x in p.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')));row['counts']=counts;assert counts['heap_allocate']==counts['retire'] and counts['hold_acquire']==counts['hold_release'] and counts['owner_acquire']+counts['heap_allocate']==counts['owner_release'],row
    (w/'controls.json').write_text(json.dumps(d,indent=2)+'\n');print(case,backend,side,mode,'pass',flush=True)

from pathlib import Path
import subprocess,json,hashlib,os,re
r=Path.cwd();w=r/'.tmp-rc/nonheld';env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'}
env['TMPDIR']=str(r/'.tmp-rc/tmp')
cs={'before':r.parent/'d9-rc-integration/.tmp-rc/install-append-compose-scalar/bin/mylang','after':r/'.tmp-rc/install-nonheld-final/bin/mylang'}
d={'compilers':{k:{'path':str(c),'sha256':hashlib.sha256(c.read_bytes()).hexdigest()} for k,c in cs.items()},'runs':[]}
# Optional continuation of the recorded partial run; fresh replay runs all cases.
if os.environ.get('NONHELD_RESUME'):d=json.loads((w/'controls-partial-json.json').read_text())
def save():(w/'controls.json').write_text(json.dumps(d,indent=2)+'\n')
for name in ['positive','bounds','overflow','arena','steps','iteration']:
 for backend in ['qbe','llvm']:
  for side,c in cs.items():
   for mode in ['rc','gc']:
    if any(a['case']==name and a['backend']==backend and a['side']==side and a['mode']==mode and 'status' in a for a in d['runs']):continue
    b=w/f'{name}-{side}-{backend}-{mode}';cmd=[str(r/'scripts/build-slot.sh'),'build',str(c),'build',str(w/'controls'/f'{name}.my'),'-o',str(b),'--cache-dir='+str(w/f'controls-cache-{side}'),'--rc-runtime=stats' if mode=='rc' else '--gc-runtime']
    if name=='steps':
     cmd+=['--backend',backend,'--mode','Debug']
     if backend=='llvm':cmd+=['--llvm-opt','3','--lto']
    else:cmd+=['--release'] if backend=='llvm' else ['--mode','ReleaseFast']
    p=subprocess.run(cmd,env=env,text=True,capture_output=True);row=dict(case=name,backend=backend,side=side,mode=mode,build_command=cmd,build_status=p.returncode,build_stderr=p.stderr);d['runs'].append(row);save();assert p.returncode==0,row
    e=dict(env)
    if name=='steps':e['MYLANG_OPTIONS']='--max-steps=500'
    if mode=='gc':e['MYLANG_OPTIONS']=e.get('MYLANG_OPTIONS','')+' --gc-stress'
    p=subprocess.run([str(b)],env=e,text=True,capture_output=True,timeout=60);row.update(status=p.returncode,stdout=p.stdout,stderr=p.stderr,binary_sha256=hashlib.sha256(b.read_bytes()).hexdigest(),environment={k:v for k,v in e.items() if k.startswith('MYLANG_')});save()
    if name=='positive':assert p.returncode==0 and p.stdout=='',row
    else:
     code={'overflow':'R_OVERFLOW','bounds':'R_LIST_BOUNDS','arena':'R_LIST_BOUNDS','steps':'R_STEP_LIMIT','iteration':'R_LIST_ITERATION_MUTATION'}[name]
     assert p.returncode==1 and code in p.stderr and p.stdout=='entered\n',row
    if mode=='rc':
     counts=json.loads(next(x.removeprefix('MYLANG_RC_COUNTS ') for x in p.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')));row['counts']=counts
     assert counts['heap_allocate']==counts['retire'] and counts['owner_acquire']+counts['heap_allocate']==counts['owner_release'] and counts['hold_acquire']==counts['hold_release'],row
    save();print(name,backend,side,mode,'pass',flush=True)

for name in ['positive','bounds','overflow','arena','steps','iteration']:
 for backend in ['qbe','llvm']:
  pair=[a['counts'] for a in d['runs'] if a['case']==name and a['backend']==backend and a['mode']=='rc']
  assert pair[0]==pair[1],(name,backend,pair)

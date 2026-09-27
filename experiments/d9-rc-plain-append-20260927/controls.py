from pathlib import Path
import subprocess,json,hashlib,os,re
r=Path.cwd();w=r/'.tmp-rc/append-room';env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'}
cs={'before':r.parent/'d9-rc-integration/.tmp-rc/install-plain-loan-hoist/bin/mylang','after':r/'.tmp-rc/install-append-room/bin/mylang'}
d={'compilers':{k:{'path':str(c),'sha256':hashlib.sha256(c.read_bytes()).hexdigest()} for k,c in cs.items()},'runs':[]}
def save():(w/'controls.json').write_text(json.dumps(d,indent=2)+'\n')
resume=os.environ.get('APPEND_ROOM_RESUME')
if resume:
 d=json.loads((w/'controls-discard.json').read_text());d['runs']=[a for a in d['runs'] if a['case']!='iteration']
for name in (['iteration'] if resume else ['growth','zero','overflow','bounds','iteration']):
 for backend in ['qbe','llvm']:
  for side,c in cs.items():
   for mode in ['rc','gc']:
    b=w/f'{name}-{side}-{backend}-{mode}';cmd=[str(r/'scripts/build-slot.sh'),'build',str(c),'build',str(w/'controls'/f'{name}.my'),'-o',str(b),'--cache-dir='+str(w/f'controls-cache-{side}'),'--rc-runtime=stats' if mode=='rc' else '--gc-runtime']
    cmd+=['--release'] if backend=='llvm' else ['--mode','ReleaseFast']
    p=subprocess.run(cmd,env=env,text=True,capture_output=True);row=dict(case=name,backend=backend,side=side,mode=mode,build_command=cmd,build_status=p.returncode,build_stderr=p.stderr);d['runs'].append(row);save();assert p.returncode==0,row
    e=dict(env)
    if name in ['growth','zero']:e['MYLANG_MEMORY_LIMIT']='1M'
    if mode=='gc':e['MYLANG_OPTIONS']='--gc-stress'
    p=subprocess.run([str(b)],env=e,text=True,capture_output=True,timeout=60);row.update(status=p.returncode,stdout=p.stdout,stderr=p.stderr,binary_sha256=hashlib.sha256(b.read_bytes()).hexdigest(),environment={k:v for k,v in e.items() if k.startswith('MYLANG_')});save()
    if name=='zero':assert p.returncode==0 and p.stdout=='entered\n4\n',row
    else:
     code={'growth':'R_MEMORY_BUDGET','overflow':'R_OVERFLOW','bounds':'R_LIST_BOUNDS','iteration':'R_LIST_ITERATION_MUTATION'}[name]
     assert p.returncode==1 and code in p.stderr and p.stdout=='entered\n',row
    if mode=='rc':
     counts=json.loads(next(x.removeprefix('MYLANG_RC_COUNTS ') for x in p.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')));row['counts']=counts
     assert counts['heap_allocate']==counts['retire'] and counts['owner_acquire']+counts['heap_allocate']==counts['owner_release'] and counts['hold_acquire']==counts['hold_release'],row
    save();print(name,backend,side,mode,'pass',flush=True)

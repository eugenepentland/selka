from pathlib import Path
import os,json,subprocess,hashlib
root=Path.cwd();w=root/'.tmp-field';compiler=w/'install-final/bin/mylang';env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(w/'tmp'),ZIG_LOCAL_CACHE_DIR=str(w/'failure-zig-cache'))
r={'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'runs':[]}
def save():(w/'failures-final.json').write_text(json.dumps(r,indent=2)+'\n')
for name in ('trap','arena_trap','budget'):
 for backend in ('qbe','llvm'):
  for mode in ('gc','rc'):
   binary=w/f'{name}-final-{mode}-{backend}';source=w/f'controls/{name}.my'
   command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build',str(source),'-o',str(binary),'--cache-dir',str(w/'failure-cache'),f'--backend={backend}']
   if backend=='llvm':command+=['--llvm-opt=3','--lto']
   if mode=='rc':command+=['--rc-runtime=stats']
   done=subprocess.run(command,env=env,text=True,capture_output=True)
   row=dict(case=name,mode=mode,backend=backend,build_command=command,build_exit=done.returncode,build_stderr=done.stderr);r['runs'].append(row);save();assert done.returncode==0,row
   e=dict(env);e['MYLANG_MEMORY_LIMIT']='1M' if name=='budget' else '128M'
   if mode=='gc':e['MYLANG_OPTIONS']='--gc-stress'
   done=subprocess.run([str(binary)],env=e,text=True,capture_output=True,timeout=30)
   row.update(exit=done.returncode,stdout=done.stdout,stderr=done.stderr,binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),environment={k:v for k,v in e.items() if k.startswith('MYLANG_')});save()
   expected='R_MEMORY_BUDGET' if name=='budget' else 'R_LIST_BOUNDS'
   assert done.returncode==1 and expected in done.stderr,row
   assert done.stdout==('entered\n' if name=='budget' else 'start0\n' if name=='arena_trap' else 'start\n'),row
   if mode=='rc':
    c=json.loads(next(s.removeprefix('MYLANG_RC_COUNTS ') for s in done.stderr.splitlines() if s.startswith('MYLANG_RC_COUNTS ')));row['counts']=c
    assert c['heap_allocate']==c['retire'] and c['owner_acquire']+c['heap_allocate']==c['owner_release'] and c['hold_acquire']==c['hold_release'],row
   save();print(name,mode,backend,'pass',row.get('counts',{}),flush=True)

from pathlib import Path
import hashlib,json,os,subprocess,signal,time
root=Path.cwd();w=root/'.tmp-argv';previous=root.parent/'d9-rc-plain-replace-astra/.tmp-lox';port=previous/'port';before=root.parent/'d9-rc-integration/.tmp-rc/install-nbody/bin/mylang';after=w/'install/bin/mylang'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(w/'tmp'),ZIG_LOCAL_CACHE_DIR=str(w/'lox-zig-cache'),MYLANG_MEMORY_LIMIT='8G')
r={'compilers':{arm:{'path':str(c),'sha256':sha(c)} for arm,c in [('before',before),('after',after)]},'builds':[],'runs':[]}
def save(): (w/'lox.json').write_text(json.dumps(r,indent=2)+'\n')
for backend in ('qbe','llvm'):
 for arm,compiler in [('before',before),('after',after)]:
  binary=w/f'lox-{arm}-{backend}'
  command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build','main.my','--project','-o',str(binary),'--cache-dir',str(w/'lox-cache'),'--rc-runtime=stats',f'--backend={backend}']
  if backend=='llvm':command+=['--llvm-opt=3','--lto']
  built=subprocess.run(command,cwd=port,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env)
  r['builds'].append(dict(arm=arm,backend=backend,command=command,cwd=str(port),exit=built.returncode,stdout=built.stdout,stderr=built.stderr));save();assert built.returncode==0,built.stderr
  manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());assert manifest['backend']==backend
  for name,args in [('usage',[]),('empty',['--engine=vm',str(previous/'empty.lox')]),('n4',['--engine=vm',str(previous/'binary_trees_n4.lox')]),('n5',['--engine=vm',str(previous/'binary_trees_n5.lox')])]:
   cmd=['taskset','-c','3',str(binary),*args];start=time.monotonic();p=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env,start_new_session=True);expired=False
   try:out,err=p.communicate(timeout=15)
   except subprocess.TimeoutExpired:
    expired=True;os.killpg(p.pid,signal.SIGTERM)
    try:out,err=p.communicate(timeout=1)
    except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);out,err=p.communicate()
   row=dict(arm=arm,backend=backend,case=name,command=cmd,exit=p.returncode,stdout=out,stderr=err,timeout=expired,wall_seconds=time.monotonic()-start,binary_sha256=sha(binary),manifest_backend=manifest['backend'])
   if not expired:
    c=json.loads(next(s.removeprefix('MYLANG_RC_COUNTS ') for s in err.splitlines() if s.startswith('MYLANG_RC_COUNTS ')));row.update(counts=c,live_allocations=c['heap_allocate']-c['retire'],live_owners=c['heap_allocate']+c['owner_acquire']-c['owner_release'])
   r['runs'].append(row);save();print(arm,backend,name,row['exit'],row.get('live_allocations'),row.get('live_owners'),flush=True)
   assert not expired,row
   assert p.returncode==(64 if name=='usage' else 0),row
   if arm=='after':
    ref=next(x for x in r['runs'] if x['arm']=='before' and x['backend']==backend and x['case']==name)
    assert out==ref['stdout'],row
    assert not row['live_allocations'] and not row['live_owners'] and c['hold_acquire']==c['hold_release'],row

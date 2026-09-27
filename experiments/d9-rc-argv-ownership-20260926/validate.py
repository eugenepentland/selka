from pathlib import Path
import hashlib,json,os,subprocess,signal,time
root=Path.cwd();w=root/'.tmp-argv';before=root.parent/'d9-rc-integration/.tmp-rc/install-nbody/bin/mylang';after=w/'install/bin/mylang'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(w/'tmp'),ZIG_LOCAL_CACHE_DIR=str(w/'guest-zig-cache'),MYLANG_MEMORY_LIMIT='8G')
r={'compiler':{arm:{'path':str(c),'sha256':sha(c)} for arm,c in [('before',before),('after',after)]},'builds':[],'runs':[]}
def save(): (w/'validation.json').write_text(json.dumps(r,indent=2)+'\n')
def run(cmd,environment,limit=10):
 p=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=environment,start_new_session=True);expired=False
 try:out,err=p.communicate(timeout=limit)
 except subprocess.TimeoutExpired:
  expired=True;os.killpg(p.pid,signal.SIGTERM)
  try:out,err=p.communicate(timeout=1)
  except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);out,err=p.communicate()
 return dict(command=cmd,exit=p.returncode,stdout=out,stderr=err,timeout=expired)
cases=[('empty',[],{},0,'0\n'),('nonzero',['return'],{},7,'1\n1 2\n'),('trap',['trap'],{},1,'1\n'),('missing',['file',str(w/'absent')],{},23,'2\n'),('file',['file',str(w/'driver/empty.txt')],{},0,'2\n'),('many',['héllo']*257,{},7,'257\n257 258\n'),('capability',['return'],{'MYLANG_OPTIONS':'--restrict'},2,''),('frames',['return'],{'MYLANG_OPTIONS':'--max-frames=1'},None,None)]
for backend in ('qbe','llvm'):
 for arm,compiler in [('before',before),('after',after)]:
  for mode in ('rc','gc'):
   if mode=='gc' and arm=='before':continue
   binary=w/f'{arm}-{backend}-{mode}'
   command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build',str(w/'driver/entry.my'),'-o',str(binary),'--cache-dir',str(w/'cache'),f'--backend={backend}']
   if mode=='rc':command+=['--rc-runtime=stats']
   if backend=='llvm':command+=['--llvm-opt=3','--lto']
   built=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env)
   r['builds'].append(dict(arm=arm,backend=backend,mode=mode,command=command,exit=built.returncode,stdout=built.stdout,stderr=built.stderr));save();assert built.returncode==0,built.stderr
   manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());assert manifest['backend']==backend
   for name,args,extra,expected,stdout in cases:
    environment=env|({'MYLANG_OPTIONS':'--gc-stress'} if mode=='gc' else {})|extra
    row=run([str(binary),*args],environment);row.update(arm=arm,backend=backend,mode=mode,case=name,binary_sha256=sha(binary),environment=extra,manifest_backend=manifest['backend'])
    counts=[json.loads(s.removeprefix('MYLANG_RC_COUNTS ')) for s in row['stderr'].splitlines() if s.startswith('MYLANG_RC_COUNTS ')]
    if mode=='rc':
     assert len(counts)==1,row
     c=counts[0];row.update(counts=c,live_allocations=c['heap_allocate']-c['retire'],live_owners=c['heap_allocate']+c['owner_acquire']-c['owner_release'])
    r['runs'].append(row);save();print(arm,backend,mode,name,row['exit'],row.get('live_allocations'),row.get('live_owners'),flush=True)
    assert not row['timeout'],row
    if expected is not None:assert row['exit']==expected and row['stdout']==stdout,row
    if mode=='rc' and arm=='after':assert not row['live_allocations'] and not row['live_owners'] and c['hold_acquire']==c['hold_release'] and not c['saturated'],row

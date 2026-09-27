from pathlib import Path
import os, json, subprocess, hashlib
root=Path.cwd(); w=root/'.tmp-arena-snapshot'; compiler=w/'install/bin/mylang'
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'}
env.update(TMPDIR=str(w/'tmp'), ZIG_LOCAL_CACHE_DIR=str(w/'guest-zig'), MYLANG_MEMORY_LIMIT='128M')
r={'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'runs':[]}
def save(): (w/'guests.json').write_text(json.dumps(r,indent=2)+'\n')
cases=[('snapshots',root/'tests/lang/record_field_snapshots.my','True\n'*8),('scalar',root/'tests/lang/rc_plain_record_writes.my','True\n'*6),('minimal',root/'.tmp-plain-record/arena-minimal.my','[12]\n[12, 14]\n'),('heap',w/'heap.my','[12]\n[12, 14]\n'),('diagnostic',root/'.tmp-plain-record/arena-diagnostic.my','11\nFalse\n8\nTrue\n[12]\n[12, 14]\n')]
for backend in ('qbe','llvm'):
 for mode in ('gc','rc'):
  for name,src,expected in cases:
   binary=w/f'{name}-{mode}-{backend}'
   cmd=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build',str(src),'-o',str(binary),'--cache-dir',str(w/'cache'),f'--backend={backend}']
   if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
   if mode=='rc':cmd+=['--rc-runtime=stats']
   d=subprocess.run(cmd,env=env,capture_output=True,text=True)
   row=dict(name=name,mode=mode,backend=backend,source_sha256=hashlib.sha256(src.read_bytes()).hexdigest(),command=cmd,build_exit=d.returncode,build_stderr=d.stderr,expected=expected);r['runs'].append(row);save();assert d.returncode==0,row
   row['manifest']=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());assert row['manifest']['backend']==backend
   runenv=dict(env)
   if mode=='gc':runenv['MYLANG_OPTIONS']='--gc-stress'
   d=subprocess.run([str(binary)],env=runenv,capture_output=True,text=True,timeout=30)
   row.update(exit=d.returncode,stdout=d.stdout,stderr=d.stderr,binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest());save();print(name,mode,backend,repr(d.stdout),d.returncode,flush=True)
   assert d.returncode==0 and d.stdout==expected,row
   if mode=='rc':
    c=json.loads(next(x.removeprefix('MYLANG_RC_COUNTS ') for x in d.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')));row['counts']=c
    assert not c['saturated'] and c['heap_allocate']==c['retire'] and c['owner_acquire']+c['heap_allocate']==c['owner_release'] and c['hold_acquire']==c['hold_release'],row
   save()

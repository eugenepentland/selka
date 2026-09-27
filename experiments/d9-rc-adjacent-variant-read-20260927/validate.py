from pathlib import Path
import os,json,subprocess,hashlib,time
root=Path.cwd(); w=root/'.tmp-variant-read'
before=root.parent/'d9-rc-integration/.tmp-rc/install-snapshot-joined/bin/mylang'
after=w/'install/bin/mylang'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'}
env.update(TMPDIR=str(w/'tmp'),ZIG_LOCAL_CACHE_DIR=str(w/'guest-zig-cache'),MYLANG_MEMORY_LIMIT='128M')
r={'before_sha256':sha(before),'after_sha256':sha(after),'runs':[]}
def save():(w/'validation.json').write_text(json.dumps(r,indent=2)+'\n')
for arm,compiler in [('before',before),('after',after)]:
 for backend in ['qbe','llvm']:
  for mode in ['gc','rc']:
   binary=w/f'guest-{arm}-{mode}-{backend}'
   cmd=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build','tests/lang/rc_variant_reads.my','-o',str(binary),'--cache-dir',str(w/f'guest-cache-{arm}'),f'--backend={backend}']
   if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
   if mode=='rc':cmd+=['--rc-runtime=stats']
   d=subprocess.run(cmd,env=env,text=True,capture_output=True)
   row=dict(arm=arm,backend=backend,mode=mode,build_command=cmd,build_exit=d.returncode,build_stderr=d.stderr);r['runs'].append(row);save();assert d.returncode==0,row
   row['manifest']=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());assert row['manifest']['backend']==backend
   runenv=env|({'MYLANG_OPTIONS':'--gc-stress'} if mode=='gc' else {})
   d=subprocess.run([str(binary)],env=runenv,text=True,capture_output=True,timeout=30)
   row.update(exit=d.returncode,stdout=d.stdout,stderr=d.stderr,binary_sha256=sha(binary),run_command=[str(binary)],environment={k:v for k,v in runenv.items() if k.startswith('MYLANG_')});save()
   assert d.returncode==0 and d.stdout=='True\n'*8,row
   if mode=='rc':
    c=json.loads(next(x.removeprefix('MYLANG_RC_COUNTS ') for x in d.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')));row['counts']=c
    assert c['heap_allocate']==c['retire'] and c['owner_acquire']+c['heap_allocate']==c['owner_release'] and c['hold_acquire']==c['hold_release'] and not c['saturated'],row
   save();print('PASS',arm,mode,backend,flush=True)

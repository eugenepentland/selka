from pathlib import Path
import os,json,subprocess,hashlib
root=Path.cwd();w=root/'.tmp-plain-record';env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(w/'tmp'),ZIG_LOCAL_CACHE_DIR=str(w/'guest-zig-cache'),MYLANG_MEMORY_LIMIT='128M');r={'runs':[]}
def save():(w/'arena-diagnostic.json').write_text(json.dumps(r,indent=2)+'\n')
for arm,compiler in [('before',root.parent/'d9-rc-integration/.tmp-rc/install-append-compose-scalar/bin/mylang'),('after',w/'install-final/bin/mylang')]:
 for backend in ('qbe','llvm'):
  for mode in ('gc','rc'):
   binary=w/f'arena-diagnostic-{arm}-{mode}-{backend}';cmd=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build',str(w/'arena-diagnostic.my'),'-o',str(binary),'--cache-dir',str(w/'arena-diag-cache'),f'--backend={backend}']
   if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
   if mode=='rc':cmd+=['--rc-runtime=stats']
   d=subprocess.run(cmd,env=env,capture_output=True,text=True);row=dict(arm=arm,mode=mode,backend=backend,compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),command=cmd,build_exit=d.returncode,build_stderr=d.stderr);r['runs'].append(row);save();assert d.returncode==0,row
   row['manifest']=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());assert row['manifest']['backend']==backend
   e=dict(env)
   if mode=='gc':e['MYLANG_OPTIONS']='--gc-stress'
   d=subprocess.run([str(binary)],env=e,capture_output=True,text=True,timeout=30);row.update(exit=d.returncode,stdout=d.stdout,stderr=d.stderr,binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest());save();print(arm,mode,backend,repr(d.stdout),d.returncode,flush=True)
   assert d.returncode==0,row

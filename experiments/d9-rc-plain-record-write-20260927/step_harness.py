from pathlib import Path
import os,subprocess,json,hashlib
root=Path.cwd();w=root/'.tmp-plain-record';compiler=w/'install/bin/mylang'
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(w/'tmp'),ZIG_LOCAL_CACHE_DIR=str(w/'guest-zig-cache'),MYLANG_MEMORY_LIMIT='128M')
r={'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'runs':[]}
def save():(w/'step-harness.json').write_text(json.dumps(r,indent=2)+'\n')
c=['cc','-O2','-I',str(root/'src'),str(w/'step_harness.c'),'-ldl','-o',str(w/'step_harness')];d=subprocess.run(c,capture_output=True,text=True);assert d.returncode==0,d.stderr
for arm in ('before','after'):
 compiler=root.parent/'d9-rc-integration/.tmp-rc/install-append-compose-scalar/bin/mylang' if arm=='before' else w/'install/bin/mylang'
 for backend in ('qbe','llvm'):
  for mode in ('gc','rc'):
   library=w/f'step-{arm}-{mode}-{backend}.so'
   cmd=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build',str(root/'.tmp-lox-projection-audit/plain-update.my'),'--library','--mode=Debug','-o',str(library),'--cache-dir',str(w/'step-cache'),f'--backend={backend}']
   if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
   if mode=='rc':cmd+=['--rc-runtime=stats']
   d=subprocess.run(cmd,env=env,text=True,capture_output=True);row=dict(arm=arm,compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),mode=mode,backend=backend,command=cmd,build_exit=d.returncode,build_stdout=d.stdout,build_stderr=d.stderr);r['runs'].append(row);save();assert d.returncode==0,row
   manifest=json.loads(Path(str(library)+'.qbe-manifest.json').read_text());row['manifest']=manifest;assert manifest['backend']==backend
   symbol=next(f['symbol'] for f in manifest['functions'] if f['name']=='update')
   c=[str(w/'step_harness'),str(library),symbol,str(18 if mode=='gc' else 19)];d=subprocess.run(c,env=env,text=True,capture_output=True,timeout=30);row.update(run=c,exit=d.returncode,stdout=d.stdout,stderr=d.stderr,binary_sha256=hashlib.sha256(library.read_bytes()).hexdigest());save();assert d.returncode==0,row
   print(arm,mode,backend,d.stdout.strip(),flush=True)

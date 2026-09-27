from pathlib import Path
import os, json, subprocess, hashlib, time, re
root=Path.cwd(); w=root/'.tmp-named-record'; port=root/'.tmp-plain-record/lox-guest'
compilers={'before':root.parent/'d9-rc-integration/.tmp-rc/install-ownership-joined-fixed/bin/mylang','after':w/'install-frozen/bin/mylang'}
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'}
env.update(TMPDIR=str(w/'tmp'),ZIG_LOCAL_CACHE_DIR=str(w/'guest-zig-cache'),MYLANG_MEMORY_LIMIT='8G')
for arm,compiler in compilers.items():
 r={'compiler':str(compiler),'compiler_sha256':sha(compiler),'sources':{str(p.relative_to(port)):sha(p) for p in sorted(port.glob('*.my'))},'builds':[]}
 def save():(w/f'lox-{arm}-builds.json').write_text(json.dumps(r,indent=2)+'\n')
 for backend in ['qbe','llvm']:
  for counted in [False,True]:
   binary=w/f'lox-{arm}-{backend}-{int(counted)}'
   cmd=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build','main.my','--project','-o',str(binary),'--cache-dir',str(w/f'lox-{arm}-cache'),f'--backend={backend}','--keep-symbols',('--rc-runtime=stats' if counted else '--rc-runtime')]
   if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
   t=time.monotonic();d=subprocess.run(cmd,cwd=port,env=env,text=True,capture_output=True)
   row=dict(backend=backend,counted=counted,command=cmd,exit=d.returncode,stderr=d.stderr,seconds=time.monotonic()-t)
   r['builds'].append(row);save();assert d.returncode==0,row
   row['binary_sha256']=sha(binary);row['manifest']=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());assert row['manifest']['backend']==backend;save();print('BUILD',arm,backend,counted,round(row['seconds'],2),flush=True)

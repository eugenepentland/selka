from pathlib import Path
import os,subprocess,json,hashlib
root=Path.cwd();w=root/'.tmp-mut-argument/scalar-readiness-prototype';guest=root/'.tmp-mut-argument/type-facts/measure/guest';out=w/'lox';out.mkdir(exist_ok=True)
e={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};e.update(TMPDIR=str(w),MYLANG_MEMORY_LIMIT='8G')
compilers={'before':root.parent/'d9-rc-readiness-before-astra/.tmp-readiness/install/bin/mylang','after':w/'install/bin/mylang'}
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();path=out/'builds.json';d=json.loads(path.read_text()) if path.exists() else {'builds':[]}
for side,c in compilers.items():
 for backend in ('qbe','llvm'):
  for counted in (False,True):
   if any(r['side']==side and r['backend']==backend and r['counted']==counted for r in d['builds']):continue
   binary=out/(side+'-'+backend+('-stats' if counted else '-production'));cmd=[root/'scripts/build-slot.sh','build',c,'build','main.my','--project','-o',binary,'--cache-dir',out/('cache-'+side),'--backend='+backend,'--keep-symbols','--rc-runtime'+('=stats' if counted else '')]
   if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
   p=subprocess.run(list(map(str,cmd)),cwd=guest,env=e,capture_output=True,text=True,timeout=600);row={'side':side,'backend':backend,'counted':counted,'command':list(map(str,cmd)),'cwd':str(guest),'compiler_sha256':sha(c),'status':p.returncode,'stderr':p.stderr,'binary':str(binary)};d['builds'].append(row);path.write_text(json.dumps(d,indent=2)+'\n');assert p.returncode==0,row
   row.update(binary_sha256=sha(binary),manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text()));assert row['manifest']['backend']==backend;path.write_text(json.dumps(d,indent=2)+'\n');print(side,backend,counted,flush=True)

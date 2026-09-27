from pathlib import Path
import os,json,hashlib,subprocess
r=Path.cwd();w=r/'.tmp-mut-argument/scalar-readiness-prototype';c=w/'install/bin/mylang';e={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};e['TMPDIR']=str(w);d=[]
for backend in ('qbe','llvm'):
 for name in ('rc_append_loops','rc_plain_appends'):
  source=r/'tests/lang'/(name+'.my');cmd=[str(r/'scripts/build-slot.sh'),'build',str(c),'run',str(source),'--gc-stress','--cache-dir='+str(w/'gc-cache')]
  if backend=='llvm':cmd+=['--release']
  p=subprocess.run(cmd,env=e,text=True,capture_output=True,timeout=300);row={'backend':backend,'case':name,'command':cmd,'compiler_sha256':hashlib.sha256(c.read_bytes()).hexdigest(),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr};d.append(row);(w/'gc-controls.json').write_text(json.dumps(d,indent=2)+'\n');assert p.returncode==0,row;print(backend,name,'passed',flush=True)

"""Paired actual backend controls for registry identity reuse."""
import hashlib,json,os,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp-mut-argument/descriptor-repeat/validation';work.mkdir(exist_ok=True)
compilers={'before':root.parent/'d9-rc-integration/.tmp-rc/install-flat-retain-joined/bin/mylang','after':root/'.tmp-mut-argument/descriptor-repeat/install/bin/mylang'}
cases=['rc_plain_appends','rc_semantic_history','dictionary_views','rc_aggregate_values','iteration_identity']
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env['TMPDIR']=str(root/'.tmp-mut-argument/descriptor-repeat')
path=work/'results.json';data=json.loads(path.read_text()) if path.exists() else {'compilers':{k:{'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for k,p in compilers.items()},'runs':[]}
def save():path.write_text(json.dumps(data,indent=2)+'\n')
for side,compiler in compilers.items():
 for backend in ('qbe','llvm'):
  for name in cases:
   if any(x['side']==side and x['backend']==backend and x['case']==name for x in data['runs']):continue
   source=root/'tests/lang'/f'{name}.my';assert source.exists(),source
   command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'test',str(source),'--rc-runtime=stats','--cache-dir='+str(work/('cache-'+side))]
   if backend=='llvm':command+=['--release']
   p=subprocess.run(command,env=env,text=True,capture_output=True,timeout=1800);row={'side':side,'backend':backend,'case':name,'command':command,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr};data['runs'].append(row);save();assert p.returncode==0,row;print(side,backend,name,p.stdout.strip(),flush=True)

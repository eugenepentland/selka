import hashlib,json,os,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp-checker';compiler=root/'zig-out/bin/mylang'
record={'base_commit':'7998e84c','compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'runs':{}}
for backend in ('qbe','llvm'):
 for runtime in ('gc','rc'):
  for fixture in ('exact','change'):
   source=work/(fixture+'.my')
   command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'run',str(source),'--cache-dir='+str(work/'guest-cache')]+(['--release'] if backend=='llvm' else [])+(['--rc-runtime=stats'] if runtime=='rc' else [])
   p=subprocess.run(command,env=dict(os.environ,TMPDIR=str(work)),capture_output=True,text=True,timeout=600)
   key=backend+'/'+runtime+'/'+fixture
   record['runs'][key]={'command':command,'source':source.read_text(),'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
   (work/'probes.json').write_text(json.dumps(record,indent=2)+'\n')
   print(key,p.returncode,repr(p.stdout),flush=True)
   if fixture=='exact':assert p.returncode==0 and p.stdout=='[13]\n13\n7\n',(key,p.stdout,p.stderr)

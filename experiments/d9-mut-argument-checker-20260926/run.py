import hashlib,json,os,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp-checker';compiler=root/'zig-out/bin/mylang'
record={'base_commit':'7998e84c','compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'runs':{}}
env=dict(os.environ,TMPDIR=str(work),ZIG_LOCAL_CACHE_DIR=str(root/'.zig-cache-checker'))
for backend in ('qbe','llvm'):
 for runtime in ('gc','rc'):
  for fixture in ('mut_dictionary_arguments','mut_reference_roots','mut_rebinding'):
   command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'test',f'tests/lang/{fixture}.my','--force','--json','--jobs=2','--cache-dir='+str(work/'guest-cache')]+(['--release'] if backend=='llvm' else [])+(['--rc-runtime=stats'] if runtime=='rc' else [])
   p=subprocess.run(command,env=env,capture_output=True,text=True,timeout=600)
   key=backend+'/'+runtime+'/'+fixture
   record['runs'][key]={'command':command,'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
   (work/'guests.json').write_text(json.dumps(record,indent=2)+'\n')
   print(key,p.returncode,p.stdout,flush=True)
   assert p.returncode==0,(key,p.stdout,p.stderr)

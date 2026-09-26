import json,subprocess,os,hashlib
from pathlib import Path
root=Path.cwd();work=root/'.tmp-schematic/drop-guard';compiler=root/'zig-out/bin/mylang'
env=dict(os.environ,TMPDIR=str(root/'.tmp-schematic/tmp'),ZIG_LOCAL_CACHE_DIR=str(root/'.zig-cache-schematic'))
result={'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'runs':{}}
for backend in ('qbe','llvm'):
 for name in ('rc_aggregate_values','rc_capability_values','recursive_values'):
  command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'test',f'tests/lang/{name}.my','--rc-runtime=stats','--force','--json','--jobs=2']+(['--release'] if backend=='llvm' else [])
  p=subprocess.run(command,env=env,capture_output=True,text=True);data=json.loads(p.stdout);result['runs'][backend+'/'+name]={'command':command,'exit':p.returncode,'result':data,'stderr':p.stderr}
  (work/'guests.json').write_text(json.dumps(result,indent=2)+'\n')
  assert p.returncode==0 and len(data['tests'])>0 and all(t['status']=='passed' for t in data['tests']),(backend,name,p.stdout,p.stderr)
  print(backend,name,len(data['tests']),'passed',flush=True)

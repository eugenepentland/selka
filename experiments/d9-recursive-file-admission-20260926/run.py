import hashlib,json,os,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp-unique';compiler=root/'zig-out/bin/mylang'
record={'base_commit':'3b5f54b0','compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'runs':{}}
for backend in ('qbe','llvm'):
 for runtime in ('gc','rc'):
  flags=(['--release'] if backend=='llvm' else [])+(['--rc-runtime=stats'] if runtime=='rc' else ['--gc-runtime'])
  for fixture in ('unique_box_direct','acyclic_file'):
   source=work/(fixture+'.my');command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'run',str(source),'--cache-dir='+str(work/'cache')]+flags
   p=subprocess.run(command,env=dict(os.environ,TMPDIR=str(work)),capture_output=True,text=True,timeout=600)
   key=backend+'/'+runtime+'/'+fixture;record['runs'][key]={'command':command,'source':source.read_text(),'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
   (work/'probes.json').write_text(json.dumps(record,indent=2)+'\n');print(key,p.returncode,repr(p.stdout),repr(p.stderr[-300:]),flush=True)
  for fixture in ('rc_contract_results','recursive_values'):
   command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'test',f'tests/lang/{fixture}.my','--force','--json','--jobs=2','--cache-dir='+str(work/'cache')]+flags
   p=subprocess.run(command,env=dict(os.environ,TMPDIR=str(work)),capture_output=True,text=True,timeout=600)
   key=backend+'/'+runtime+'/'+fixture;record['runs'][key]={'command':command,'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
   (work/'probes.json').write_text(json.dumps(record,indent=2)+'\n');print(key,p.returncode,flush=True)
   assert p.returncode==0,(key,p.stdout,p.stderr)

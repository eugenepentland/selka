import hashlib,json,os,subprocess
from pathlib import Path
root=Path.cwd();compiler=root/'zig-out/bin/mylang';work=root/'.tmp-schematic/history-guests';rows={}
identity={'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'source_base':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'source_sha256':hashlib.sha256((root/'tests/lang/rc_semantic_history.my').read_bytes()).hexdigest(),'runs':rows}
for backend in ('qbe','llvm'):
 for mode in ('gc','rc'):
  key=f'{backend}-{mode}';command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'test','tests/lang/rc_semantic_history.my','--force','--json','--jobs=2']
  command+=['--gc-runtime','--gc-stress'] if mode=='gc' else ['--rc-runtime=stats']
  if backend=='llvm':command+=['--release']
  run=subprocess.run(command,env=dict(os.environ,TMPDIR=str(root/'.tmp-schematic/tmp')),capture_output=True)
  (work/(key+'.json')).write_bytes(run.stdout);(work/(key+'.log')).write_bytes(run.stderr)
  result=json.loads(run.stdout);rows[key]={'command':command,'exit':run.returncode,'result':result}
  (work/'results.json').write_text(json.dumps(identity,indent=2)+'\n')
  print(key,result['passed'],result['failed'],flush=True)
assert hashlib.sha256(compiler.read_bytes()).hexdigest()==identity['compiler_sha256']
assert hashlib.sha256((root/'tests/lang/rc_semantic_history.my').read_bytes()).hexdigest()==identity['source_sha256']

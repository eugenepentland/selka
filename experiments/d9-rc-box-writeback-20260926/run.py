import hashlib,json,os,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp-box';source=root/'tests/lang/rc_box_writeback.my';rows={}
compilers={'before':root.parent/'d9-rc-integration/.tmp-rc/install-compact/bin/mylang','after':root/'zig-out/bin/mylang'}
result={'source':source.read_text(),'compiler_sha256':{k:hashlib.sha256(v.read_bytes()).hexdigest() for k,v in compilers.items()},'runs':rows}
for side,compiler in compilers.items():
 for backend in ('qbe','llvm'):
  for mode in ('gc','rc'):
   key=f'{side}-{backend}-{mode}';command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'test',str(source),'--force','--json','--jobs=2']
   command+=['--gc-runtime','--gc-stress'] if mode=='gc' else ['--rc-runtime=stats']
   if backend=='llvm':command+=['--release']
   run=subprocess.run(command,capture_output=True,env=dict(os.environ,TMPDIR=str(work/'tmp')));d=json.loads(run.stdout)
   rows[key]={'command':command,'exit':run.returncode,'stderr':run.stderr.decode(errors='replace'),'result':d};(work/'results.json').write_text(json.dumps(result,indent=2)+'\n')
   print(key,d['passed'],d['failed'],flush=True)
   if side=='after' or mode=='gc':assert d['passed']==5 and not d['failed'],rows[key]

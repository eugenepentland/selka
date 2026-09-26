import hashlib,json,os,subprocess
from pathlib import Path
root=Path.cwd();w=root/'.tmp-repeat';before=Path('/home/epentland/ai/canopy/mylang-worktrees/d9-rc-integration/.tmp-rc/install-compact/bin/mylang');after=root/'zig-out/bin/mylang'
result={'compilers':{n:hashlib.sha256(p.read_bytes()).hexdigest() for n,p in [('before',before),('after',after)]},'runs':{}}
for version,compiler in [('before',before),('after',after)]:
 for backend in ('qbe','llvm'):
  for fixture in ('permanent','rc_box_writeback'):
   command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'run',str(w/(fixture+'.my')),'--gc-runtime','--gc-stress','--cache-dir='+str(w/'validation-cache')]+(['--release'] if backend=='llvm' else [])
   p=subprocess.run(command,capture_output=True,text=True,env=dict(os.environ,TMPDIR=str(w)),timeout=600)
   key=f'{version}/{backend}/{fixture}';result['runs'][key]={'command':command,'source':(w/(fixture+'.my')).read_text(),'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
   (w/'validation.json').write_text(json.dumps(result,indent=2)+'\n');print(key,p.returncode,repr(p.stdout),flush=True)
   if version=='after':assert p.returncode==0 and 'False' not in p.stdout,(key,p.stdout,p.stderr)

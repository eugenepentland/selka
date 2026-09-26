import hashlib,json,os,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp-repeat';compiler=Path('/home/epentland/ai/canopy/mylang-worktrees/d9-rc-integration/.tmp-rc/install-compact/bin/mylang')
result={'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'runs':{}}
for backend in ('qbe','llvm'):
 for name in ('rc_box_writeback','repeat'):
  for accounted in (False,True):
   command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'run',str(work/(name+'.my')),'--gc-runtime','--gc-stress','--cache-dir='+str(work/'before-cache')]+(['--release'] if backend=='llvm' else [])+(['--max-steps=100000'] if accounted else [])
   p=subprocess.run(command,capture_output=True,text=True,env=dict(os.environ,TMPDIR=str(work)),timeout=600)
   key=f'{backend}/{name}/{accounted}';result['runs'][key]={'command':command,'source':(work/(name+'.my')).read_text(),'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
   (work/'before-corrected.json').write_text(json.dumps(result,indent=2)+'\n');print(key,p.returncode,repr(p.stdout),flush=True)

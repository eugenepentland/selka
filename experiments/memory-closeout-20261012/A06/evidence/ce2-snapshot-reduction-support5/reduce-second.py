from pathlib import Path
import subprocess,os,json,time,hashlib
root=Path(__file__).resolve().parent
compiler=Path('/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/memory-closeout/coordinator/support5-install/bin/mylang')
cache=root.parent/'support5-migration-native-ce2/cache'
def run(name,argv,env=None):
 t=time.monotonic();p=subprocess.run(argv,capture_output=True,text=True,env=env,timeout=120)
 row=dict(argv=list(map(str,argv)),status=p.returncode,stdout=p.stdout,stderr=p.stderr,elapsed_s=time.monotonic()-t)
 (root/(name+'.json')).write_text(json.dumps(row,indent=2)+'\n')
 print(name,p.returncode,repr(p.stdout[:500]),repr(p.stderr[:300]),flush=True)
 return p
for stem in ['minimal-original','minimal-slim','minimal-wide','minimal-wide-no-increment','minimal-wide-inline']:
 out=root/stem
 p=run(stem+'-build',[str(compiler),'build',str(out)+'.my','--zig',os.environ['ZIG'],'--cache-dir',str(cache),'--release','--experimental-zero-rc','--counters','-o',str(out),'--emit-llvm',str(out)+'.ll'])
 if p.returncode==0:run(stem+'-run',[str(out)],dict(os.environ,MYLANG_COUNTERS=str(out)+'-counts.json'))
for stem in ['prefix3','minimal-wide']:
 p=run(stem+'-facts',[str(compiler),'dump-ir',str(root/(stem+'.my')),'--facts','--experimental-zero-rc'])
 (root/(stem+'-facts.txt')).write_text(p.stdout)

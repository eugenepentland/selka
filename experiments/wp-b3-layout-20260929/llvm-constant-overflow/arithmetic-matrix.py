import hashlib,json,os,subprocess
from pathlib import Path
w=Path(__file__).resolve().parent.parent;d=w/'.tmp/arithmetic-final';d.mkdir(exist_ok=True);tool=w/'.tmp/constant-final/bin/mylang';records=[]
for name,flags in [('rc',[]),('gc',['--gc-runtime']),('stress',['--gc-stress']),('release',['--release']),('gc-release',['--gc-runtime','--release']),('stats',['--rc-runtime=stats'])]:
 e={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_')};e.update(TMPDIR=str(w/'.tmp'),ZIG_LOCAL_CACHE_DIR=str(w/'.zig-local-cache'),ZIG_GLOBAL_CACHE_DIR=str(w/'.zig-global-cache'))
 cmd=[str(w/'scripts/build-slot.sh'),'build',str(tool),'test',str(w/'tests/lang/checked_arithmetic.my'),'--json','--force','--cache-dir='+str(d/('stats-counting' if name=='stats' else name)/'cache')]+flags
 r=subprocess.run(cmd,env=e,capture_output=True);(d/(name+'.out')).write_bytes(r.stdout);(d/(name+'.err')).write_bytes(r.stderr);record={'name':name,'command':cmd,'status':r.returncode,'stdout':r.stdout.decode(),'stderr_sha256':hashlib.sha256(r.stderr).hexdigest()};records.append(record);(d/'receipt.json').write_text(json.dumps({'compiler_sha256':hashlib.sha256(tool.read_bytes()).hexdigest(),'runs':records},indent=2)+'\n');print(name,r.returncode,flush=True);assert r.returncode==0,r.stderr.decode()

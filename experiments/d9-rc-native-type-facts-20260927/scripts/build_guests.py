from pathlib import Path
import hashlib,json,os,shutil,subprocess,time
root=Path.cwd();work=root/'.tmp-mut-argument/type-facts/measure';work.mkdir(exist_ok=True);peer=root.parent/'d9-rc-lox-probe-astra';guest=work/'guest';shutil.copytree(peer/'.tmp-plain-record/lox-guest',guest,dirs_exist_ok=True)
compiler=root/'.tmp-mut-argument/type-facts/install/bin/mylang';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();assert sha(compiler)=='2db0563ac88bfacebbe5b7c7c599069b8b80b1e7c8acc9e1cdb3d53f9fe0f54a'
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(work),ZIG_LOCAL_CACHE_DIR=str(root.parent/'.d9-rc-mut-argument-zig-cache'),MYLANG_MEMORY_LIMIT='8G')
r={'source':'5b87601297f01810968b9f7ac554c484d5848cca + type-facts source.patch','compiler':str(compiler),'compiler_sha256':sha(compiler),'sources':{str(p.relative_to(guest)):sha(p) for p in guest.rglob('*.my')},'builds':[]}
for backend in ('qbe','llvm'):
 for counted in (False,True):
  binary=work/(backend+('-stats' if counted else '-production'));cmd=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build','main.my','--project','-o',str(binary),'--cache-dir',str(work/'cache'),f'--backend={backend}','--keep-symbols',('--rc-runtime=stats' if counted else '--rc-runtime')]
  if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
  print('START',backend,counted,flush=True);start=time.monotonic();p=subprocess.run(cmd,env=env,cwd=guest,capture_output=True,text=True,timeout=600);row={'command':cmd,'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr,'backend':backend,'counted':counted,'seconds':time.monotonic()-start};r['builds'].append(row);(work/'builds.json').write_text(json.dumps(r,indent=2)+'\n');assert p.returncode==0,row
  row.update(binary_sha256=sha(binary),manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text()));assert row['manifest']['backend']==backend;(work/'builds.json').write_text(json.dumps(r,indent=2)+'\n');print('DONE',backend,counted,round(row['seconds'],2),flush=True)

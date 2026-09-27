from pathlib import Path
import hashlib,json,os,subprocess
root=Path.cwd();work=root/'.tmp-rc-performance/fannkuch-7d68202d'
compiler=root.parent/'d9-rc-integration/.tmp-rc/install-scope-scalar/bin/mylang'
env=dict(os.environ,TMPDIR=str(root/'.tmp-rc-performance/tmp'),ZIG_LOCAL_CACHE_DIR=str(root/'.zig-cache-guests'))
source=root/'bench/parity/suite/fannkuch_redux.my';expected=source.with_suffix('.expected').read_bytes()
result={'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'commands':[],'profile_is_qualitative':True}
for mode in ('production','stats'):
 binary=work/mode
 command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build',str(source),'-o',str(binary),'--cache-dir='+str(work/'cache'),'--keep-symbols','--rc-runtime'+('=stats' if mode=='stats' else '')]
 done=subprocess.run(command,env=env,capture_output=True,timeout=1200);result['commands'].append({'command':command,'status':done.returncode,'stderr':done.stderr.decode()});assert done.returncode==0,done.stderr.decode()
 result[mode+'_sha256']=hashlib.sha256(binary.read_bytes()).hexdigest()
command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'emit-qbe',str(source),'--no-cache','--rc-runtime']
done=subprocess.run(command,env=env,capture_output=True,timeout=1200);assert done.returncode==0,done.stderr.decode();(work/'emitted.json').write_bytes(done.stdout)
done=subprocess.run([str(work/'stats')],env=env,capture_output=True,timeout=120);assert done.returncode==0 and done.stdout==expected
(work/'stats.stderr').write_bytes(done.stderr);result['counters']=[json.loads(line.split(b' ',1)[1]) for line in done.stderr.splitlines() if line.startswith(b'MYLANG_RC_COUNTS ')]
command=['perf','record','-e','instructions:u','-c','50000000','-g','-o',str(work/'profile.data'),'--','taskset','-c','1',str(work/'production')]
done=subprocess.run(command,env=env,capture_output=True,timeout=120);result['commands'].append({'command':command,'status':done.returncode,'stderr':done.stderr.decode()});assert done.returncode==0 and done.stdout==expected
report=subprocess.run(['perf','report','--stdio','--no-children','--sort','symbol','-i',str(work/'profile.data')],capture_output=True,check=True)
(work/'profile.txt').write_bytes(report.stdout)
(work/'identity.json').write_text(json.dumps(result,indent=2)+'\n')
print('profile complete',result['counters'],flush=True)

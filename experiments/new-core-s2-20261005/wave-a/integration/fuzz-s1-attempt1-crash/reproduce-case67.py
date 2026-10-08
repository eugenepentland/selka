import hashlib,json,os,subprocess,time
from pathlib import Path
ROOT=Path.cwd()
E=ROOT/'experiments/new-core-s2-20261005/wave-a/integration/fuzz-s1-crash'
SOURCE=ROOT/'experiments/new-core-s2-20261005/wave-a/integration/fuzz-s1/failures/records_unions_propagate_mut_alias67-5676f097b6ec.my'
results=[]
for variant in ('baseline','current'):
 compiler=ROOT/('.mylang-cache/wave-a/baseline/mylang-core' if variant=='baseline' else 'zig-out/bin/mylang-core')
 cache=ROOT/'.mylang-cache/wave-a/case67-repro'/variant
 for leaf in ('tmp','zig','frontend'):(cache/leaf).mkdir(parents=True,exist_ok=True)
 env=dict(os.environ,TMPDIR=str(cache/'tmp'),ZIG_LOCAL_CACHE_DIR=str(cache/'zig'),ZIG_GLOBAL_CACHE_DIR='/home/epentland/ai/canopy/.zig-global-cache',MYL_CORE_LEAKCHECK='1')
 for mode,flags in (('debug',[]),('release',['--release']),('verify',['--release','--verify-facts'])):
  binary=cache/mode
  command=[str(compiler),'build',str(SOURCE),'-o',str(binary),*flags,'--cache-dir',str(cache/'frontend'/mode),'--emit-llvm',str(E/f'{variant}-{mode}.ll')]
  started=time.monotonic()
  built=subprocess.run(command,capture_output=True,text=True,env=env,timeout=60)
  record={'variant':variant,'mode':mode,'compiler':str(compiler),'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'build_command':command,'build_exit':built.returncode,'build_seconds':time.monotonic()-started,'build_stdout':built.stdout,'build_stderr':built.stderr}
  if built.returncode==0:
   started=time.monotonic()
   ran=subprocess.run([str(binary),'37','4','999983'],capture_output=True,text=True,env=env,timeout=20)
   record.update(run_command=[str(binary),'37','4','999983'],exit=ran.returncode,stdout=ran.stdout,stderr=ran.stderr,run_seconds=time.monotonic()-started)
  results.append(record)
  (E/'reproduction.json').write_text(json.dumps({'source':str(SOURCE),'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'affinity':sorted(os.sched_getaffinity(0)),'results':results},indent=2)+'\n')
  print(json.dumps(record),flush=True)

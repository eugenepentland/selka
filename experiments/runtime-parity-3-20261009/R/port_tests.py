#!/usr/bin/env python3
"""Run the frozen Lox/EDA port tests with a stable copied Debug compiler."""
import argparse,gzip,hashlib,json,os,pathlib,shutil,subprocess,time
ROOT=pathlib.Path(__file__).resolve().parents[3]
p=argparse.ArgumentParser();p.add_argument('--compiler',type=pathlib.Path,required=True);p.add_argument('--tag',required=True);a=p.parse_args()
assert pathlib.Path(os.readlink('/proc/self/fd/9')).name.startswith('build')
work=ROOT/'.mylang-cache/rp3/R/port-tests'/a.tag;work.mkdir(parents=True,exist_ok=True);compiler=work/'compiler';shutil.copyfile(a.compiler.resolve(),compiler);compiler.chmod(0o755)
area=ROOT/'experiments/runtime-parity-3-20261009/R';receipt={'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'cells':[]}
jobs=[('lox',ROOT/'.mylang-cache/lox/ports/mylang','.',65,['--max-steps=100000000']),('eda',ROOT/'.mylang-cache/eda-src','src',310,['--max-frames=30000','--max-steps=4000000000','--max-memory=2G'])]
for name,cwd,path,expected,limits in jobs:
 command=[str(compiler),'test',path,'--jobs=4','--json','--cache-dir',str(work/(name+'-cache')),*limits];started=time.monotonic()
 done=subprocess.run(command,cwd=cwd,capture_output=True,env=dict(os.environ,MYLANG_CORE_RUNTIME_CACHE=str(work/'runtime')))
 for kind,data in [('stdout',done.stdout),('stderr',done.stderr)]:
  (area/f'{a.tag}-{name}-tests.{kind}.gz').write_bytes(gzip.compress(data,mtime=0))
 row={'program':name,'command':command,'cwd':str(cwd),'status':done.returncode,'seconds':time.monotonic()-started,'stdout_sha256':hashlib.sha256(done.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(done.stderr).hexdigest()};receipt['cells'].append(row)
 try:report=json.loads(done.stdout);row['summary']={k:report[k] for k in ('passed','cached','failed','skipped','unsupported')}
 except ValueError:report={}
 (area/(a.tag+'-port-tests.json')).write_text(json.dumps(receipt,indent=1))
 assert done.returncode==0 and row['summary']=={'passed':expected,'cached':0,'failed':0,'skipped':0,'unsupported':0},row
 print(name,expected,'passed; no cached results',flush=True)

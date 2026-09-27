"""Residual full-size gap versus immutable accepted GC, without corpus claims."""
import hashlib,json,os,statistics,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp-mut-argument/retain-run'
gc=root.parent/'d9-rc-performance/.tmp-rc-performance/bin/gc'
measured=json.loads((work/'measurement.json').read_text())
result={'cpu':2,'backends':{}}
def run(cmd):return subprocess.run(cmd,text=True,capture_output=True,check=True,env=dict(os.environ,TMPDIR=str(work)))
for backend in ('qbe','llvm'):
 binaries={'gc':gc/f'parity-micro-alloc_churn.{backend}','rc':work/f'alloc-churn-{backend}-after-rc'}
 samples=[]
 for repetition in range(3):
  for arm in (('gc','rc') if repetition%2==0 else ('rc','gc')):
   command=['taskset','-c','2','perf','stat','-x,','-e','instructions:u,cycles:u','--',str(binaries[arm])]
   done=run(command);assert done.stdout==measured['backends'][backend]['stdout']
   counters={f[2]:int(f[0]) for line in done.stderr.splitlines() if len(f:=line.split(','))>2 and f[0].isdigit()}
   samples.append(dict(command=command,arm=arm,counters=counters,stderr=done.stderr))
 medians={arm:statistics.median(s['counters']['cpu_core/instructions/u'] for s in samples if s['arm']==arm) for arm in binaries}
 result['backends'][backend]={'binaries':{a:{'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for a,p in binaries.items()},'samples':samples,'medians':medians,'rc_over_gc':medians['rc']/medians['gc']}
 (work/'residual.json').write_text(json.dumps(result,indent=2)+'\n');print(backend,medians,result['backends'][backend]['rc_over_gc'],flush=True)
 command=['perf','record','-q','-e','cpu_core/instructions/u','-F','199','-o',str(work/f'{backend}-after.data'),'--','taskset','-c','2',str(binaries['rc'])]
 done=run(command);assert done.stdout==measured['backends'][backend]['stdout']
 result['backends'][backend]['profile']={'command':command,'stderr':done.stderr}
 for suffix,args in [('samples.txt',['script','-F','ip,sym,dso,period']),('report.txt',['report','--stdio','--no-children','--sort','symbol,dso','--percent-limit','0.3']),('stats.txt',['report','--stdio','--stats'])]:
  done=run(['perf']+args+['-i',str(work/f'{backend}-after.data')]);(work/f'{backend}-after.{suffix}').write_text(done.stdout+done.stderr)
 (work/'residual.json').write_text(json.dumps(result,indent=2)+'\n')

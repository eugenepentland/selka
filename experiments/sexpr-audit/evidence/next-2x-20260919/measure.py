import hashlib,json,os,random,statistics,subprocess,time,sys
from pathlib import Path
W=Path(sys.argv[1]).resolve()
os.sched_setaffinity(0,{6})
phases={'read':('a_read','--read'),'tokens':('b_tokens','--tokens'),'parse':('c_parse','--parse'),'census':('census',None),'render':('census','--render'),'scan':('e_scan','--scan')}
report={'cpu':6,'runs':21,'clock':'perf_counter_ns; Python parent and children pinned before spawning; no taskset process per sample','binaries':{},'inputs':{},'results':{}}
for p in list((W/'bin').iterdir())+[W/v for v in ['census','a_read','b_tokens','c_parse','e_scan']]:
 report['binaries'][str(p.relative_to(W))]=hashlib.sha256(p.read_bytes()).hexdigest()
for inp in ['input.sexp','input8.sexp']:
 p=W/inp;report['inputs'][inp]={'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
 tasks={}
 for phase,(driver,mode) in phases.items():
  if inp=='input8.sexp' and phase not in ['census','render']:continue
  tasks[phase+' mylang']=[str(W/driver),str(p)]+(['--render'] if phase=='render' else [])
  tasks[phase+' zig']=[str(W/'bin/zig-bench'),str(p)]+([mode] if mode else [])
 tasks['true']=['/bin/true']
 values={k:[] for k in tasks};outputs={}
 for k,cmd in tasks.items():
  r=subprocess.run(cmd,capture_output=True,check=True);outputs[k]=r.stdout
 for phase in phases:
  if phase+' mylang' not in outputs:continue
  if phase=='tokens':
   assert int(outputs['tokens mylang'].split(b'=')[1])==int(outputs['tokens zig'].split(b'=')[1])+1
  else:assert outputs[phase+' mylang']==outputs[phase+' zig'],phase
 rng=random.Random(19)
 for i in range(21):
  order=list(tasks);rng.shuffle(order)
  for k in order:
   t=time.perf_counter_ns();r=subprocess.run(tasks[k],stdout=subprocess.PIPE,stderr=subprocess.PIPE);ms=(time.perf_counter_ns()-t)/1e6
   assert r.returncode==0 and r.stdout==outputs[k],k
   values[k].append(ms)
 result={k:{'median_ms':statistics.median(v),'min_ms':min(v),'samples_ms':v,'stdout_sha256':hashlib.sha256(outputs[k]).hexdigest()} for k,v in values.items()}
 report['results'][inp]=result
 print(inp,flush=True)
 for k,v in result.items():print(k,round(v['median_ms'],3),flush=True)
(W/'measurement.json').write_text(json.dumps(report,indent=2)+'\n')

from pathlib import Path
import os,subprocess,json,hashlib,time
r=Path.cwd();w=r/'.tmp-rc/append-room';p=w/'profile';env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'}
d={'source':'3bc671b710f50928a2704d0cc747232bd85be21d','cpu':10,'period':2000000,'runs':[]}
for name in ['append','sieve']:
 for backend in ['qbe','llvm']:
  binary=w/'full'/f'{name}-after-{backend}-rc';base=p/f'{name}-{backend}'
  cmd=['taskset','-c','10','perf','record','-e','instructions:u','-c','2000000','-o',str(base)+'.data','--',str(binary)]
  z=subprocess.run(cmd,env=env,text=True,capture_output=True);row={'case':name,'backend':backend,'binary':str(binary),'sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'command':cmd,'status':z.returncode,'stdout':z.stdout,'stderr':z.stderr};assert z.returncode==0,row
  cmd=['perf','report','--stdio','--no-children','-i',str(base)+'.data','--percent-limit','0.25'];z=subprocess.run(cmd,env=env,text=True,capture_output=True);assert z.returncode==0,z.stderr;(Path(str(base)+'.txt')).write_text(z.stdout);row['report_command']=cmd;row['report_stderr']=z.stderr
  cmd=['perf','script','-D','-i',str(base)+'.data'];z=subprocess.run(cmd,env=env,text=True,capture_output=True);assert z.returncode==0,z.stderr;row['throttle']=z.stdout.count('PERF_RECORD_THROTTLE');row['unthrottle']=z.stdout.count('PERF_RECORD_UNTHROTTLE')
  d['runs'].append(row);(p/'results.json').write_text(json.dumps(d,indent=2)+'\n');print(name,backend,'done',flush=True)

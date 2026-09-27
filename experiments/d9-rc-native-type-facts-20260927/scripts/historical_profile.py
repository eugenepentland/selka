from pathlib import Path
import json,hashlib,subprocess,os,time,collections,re
root=Path.cwd();work=root/'.tmp-mut-argument/lox-post-record';peer=root.parent/'d9-rc-lox-probe-astra';source=peer/'experiments/d9-rc-plain-record-write-20260927';script=root.parent/'d9-rc-performance/.tmp-rc-performance/lox-scripts/binary_trees.tree.lox';expected=(source/'expected-n10.txt').read_text()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(work),MYLANG_MEMORY_LIMIT='8G')
receipt={'source_commit':'6a75eb2a39686ccab91a981496f5520477abf34c','input':str(script),'input_sha256':sha(script),'cpu':2,'rows':[]}
for backend in ('qbe','llvm'):
 binary=peer/f'.tmp-plain-record/lox-after-{backend}-0';manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());assert manifest['backend']==backend
 data=work/f'{backend}.data';cmd=['taskset','-c','2','perf','record','-e','cpu_core/instructions/u','-c','50000000','-o',str(data),'--',str(binary),'--engine=vm',str(script)]
 print('START',backend,flush=True);start=time.monotonic();p=subprocess.run(cmd,env=env,capture_output=True,text=True,timeout=180);assert p.returncode==0 and p.stdout==expected,(p.returncode,p.stdout,p.stderr)
 row={'backend':backend,'binary':str(binary),'binary_sha256':sha(binary),'manifest':manifest,'command':cmd,'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr,'wall_seconds':time.monotonic()-start};receipt['rows'].append(row)
 s=subprocess.run(['perf','script','-i',str(data),'-F','period,ip,sym,dso'],capture_output=True,text=True,check=True);(work/f'{backend}.samples.txt').write_text(s.stdout);row['script_stderr']=s.stderr
 counts=collections.Counter();ips=collections.Counter();samples=0
 for line in s.stdout.splitlines():
  m=re.match(r'\s*(\d+)\s+([0-9a-f]+)\s+(.+)\s+\(([^()]*)\)\s*$',line)
  if m: counts[m[3]]+=int(m[1]);ips[m[2]]+=int(m[1]);samples+=1
 total=sum(counts.values());row['samples']=samples;row['sample_weight']=total;row['top_symbols']=[{'symbol':k,'weight':v,'percent':100*v/total} for k,v in counts.most_common(45)];row['top_ips']=ips.most_common(50)
 raw=subprocess.run(['perf','script','-D','-i',str(data)],capture_output=True,text=True,check=True);row['throttle']=raw.stdout.count('PERF_RECORD_THROTTLE');row['unthrottle']=raw.stdout.count('PERF_RECORD_UNTHROTTLE');row['lost']=raw.stdout.count('PERF_RECORD_LOST')
 (work/'results.json').write_text(json.dumps(receipt,indent=2)+'\n');print('DONE',backend,round(row['wall_seconds'],2),'samples',samples,'throttle',row['throttle'],'lost',row['lost'],flush=True)
 print(json.dumps(row['top_symbols'][:20],indent=2),flush=True)

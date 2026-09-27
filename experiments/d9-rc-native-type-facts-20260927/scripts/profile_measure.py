from pathlib import Path
import json,hashlib,subprocess,os,time,collections,re,sys
root=Path.cwd();work=root/'.tmp-mut-argument/lox-post-record/current';peer=root.parent/'d9-rc-lox-probe-astra';source=peer/'experiments/d9-rc-plain-record-write-20260927';script=root.parent/'d9-rc-performance/.tmp-rc-performance/lox-scripts/binary_trees.tree.lox';expected=(source/'expected-n10.txt').read_text();sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(work),MYLANG_MEMORY_LIMIT='8G');backend=sys.argv[1];binary=work/f'{backend}-production';data=work/f'{backend}.data';manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());assert manifest['backend']==backend
r={'source':'5b87601297f01810968b9f7ac554c484d5848cca','backend':backend,'binary':str(binary),'binary_sha256':sha(binary),'input':str(script),'input_sha256':sha(script),'manifest':manifest,'runs':[]}
def save():(work/f'{backend}-results.json').write_text(json.dumps(r,indent=2)+'\n')
def run(cmd):
 print('START',cmd[3:6],flush=True);start=time.monotonic();p=subprocess.run(cmd,env=env,capture_output=True,text=True,timeout=180);row={'command':cmd,'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr,'seconds':time.monotonic()-start};r['runs'].append(row);save();assert p.returncode==0 and p.stdout==expected,row;print('DONE',round(row['seconds'],2),flush=True);return row
row=run(['taskset','-c','2','perf','record','-e','cpu_core/instructions/u','-F','99','-j','any_call,u','-o',str(data),'--',str(binary),'--engine=vm',str(script)])
s=subprocess.run(['perf','script','-i',str(data),'-F','period,ip,sym,dso'],capture_output=True,text=True,check=True);(work/f'{backend}.samples.txt').write_text(s.stdout);row['script_stderr']=s.stderr
counts=collections.Counter();ips=collections.Counter()
for line in s.stdout.splitlines():
 m=re.match(r'\s*(\d+)\s+([0-9a-f]+)\s+(.+)\s+\(([^()]*)\)\s*$',line)
 if m: counts[m[3]]+=int(m[1]);ips[m[2]]+=int(m[1])
total=sum(counts.values());row['sample_weight']=total;row['top_symbols']=[{'symbol':k,'weight':v,'percent':100*v/total} for k,v in counts.most_common()];row['ips']=ips
raw=subprocess.run(['perf','script','-D','-i',str(data)],capture_output=True,text=True,check=True);row['throttle']=len(re.findall(r': PERF_RECORD_THROTTLE\b',raw.stdout));row['unthrottle']=len(re.findall(r': PERF_RECORD_UNTHROTTLE\b',raw.stdout));row['lost']=len(re.findall(r': PERF_RECORD_LOST\b',raw.stdout))
branches=subprocess.run(['perf','script','-i',str(data),'-F','period,ip,sym,dso,brstacksym'],capture_output=True,text=True,check=True);(work/f'{backend}.branches.txt').write_text(branches.stdout);save();print(json.dumps(row['top_symbols'][:15],indent=2),flush=True);print('throttle',row['throttle'],'lost',row['lost'],flush=True)
for repeat in range(3):
 row=run(['taskset','-c','2','perf','stat','-x,','-e','cpu_core/instructions/u','--',str(binary),'--engine=vm',str(script)]);p=next(x.split(',') for x in row['stderr'].splitlines() if ',cpu_core/instructions/u,' in x);row['instructions']=int(p[0]);row['event_running_percent']=float(p[4]);assert row['event_running_percent']==100;save();print('instructions',row['instructions'],flush=True)
stats=work/f'{backend}-stats';row=run(['taskset','-c','2',str(stats),'--engine=vm',str(script)]);row['binary_sha256']=sha(stats);c=json.loads(next(x.removeprefix('MYLANG_RC_COUNTS ') for x in row['stderr'].splitlines() if x.startswith('MYLANG_RC_COUNTS ')));assert not c['saturated'] and c['heap_allocate']==c['retire'] and c['owner_acquire']+c['heap_allocate']==c['owner_release'] and c['hold_acquire']==c['hold_release'];row['counts']=c;save();print(json.dumps(c),flush=True)

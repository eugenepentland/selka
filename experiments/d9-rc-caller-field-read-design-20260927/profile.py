from pathlib import Path
import collections, hashlib, json, os, re, subprocess, sys, time

root=Path.cwd(); work=root/'.tmp-mut-argument/caller-field-audit'; backend=sys.argv[1]
binary=root/'.tmp-mut-argument/field-list-read'/('proof-final-'+backend+'-production'); script=root.parent/'d9-rc-performance/.tmp-rc-performance/lox-scripts/binary_trees.tree.lox'
expected=(root/'experiments/d9-rc-plain-record-write-20260927/expected-n10.txt').read_text()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'}
env.update(TMPDIR=str(root.parent/'.d9-rc-mut-argument-tmp'),MYLANG_MEMORY_LIMIT='8G')
manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text()); assert manifest['backend']==backend
result={'source':'c1224f30','backend':backend,'binary':str(binary),'binary_sha256':sha(binary),'input':str(script),'input_sha256':sha(script),'manifest':manifest,'runs':[]}
def save():(work/(backend+'-results.json')).write_text(json.dumps(result,indent=2)+'\n')
def run(cmd):
    print('START',cmd[:8],flush=True);start=time.monotonic();p=subprocess.run(cmd,env=env,capture_output=True,text=True,timeout=600)
    row={'command':cmd,'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr,'seconds':time.monotonic()-start};result['runs'].append(row);save()
    assert p.returncode==0 and p.stdout==expected,row
    print('DONE',round(row['seconds'],2),flush=True);return row
data=work/(backend+'.data')
row=run(['taskset','-c','3','perf','record','-e','cpu_core/instructions/u','-c','500000000','-j','any_call,u','-o',str(data),'--',str(binary),'--engine=vm',str(script)])
for suffix,fields in [('samples','period,ip,sym,dso'),('branches','period,ip,sym,dso,brstacksym')]:
    p=subprocess.run(['perf','script','-i',str(data),'-F',fields],capture_output=True,text=True,check=True)
    (work/(backend+'.'+suffix+'.txt')).write_text(p.stdout)
    row[suffix+'_stderr']=p.stderr
p=subprocess.run(['perf','script','-D','-i',str(data)],capture_output=True,text=True,check=True)
row['throttle']=len(re.findall(r': PERF_RECORD_THROTTLE\b',p.stdout));row['unthrottle']=len(re.findall(r': PERF_RECORD_UNTHROTTLE\b',p.stdout));row['lost']=len(re.findall(r': PERF_RECORD_LOST\b',p.stdout))
(work/(backend+'.perf-raw.txt')).write_text(p.stdout)
hits=collections.Counter();weighted=collections.Counter()
for line in (work/(backend+'.samples.txt')).read_text().splitlines():
    m=re.match(r'\s*(\d+)\s+([0-9a-f]+)\s+(.+)\s+\(([^()]*)\)\s*$',line)
    if m:hits[m[3]]+=1;weighted[m[3]]+=int(m[1])
row['attribution']='qualitative only' if row['throttle'] or row['lost'] else 'fixed-period retired-instruction sampling; approximate'
row['symbols']=[{'symbol':k,'hits':v,'period_sum':weighted[k]} for k,v in hits.most_common()];save()
print('PROFILE',row['attribution'],'throttle',row['throttle'],'lost',row['lost'],row['symbols'][:15],flush=True)

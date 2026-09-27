from pathlib import Path
import json,os,subprocess,hashlib,statistics,time
r=Path.cwd();w=r/'.tmp-mut-argument/field-list-read';inp=r.parent/'d9-rc-performance/.tmp-rc-performance/lox-scripts/binary_trees.tree.lox';expected=(r/'experiments/d9-rc-plain-record-write-20260927/expected-n10.txt').read_text()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(r.parent/'.d9-rc-mut-argument-tmp'),MYLANG_MEMORY_LIMIT='8G')
d={'input':str(inp),'input_sha256':sha(inp),'runs':[],'summary':{}}
def save():(w/'paired-results.json').write_text(json.dumps(d,indent=2)+'\n')
def run(side,backend,counted,rep):
 binary=w/(('final-' if side=='after' else '')+backend+('-stats' if counted else '-production'))
 manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());assert manifest['backend']==backend
 cmd=['taskset','-c','3']+([] if counted else ['perf','stat','-x,','-e','cpu_core/instructions/u','--'])+[str(binary),'--engine=vm',str(inp)]
 start=time.monotonic();p=subprocess.run(cmd,env=env,capture_output=True,text=True,timeout=600)
 row={'side':side,'backend':backend,'counted':counted,'repeat':rep,'command':cmd,'binary':str(binary),'sha256':sha(binary),'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr,'seconds':time.monotonic()-start};d['runs'].append(row);save();assert not p.returncode and p.stdout==expected,row
 if counted:
  c=json.loads(next(line[len('MYLANG_RC_COUNTS '):] for line in p.stderr.splitlines() if line.startswith('MYLANG_RC_COUNTS ')));row['counts']=c
  assert not c['saturated'] and c['heap_allocate']==c['retire'] and c['heap_allocate']+c['owner_acquire']==c['owner_release'] and c['hold_acquire']==c['hold_release']
 else:
  values=next(line.split(',') for line in p.stderr.splitlines() if ',cpu_core/instructions/u,' in line);assert float(values[4])==100;row['instructions']=int(values[0]);row['event_running_percent']=float(values[4])
 save();print(side,backend,'counts' if counted else rep,row.get('instructions',row.get('counts')),flush=True)
for backend in ('qbe','llvm'):
 for rep in range(3):
  for side in (('before','after') if rep%2==0 else ('after','before')):run(side,backend,False,rep)
 for side in ('before','after'):run(side,backend,True,0)
 samples={side:[x['instructions'] for x in d['runs'] if x['backend']==backend and x['side']==side and not x['counted']] for side in ('before','after')}
 med={k:statistics.median(v) for k,v in samples.items()};gc={'qbe':7243227886,'llvm':3433157037}[backend]
 d['summary'][backend]={'samples':samples,'medians':med,'after_before':med['after']/med['before'],'accepted_gc_archival_median':gc,'before_gc':med['before']/gc,'after_gc':med['after']/gc};save();print('SUMMARY',backend,d['summary'][backend],flush=True)

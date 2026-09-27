from pathlib import Path
import os,json,subprocess,hashlib,signal,time
root=Path.cwd();w=root/'.tmp-plain-record';perf=root.parent/'d9-rc-performance/.tmp-rc-performance';script=perf/'lox-scripts/binary_trees.tree.lox';expected=(perf/'lox/bench/expected/binary_trees.tree.out').read_text();built=json.loads((w/'lox.json').read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(w/'tmp'),MYLANG_MEMORY_LIMIT='8G')
r={'input':str(script),'input_sha256':sha(script),'expected_sha256':hashlib.sha256(expected.encode()).hexdigest(),'control_compiler':built['before_sha256'],'candidate_compiler':built['after_sha256'],'runs':[]}
def save():(w/'full.json').write_text(json.dumps(r,indent=2)+'\n')
for backend in ('qbe','llvm'):
 for counted in (True,False):
  for repeat in range(1 if counted else 3):
   for arm in ('before','after'):
    binary=w/f'lox-{arm}-{backend}-{int(counted)}';manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());assert manifest['backend']==backend
    cmd=['taskset','-c','3']+([] if counted else ['perf','stat','-x,','-e','cpu_core/instructions/u','--'])+[str(binary),'--engine=vm',str(script)]
    print('START',backend,counted,repeat,arm,flush=True)
    p=subprocess.Popen(cmd,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True);expired=False;start=time.monotonic()
    try:out,err=p.communicate(timeout=240)
    except subprocess.TimeoutExpired:
     expired=True;os.killpg(p.pid,signal.SIGTERM)
     try:out,err=p.communicate(timeout=1)
     except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);out,err=p.communicate()
    row=dict(arm=arm,backend=backend,counted=counted,repeat=repeat,command=cmd,exit=p.returncode,stdout=out,stderr=err,timeout=expired,wall_seconds=time.monotonic()-start,binary_sha256=sha(binary));r['runs'].append(row);save();assert not expired and p.returncode==0 and out==expected,row
    if counted:
     c=json.loads(next(s.removeprefix('MYLANG_RC_COUNTS ') for s in err.splitlines() if s.startswith('MYLANG_RC_COUNTS ')));row['counts']=c;assert not c['saturated'] and c['heap_allocate']==c['retire'] and c['owner_acquire']+c['heap_allocate']==c['owner_release'] and c['hold_acquire']==c['hold_release'],row
    else:
     parts=next(s.split(',') for s in err.splitlines() if ',cpu_core/instructions/u,' in s);row.update(instructions=int(parts[0]),event_runtime_ns=int(parts[3]),event_running_percent=float(parts[4]));assert row['event_running_percent']==100.0,row
    save();print('DONE',backend,counted,repeat,arm,round(row['wall_seconds'],3),row.get('counts',row.get('instructions')),flush=True)
print('COMPLETE',flush=True)

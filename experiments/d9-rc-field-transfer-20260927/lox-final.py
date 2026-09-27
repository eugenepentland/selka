from pathlib import Path
import os,json,subprocess,hashlib,signal,time
root=Path.cwd();w=root/'.tmp-field';previous=root.parent/'d9-rc-plain-replace-astra/.tmp-lox';port=previous/'port';compiler=w/'install-final/bin/mylang';original=json.loads((w/'lox.json').read_text());perf=root.parent/'d9-rc-performance/.tmp-rc-performance'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(w/'tmp'),ZIG_LOCAL_CACHE_DIR=str(w/'lox-zig-cache'),MYLANG_MEMORY_LIMIT='8G')
r={'compiler':str(compiler),'compiler_sha256':sha(compiler),'builds':[],'runs':[],'n10_script':str(perf/'lox-scripts/binary_trees.tree.lox'),'n10_script_sha256':sha(perf/'lox-scripts/binary_trees.tree.lox'),'n10_expected_sha256':sha(perf/'lox/bench/expected/binary_trees.tree.out')}
def save():(w/'lox-final.json').write_text(json.dumps(r,indent=2)+'\n')
def bounded(cmd,seconds):
 p=subprocess.Popen(cmd,env=env,cwd=perf,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True);expired=False;start=time.monotonic()
 try:out,err=p.communicate(timeout=seconds)
 except subprocess.TimeoutExpired:
  expired=True;os.killpg(p.pid,signal.SIGTERM)
  try:out,err=p.communicate(timeout=1)
  except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);out,err=p.communicate()
 return dict(command=cmd,exit=p.returncode,stdout=out,stderr=err,timeout=expired,wall_seconds=time.monotonic()-start)
for backend in ('qbe','llvm'):
 for counted in (True,False):
  binary=w/f'lox-final-{backend}-{int(counted)}'
  cmd=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build','main.my','--project','-o',str(binary),'--cache-dir',str(w/'lox-cache-final'),f'--backend={backend}','--keep-symbols',('--rc-runtime=stats' if counted else '--rc-runtime')]
  if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
  done=subprocess.run(cmd,env=env,cwd=port,capture_output=True,text=True)
  row=dict(backend=backend,counted=counted,command=cmd,exit=done.returncode,stdout=done.stdout,stderr=done.stderr);r['builds'].append(row);save();assert done.returncode==0,row
  row.update(binary_sha256=sha(binary),manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text()));assert row['manifest']['backend']==backend
  old=next(x for x in original['builds'] if x['arm']=='after' and x['backend']==backend and x['counted']==counted)
  row['prototype_binary_identical']=row['binary_sha256']==old['binary_sha256'];save();print('BUILD',backend,counted,'identical',row['prototype_binary_identical'],flush=True)
  for n in (4,5,10):
   script=perf/'lox-scripts/binary_trees.tree.lox' if n==10 else previous/f'binary_trees_n{n}.lox'
   cmd=['taskset','-c','3']+([] if counted else ['perf','stat','-x,','-e','cpu_core/instructions/u','--'])+[str(binary),'--engine=vm',str(script)]
   run=bounded(cmd,120 if n==10 else 15);run.update(backend=backend,counted=counted,n=n);r['runs'].append(run);save()
   expected=(perf/'lox/bench/expected/binary_trees.tree.out').read_text() if n==10 else next(x['stdout'] for x in original['runs'] if x['arm']=='after' and x['backend']==backend and x['n']==n)
   if run['timeout']:print('TIMEOUT',backend,counted,n,flush=True);continue
   assert run['exit']==0 and run['stdout']==expected,run
   if counted:
    c=json.loads(next(s.removeprefix('MYLANG_RC_COUNTS ') for s in run['stderr'].splitlines() if s.startswith('MYLANG_RC_COUNTS ')));run['counts']=c
    assert not c['saturated'] and c['heap_allocate']==c['retire'] and c['owner_acquire']+c['heap_allocate']==c['owner_release'] and c['hold_acquire']==c['hold_release'],run
    if n!=10:assert c==next(x['counts'] for x in original['runs'] if x['arm']=='after' and x['backend']==backend and x['counted'] and x['n']==n),run
   else:run['instructions']=int(next(s.split(',')[0] for s in run['stderr'].splitlines() if ',cpu_core/instructions/u,' in s))
   save();print('RUN',backend,counted,n,round(run['wall_seconds'],3),run.get('counts',run.get('instructions')),flush=True)
print('COMPLETE',flush=True)

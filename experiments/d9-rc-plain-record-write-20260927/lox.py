from pathlib import Path
import os,json,subprocess,hashlib,signal,time,statistics
root=Path.cwd();w=root/'.tmp-plain-record';port=w/'lox-guest';before=root.parent/'d9-rc-integration/.tmp-rc/install-append-compose-scalar/bin/mylang';after=w/'install-final/bin/mylang';previous=root.parent/'d9-rc-plain-replace-astra/.tmp-lox';reference=json.loads((root/'.tmp-field/lox.json').read_text())['runs']
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(w/'tmp'),ZIG_LOCAL_CACHE_DIR=str(w/'guest-zig-cache'),MYLANG_MEMORY_LIMIT='8G')
assert len(json.loads((w/'step-harness.json').read_text())['runs'])==8
assert len(json.loads((w/'traps.json').read_text())['runs'])==16
assert sha(before)=='082edf36c3b1370debeccb4bdcbf3069fbf7829ad1852e8a7d0d5d7f2a34c67e'
assert sha(after)==sha(w/'install/bin/mylang')
r={'baseline_commit':'468bd8e536b0e088ff71291cb9a3c92db8ebf448','before_compiler':str(before),'before_sha256':sha(before),'after_compiler':str(after),'after_sha256':sha(after),'builds':[],'runs':[]}
def save():(w/'lox.json').write_text(json.dumps(r,indent=2)+'\n')
def bounded(cmd,seconds=40):
 p=subprocess.Popen(cmd,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True);expired=False;start=time.monotonic()
 try:out,err=p.communicate(timeout=seconds)
 except subprocess.TimeoutExpired:
  expired=True;os.killpg(p.pid,signal.SIGTERM)
  try:out,err=p.communicate(timeout=1)
  except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);out,err=p.communicate()
 return dict(command=cmd,exit=p.returncode,stdout=out,stderr=err,timeout=expired,wall_seconds=time.monotonic()-start)
for backend in ('qbe','llvm'):
 for arm,compiler in (('before',before),('after',after)):
  for counted in (True,False):
   binary=w/f'lox-{arm}-{backend}-{int(counted)}'
   cmd=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build','main.my','--project','-o',str(binary),'--cache-dir',str(w/f'lox-cache-{arm}'),f'--backend={backend}','--keep-symbols',('--rc-runtime=stats' if counted else '--rc-runtime')]
   if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
   done=subprocess.run(cmd,env=env,cwd=port,capture_output=True,text=True)
   row=dict(arm=arm,backend=backend,counted=counted,command=cmd,exit=done.returncode,stdout=done.stdout,stderr=done.stderr);r['builds'].append(row);save();assert done.returncode==0,row
   row.update(binary_sha256=sha(binary),manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text()));assert row['manifest']['backend']==backend;save();print('BUILD',arm,backend,counted,flush=True)
   for n in (4,5):
    script=previous/f'binary_trees_n{n}.lox';cmd=[str(binary),'--engine=vm',str(script)]
    for repeat in range(1 if counted else 3):
     run=bounded(['taskset','-c','3']+([] if counted else ['perf','stat','-x,','-e','cpu_core/instructions/u','--'])+cmd)
     run.update(arm=arm,backend=backend,counted=counted,n=n,repeat=repeat,script_sha256=sha(script));r['runs'].append(run);save()
     expected=next(x['stdout'] for x in reference if x['arm']=='after' and x['backend']==backend and x['n']==n)
     assert run['exit']==0 and not run['timeout'] and run['stdout']==expected,run
     if counted:
      c=json.loads(next(s.removeprefix('MYLANG_RC_COUNTS ') for s in run['stderr'].splitlines() if s.startswith('MYLANG_RC_COUNTS ')));run['counts']=c
      assert not c['saturated'] and c['heap_allocate']==c['retire'] and c['owner_acquire']+c['heap_allocate']==c['owner_release'] and c['hold_acquire']==c['hold_release'],run
     else:
      line=next(s for s in run['stderr'].splitlines() if ',cpu_core/instructions/u,' in s);parts=line.split(',');run['instructions']=int(parts[0]);run['event_runtime_ns']=int(parts[3]);run['event_running_percent']=float(parts[4]);assert run['event_running_percent']==100.0,run
     save();print('RUN',arm,backend,counted,n,repeat,round(run['wall_seconds'],3),run.get('counts',run.get('instructions')),flush=True)
print('COMPLETE',flush=True)

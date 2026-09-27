from pathlib import Path
import os,json,subprocess,hashlib,signal,time,statistics,sys
root=Path.cwd();w=root/'.tmp-named-record';baseline=w;perf=root.parent/'d9-rc-performance/.tmp-rc-performance'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();before=json.loads((w/'lox-before-builds.json').read_text());after=json.loads((w/'lox-after-builds.json').read_text());reference=json.loads((root/'.tmp-field/lox.json').read_text())['runs']
assert after['compiler_sha256']==sha(w/'install-frozen/bin/mylang');assert before['compiler_sha256']=='1f3bca2c62180a58fcc54782f9414a2b272e8447f996096a6883dc330774e3c7'
for name,digest in before['sources'].items():assert sha(root/'.tmp-plain-record/lox-guest'/name)==digest,name
full='--full' in sys.argv;path=w/('full.json' if full else 'reduced.json');r={'before_compiler':before['compiler_sha256'],'after_compiler':after['compiler_sha256'],'cpu':10,'runs':[]}
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env.update(TMPDIR=str(w/'tmp'),MYLANG_MEMORY_LIMIT='8G')
def save():path.write_text(json.dumps(r,indent=2)+'\n')
for n in ([10] if full else [4,5]):
 script=perf/'lox-scripts/binary_trees.tree.lox' if full else root.parent/f'd9-rc-plain-replace-astra/.tmp-lox/binary_trees_n{n}.lox'
 expected=(perf/'lox/bench/expected/binary_trees.tree.out').read_text() if full else next(x['stdout'] for x in reference if x['arm']=='after' and x['n']==n)
 for backend in ('qbe','llvm'):
  for counted in (True,False):
   for repeat in range(1 if counted else 3):
    for arm,build in [('before',before),('after',after)]:
     record=next(x for x in build['builds'] if x['backend']==backend and x['counted']==counted);cmd0=record['command'];binary=Path(cmd0[cmd0.index('-o')+1]);assert sha(binary)==record['binary_sha256'];assert record['manifest']['backend']==backend
     command=['taskset','-c','10','/usr/bin/time','-f','MYLANG_RSS_KIB=%M']+([] if counted else ['perf','stat','-x,','-e','cpu_core/instructions/u','--'])+[str(binary),'--engine=vm',str(script)]
     print('START',n,backend,counted,repeat,arm,flush=True);start=time.monotonic();p=subprocess.Popen(command,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True);expired=False
     try:stdout,stderr=p.communicate(timeout=240 if full else 40)
     except subprocess.TimeoutExpired:
      expired=True;os.killpg(p.pid,signal.SIGTERM)
      try:stdout,stderr=p.communicate(timeout=1)
      except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);stdout,stderr=p.communicate()
     row=dict(n=n,arm=arm,backend=backend,counted=counted,repeat=repeat,command=command,exit=p.returncode,timeout=expired,stdout=stdout,stderr=stderr,wall_seconds=time.monotonic()-start,binary_sha256=sha(binary),input_sha256=sha(script),expected_sha256=hashlib.sha256(expected.encode()).hexdigest());r['runs'].append(row);save();assert not expired and p.returncode==0 and stdout==expected,row
     row['wrapper_max_rss_kib']=int(next(x.removeprefix('MYLANG_RSS_KIB=') for x in stderr.splitlines() if x.startswith('MYLANG_RSS_KIB=')))
     if counted:
      c=json.loads(next(x.removeprefix('MYLANG_RC_COUNTS ') for x in stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')));row['counts']=c;assert not c['saturated'] and c['heap_allocate']==c['retire'] and c['owner_acquire']+c['heap_allocate']==c['owner_release'] and c['hold_acquire']==c['hold_release'],row
     else:
      parts=next(x.split(',') for x in stderr.splitlines() if ',cpu_core/instructions/u,' in x);row.update(instructions=int(parts[0]),event_runtime_ns=int(parts[3]),event_running_percent=float(parts[4]));assert row['event_running_percent']==100.0,row
     save();print('DONE',n,backend,counted,repeat,arm,round(row['wall_seconds'],3),row.get('instructions',row.get('counts')),flush=True)
print('COMPLETE',flush=True)

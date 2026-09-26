import hashlib,json,statistics,subprocess
from pathlib import Path
p=Path.cwd()/'.tmp-rc/profile';out=Path.cwd()/'.tmp-rc/inert-return';expected=(p/'rc-n12.stdout').read_text();sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
r={'base':'41e08854','source_sha256':sha(p/'binary_trees_n12.my'),'cpu':2,'compilers':{arm:sha(p/f'install-{name}/bin/mylang') for arm,name in [('before','gap-allocator'),('after','inert-return-final')]},'backends':{}}
for backend in ('qbe','llvm'):
 names={'before':f'gap-allocator-{backend}-rc-n12','after':f'inert-return-final-{backend}-rc-n12','gc':f'gap-allocator-{backend}-gc-n12'}
 samples=[];counts={}
 for iteration in range(3):
  for arm in (('before','after','gc') if iteration%2==0 else ('gc','after','before')):
   binary=p/names[arm];meta=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text());assert meta['backend']==backend and meta['lto']==(backend=='llvm')
   cmd=['taskset','-c','2','perf','stat','-x,','-e','instructions:u,cycles:u','--',str(binary)]
   done=subprocess.run(cmd,text=True,capture_output=True,check=True);assert done.stdout==expected
   counters={f[2]:int(f[0]) for line in done.stderr.splitlines() if len(f:=line.split(','))>2 and f[0].isdigit()}
   samples.append({'arm':arm,'command':cmd,'counters':counters,'stderr':done.stderr})
 for arm,name in [('before','gap-allocator'),('after','inert-return-final')]:
  done=subprocess.run(['taskset','-c','2',str(p/f'{name}-{backend}-stats-n12')],text=True,capture_output=True,check=True);assert done.stdout==expected
  counts[arm]=json.loads(done.stderr.removeprefix('MYLANG_RC_COUNTS '))
 assert counts['before']==counts['after'],counts
 med={arm:statistics.median(s['counters']['cpu_core/instructions/u'] for s in samples if s['arm']==arm) for arm in names}
 r['backends'][backend]={'medians':med,'after_over_before':med['after']/med['before'],'after_over_gc':med['after']/med['gc'],'samples':samples,'counts':counts,'binary_sha256':{arm:sha(p/name) for arm,name in names.items()}}
 (out/'measurement.json').write_text(json.dumps(r,indent=2)+'\n');print(backend,med,'after/before',med['after']/med['before'],'after/GC',med['after']/med['gc'],flush=True)

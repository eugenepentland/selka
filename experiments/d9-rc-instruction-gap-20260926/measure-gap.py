import hashlib,json,statistics,subprocess
from pathlib import Path
p=Path(__file__).resolve().parent
sha=lambda path:hashlib.sha256(Path(path).read_bytes()).hexdigest()
expected=(p/'rc-n12.stdout').read_text()
r={'revision':'7fc669a7','source_sha256':sha(p/'binary_trees_n12.my'),'compiler_sha256':sha(p/'install-gap/bin/mylang'),'cpu':0,'backends':{}}
for backend in ('qbe','llvm'):
 samples=[]
 for iteration in range(3):
  for mode in (('rc','gc') if iteration%2==0 else ('gc','rc')):
   binary=p/f'gap-{backend}-{mode}-n12'
   meta=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text())
   assert meta['backend']==backend and meta['lto']==(backend=='llvm')
   cmd=['taskset','-c','0','perf','stat','-x,','-e','instructions:u,cycles:u','--',str(binary)]
   done=subprocess.run(cmd,text=True,capture_output=True,check=True)
   assert done.stdout==expected
   counters={f[2]:int(f[0]) for line in done.stderr.splitlines() if len(f:=line.split(','))>2 and f[0].isdigit()}
   samples.append({'mode':mode,'command':cmd,'counters':counters,'stderr':done.stderr})
 med={mode:statistics.median(s['counters']['cpu_core/instructions/u'] for s in samples if s['mode']==mode) for mode in ('rc','gc')}
 done=subprocess.run(['taskset','-c','0',str(p/f'gap-{backend}-stats-n12')],text=True,capture_output=True,check=True)
 assert done.stdout==expected
 counts=json.loads(done.stderr.removeprefix('MYLANG_RC_COUNTS '))
 assert counts['heap_allocate']==counts['retire']==669060 and counts['owner_acquire']==19 and counts['owner_release']==669079
 r['backends'][backend]={'medians':med,'rc_over_gc':med['rc']/med['gc'],'counts':counts,'samples':samples,'binary_sha256':{mode:sha(p/f'gap-{backend}-{mode}-n12') for mode in ('rc','gc')}}
 print(backend,med,med['rc']/med['gc'],flush=True)
r['commands']=json.loads((p/'drop-build-commands.json').read_text())+json.loads((p/'gap-gc-build-commands.json').read_text())
(p/'gap.json').write_text(json.dumps(r,indent=2)+'\n')

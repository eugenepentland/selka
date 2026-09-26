import hashlib,json,os,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp-init'
compilers={'before':root.parent/'d9-rc-integration/.tmp-rc/install-history-flat/bin/mylang','after':root/'zig-out/bin/mylang'}
result={'compilers':{k:hashlib.sha256(v.read_bytes()).hexdigest() for k,v in compilers.items()},'runs':json.loads((work/'validation-probe-v2.json').read_text())['runs'][:8]}
for backend in ('qbe','llvm'):
 for case in ('direct54','frames','steps','floor','memory'):
  for arm,compiler in compilers.items():
   if any(row['backend']==backend and row['case']==case and row['arm']==arm for row in result['runs']):continue
   source=root/'experiments/d9-rc-inert-return-20260926'/('direct/driver.my' if case=='direct54' else 'trap.my')
   if case=='floor':source=work/'floor.my'
   if case=='memory':source=work/'budget.my'
   command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build',str(source),'--run','--rc-runtime=stats','--cache-dir='+str(work/'cache-validate')]
   if backend=='llvm':command+=['--backend=llvm','--llvm-opt=3','--lto']
   if case=='frames':command+=['--max-frames=4']
   if case=='steps':command+=['--max-steps=100']
   if case=='memory':command+=['--max-memory=2048']
   run=subprocess.run(command,text=True,capture_output=True,timeout=360,env=dict(os.environ,TMPDIR=str(work/'tmp'),ZIG_LOCAL_CACHE_DIR=str(root/'.zig-cache-init')))
   counts=[json.loads(line.removeprefix('MYLANG_RC_COUNTS ')) for line in run.stderr.splitlines() if line.startswith('MYLANG_RC_COUNTS ')]
   row={'backend':backend,'case':case,'arm':arm,'command':command,'status':run.returncode,'stdout':run.stdout,'stderr':run.stderr,'counts':counts};result['runs'].append(row)
   (work/'validation-final.json').write_text(json.dumps(result,indent=2)+'\n')
   assert run.returncode==(0 if case=='direct54' else 1) and not run.stdout and len(counts)==1,row
   c=counts[0];assert c['runtime']=='rc-v3-counting' and not c['saturated'] and c['heap_allocate']==c['retire'] and c['heap_allocate']+c['owner_acquire']==c['owner_release'] and c['hold_acquire']==c['hold_release'],row
   if case!='direct54':assert {'steps':'R_STEP_LIMIT','memory':'R_MEMORY_BUDGET'}.get(case,'R_FRAME_LIMIT') in run.stderr,row
   print(backend,case,arm,'PASS',flush=True)
  assert result['runs'][-1]['counts']==result['runs'][-2]['counts']

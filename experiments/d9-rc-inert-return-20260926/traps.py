import hashlib,json,subprocess
from pathlib import Path
root=Path.cwd();p=root/'.tmp-rc/inert-return';profile=root/'.tmp-rc/profile';result={'runs':[]}
for backend in ('qbe','llvm'):
 for mode in ('frames','steps','floor'):
  for arm,name in [('before','gap-allocator'),('after','inert-return-final')]:
   compiler=profile/f'install-{name}/bin/mylang';binary=p/f'trap-{backend}-{mode}-{arm}'
   cmd=[str(compiler),'build',str(p/'trap.my'),'--run','--rc-runtime=stats','--cache-dir='+str(p/'cache-traps')]
   if backend=='llvm':cmd+=['--backend=llvm','--llvm-opt=3','--lto']
   if mode!='floor':cmd+=['--max-frames=4' if mode=='frames' else '--max-steps=100']
   run=subprocess.run(cmd,text=True,capture_output=True,timeout=180)
   args=cmd
   lines=run.stderr.splitlines();records=[json.loads(line.removeprefix('MYLANG_RC_COUNTS ')) for line in lines if line.startswith('MYLANG_RC_COUNTS ')]
   row={'backend':backend,'mode':mode,'arm':arm,'build':cmd,'command':args,'exit':run.returncode,'stdout':run.stdout,'stderr':run.stderr,'counts':records}
   result['runs'].append(row);(p/'traps.json').write_text(json.dumps(result,indent=2)+'\n')
   assert run.returncode==1 and not run.stdout and len(records)==1,row
   c=records[0];assert c['heap_allocate']==c['retire'] and c['heap_allocate']+c['owner_acquire']==c['owner_release'] and c['hold_acquire']==c['hold_release'],row
   assert ('R_STEP_LIMIT' if mode=='steps' else 'R_FRAME_LIMIT') in run.stderr,row
   print(backend,mode,arm,c,flush=True)
  assert result['runs'][-1]['counts']==result['runs'][-2]['counts']

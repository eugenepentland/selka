import hashlib,json,subprocess
from pathlib import Path
root=Path.cwd(); p=root/'.tmp-rc/inert-return';profile=root/'.tmp-rc/profile'
compilers={'before':profile/'install-gap-allocator/bin/mylang','after':profile/'install-inert-return-final/bin/mylang'}
result={'compiler_sha256':{arm:hashlib.sha256(c.read_bytes()).hexdigest() for arm,c in compilers.items()},'runs':[]}
for backend in ('qbe','llvm'):
 for arm,compiler in compilers.items():
  binary=p/f'direct-{backend}-{arm}'
  cmd=[str(compiler),'build',str(p/'direct/driver.my'),'-o',str(binary),'--rc-runtime=stats','--keep-symbols','--cache-dir='+str(p/'cache-direct')]
  if backend=='llvm':cmd+=['--backend=llvm','--llvm-opt=3','--lto']
  build=subprocess.run(cmd,capture_output=True,text=True)
  assert build.returncode==0,(cmd,build.stdout,build.stderr)
  manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text())
  assert manifest['backend']==backend and manifest['lto']==(backend=='llvm')
  run=subprocess.run([str(binary)],text=True,capture_output=True)
  counts=json.loads(run.stderr.removeprefix('MYLANG_RC_COUNTS ')) if run.returncode==0 else None
  row={'arm':arm,'backend':backend,'command':cmd,'exit':run.returncode,'stdout':run.stdout,'stderr':run.stderr,'counts':counts,'build_stderr':build.stderr,'manifest':manifest}
  result['runs'].append(row);(p/'direct.json').write_text(json.dumps(result,indent=2)+'\n')
  assert run.returncode==0 and run.stdout=='',row
  assert counts['heap_allocate']==counts['retire'] and counts['owner_acquire']+counts['heap_allocate']==counts['owner_release'] and counts['hold_acquire']==counts['hold_release'],row
  print(backend,arm,counts,flush=True)
 for row in result['runs'][-2:]:assert row['counts']==result['runs'][-1]['counts']

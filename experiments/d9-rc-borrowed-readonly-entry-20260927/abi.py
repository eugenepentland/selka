from pathlib import Path
exec(Path('.tmp-borrowed-frame/controls.py').read_text().split('for side,c in C.items():')[0])
D={'compilers':D['compilers'],'builds':[],'runs':[]}
def save(): (W/'abi.json').write_text(json.dumps(D,indent=2)+'\n')
for side,c in C.items():
 for backend in ('qbe','llvm'):
  for name,expected in (('heap-result','205\n'),('large-result','True\n')):
   b=W/'bin'/f'{name}-{side}-{backend}';cmd=[R/'scripts/build-slot.sh','build',c,'build',W/'controls'/f'{name}.my','--mode=ReleaseFast','--rc-runtime=stats','--backend='+backend,'--cache-dir='+str(W/('cache-controls-'+side)),'-o',b]
   if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
   row=execute(cmd);row.update(side=side,backend=backend,case=name);D['builds'].append(row);save();assert row['status']==0,row
   m=json.loads(Path(str(b)+'.qbe-manifest.json').read_text());row.update(manifest=m,binary_sha256=sha(b));assert m['backend']==backend
   run=execute([b]);run.update(side=side,backend=backend,case=name);D['runs'].append(run);save();assert run['status']==0 and run['stdout']==expected,run
   counts(run);save();print(side,backend,name,run['stdout'].strip(),flush=True)
D['complete']=True;save()

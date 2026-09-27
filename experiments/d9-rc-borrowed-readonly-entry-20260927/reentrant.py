from pathlib import Path
exec(Path('.tmp-borrowed-frame/controls.py').read_text().split('for side,c in C.items():')[0])
D={'compilers':D['compilers'],'builds':[],'runs':[]}
def save(): (W/'reentrant.json').write_text(json.dumps(D,indent=2)+'\n')
cmd=['cc','-O2','-Wall','-Wextra','-I',R/'src',W/'controls/reentrant.c','-ldl','-o',W/'bin/reentrant'];row=execute(cmd);D['harness']=row;save();assert row['status']==0,row
for side,c in C.items():
 for backend in ('qbe','llvm'):
  b=W/'bin'/f'reentrant-{side}-{backend}.so';cmd=[R/'scripts/build-slot.sh','build',c,'build',W/'controls/reentrant.my','--library','--mode=Debug','--rc-runtime=stats','--backend='+backend,'--cache-dir='+str(W/('cache-controls-'+side)),'-o',b]
  if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
  row=execute(cmd);row.update(side=side,backend=backend);D['builds'].append(row);save();assert row['status']==0,row
  m=json.loads(Path(str(b)+'.qbe-manifest.json').read_text());row.update(manifest=m,binary_sha256=sha(b));assert m['backend']==backend
  symbols={f['name']:f['symbol'] for f in m['functions'] if not f['symbol'].endswith(('_rc_borrow','_rc_immortal'))}
  for mode in (0,1):
   run=execute([W/'bin/reentrant',b,symbols['seed'],symbols['visit'],mode]);run.update(side=side,backend=backend,mode=mode);D['runs'].append(run);save();assert run['status']==0,run
   counts(run);save();print(side,backend,mode,run['stdout'].strip(),flush=True)
D['complete']=True;save()

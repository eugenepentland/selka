from pathlib import Path
exec(Path('.tmp-borrowed-frame/controls.py').read_text().split('for side,c in C.items():')[0])
C={'after':W/'install-after/bin/mylang'}
D={'compilers':{s:{'path':str(c),'sha256':sha(c)} for s,c in C.items()},'builds':[],'runs':[]}
def save(): (W/'traps-final.json').write_text(json.dumps(D,indent=2)+'\n')
cases=[('bounds',['x'],'','R_LIST_BOUNDS',1),('fallback',['x','y'],'','',10),('overflow',['x','y','z'],'','R_OVERFLOW',1),('steps23',[],'--max-steps=23','R_STEP_LIMIT',1),('steps24',[],'--max-steps=24','R_STEP_LIMIT',1),('frames',[],'--max-frames=3','R_FRAME_LIMIT',1),('success',[],'--max-frames=4','',12)]
for side,c in C.items():
 for backend in ('qbe','llvm'):
  b=W/'identity-final'/f'traps-final-{side}-{backend}';cmd=[R/'scripts/build-slot.sh','build',c,'build',W/'controls/traps.my','--mode=Debug','--rc-runtime=stats','--backend='+backend,'--cache-dir='+str(W/('cache-controls-'+side)),'-o',b]
  if backend=='llvm':cmd+=['--llvm-opt=0']
  row=execute(cmd);row.update(side=side,backend=backend);D['builds'].append(row);save();assert row['status']==0,row
  row.update(manifest=json.loads(Path(str(b)+'.qbe-manifest.json').read_text()),binary_sha256=sha(b));assert row['manifest']['backend']==backend
  for name,args,options,code,status in cases:
   run=execute([b,*args],options);run.update(side=side,backend=backend,case=name,expected_trap=code);D['runs'].append(run);save()
   assert run['status']==status and (not code or code in run['stderr']),run
   counts(run);save();print(side,backend,name,'passed',flush=True)
for backend in ('qbe','llvm'):
 for case,*_ in cases:
  rows=[r for r in json.loads((W/'traps.json').read_text())['runs'] if r['side']=='before' and r['backend']==backend and r['case']==case]+[r for r in D['runs'] if r['backend']==backend and r['case']==case]
  clean=lambda r:'\n'.join(s for s in r['stderr'].splitlines() if not s.startswith('MYLANG_RC_COUNTS '))
  assert len(rows)==2 and clean(rows[0])==clean(rows[1]) and rows[0]['stdout']==rows[1]['stdout'],rows
D['complete']=True;save()

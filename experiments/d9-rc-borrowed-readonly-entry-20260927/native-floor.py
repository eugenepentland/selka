from pathlib import Path
exec(Path('.tmp-borrowed-frame/controls.py').read_text().split('for side,c in C.items():')[0])
D={'source_sha256':sha(W/'controls/native-floor.c'),'runs':[]}
def save(): (W/'native-floor.json').write_text(json.dumps(D,indent=2)+'\n')
row=execute(['cc','-O2','-Wall','-Wextra','-I',R/'src',W/'controls/native-floor.c','-ldl','-o',W/'bin/native-floor']);D['harness']=row;save();assert row['status']==0,row
for build in json.loads((W/'reentrant.json').read_text())['builds']:
 m=build['manifest'];symbols={f['name']:f['symbol'] for f in m['functions'] if not f['symbol'].endswith(('_rc_borrow','_rc_immortal'))}
 b=Path(build['command'][build['command'].index('-o')+1]);run=execute([W/'bin/native-floor',b,symbols['seed'],symbols['visit'],2]);run.update(side=build['side'],backend=build['backend'],binary_sha256=sha(b));D['runs'].append(run);save();assert run['status']==0 and 'code=R_FRAME_LIMIT' in run['stdout'],run
 counts(run);save();print(build['side'],build['backend'],'native floor preserved',flush=True)
D['complete']=True;save()

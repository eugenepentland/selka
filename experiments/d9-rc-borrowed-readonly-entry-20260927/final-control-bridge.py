from pathlib import Path
exec(Path('.tmp-borrowed-frame/controls.py').read_text().split('for side,c in C.items():')[0])
final=W/'install-after/bin/mylang';D={'compiler':str(final),'compiler_sha256':sha(final),'builds':[],'runs':[],'trap_identities':[]}
def save():(W/'final-control-bridge.json').write_text(json.dumps(D,indent=2)+'\n')
for row in json.loads((W/'reentrant.json').read_text())['builds']:
 if row['side']!='after':continue
 cmd=list(row['command']);old=Path(cmd[cmd.index('-o')+1]);new=W/'identity-final'/old.name;cmd[2]=str(final);cmd[cmd.index('-o')+1]=str(new)
 out=execute(cmd);out.update(side='after',backend=row['backend']);D['builds'].append(out);save();assert out['status']==0,out
 m=json.loads(Path(str(new)+'.qbe-manifest.json').read_text());out.update(manifest=m,binary_sha256=sha(new));assert m['backend']==row['backend']
 symbols={f['name']:f['symbol'] for f in m['functions'] if not f['symbol'].endswith(('_rc_borrow','_rc_immortal'))}
 for mode in (0,1,2):
  harness=W/'bin'/('native-floor' if mode==2 else 'reentrant');run=execute([harness,new,symbols['seed'],symbols['visit'],mode]);run.update(side='after',backend=row['backend'],mode=mode);D['runs'].append(run);save();assert run['status']==0,run
  if mode==2:assert 'code=R_FRAME_LIMIT' in run['stdout'],run
  counts(run);save();print(row['backend'],mode,'final compiler passed',flush=True)
for row in json.loads((W/'traps.json').read_text())['builds']:
 if row['side']!='after':continue
 cmd=list(row['command']);old=Path(cmd[cmd.index('-o')+1]);new=W/'identity-final'/old.name;cmd[2]=str(final);cmd[cmd.index('-o')+1]=str(new)
 out=execute(cmd);out.update(case='traps',backend=row['backend'],original=str(old),replacement=str(new));D['trap_identities'].append(out);save();assert out['status']==0,out
 out.update(original_sha256=sha(old),replacement_sha256=sha(new));save();assert out['original_sha256']==out['replacement_sha256'],out
 print(row['backend'],'traps byte-identical',flush=True)
D['complete']=True;save()

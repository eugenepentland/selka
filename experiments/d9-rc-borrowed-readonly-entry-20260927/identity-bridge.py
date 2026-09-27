from pathlib import Path
exec(Path('.tmp-borrowed-frame/controls.py').read_text().split('for side,c in C.items():')[0])
final=W/'install-after/bin/mylang';D={'compiler':str(final),'compiler_sha256':sha(final),'rows':[]}
def save():(W/'identity-bridge.json').write_text(json.dumps(D,indent=2)+'\n')
for file in ('controls','abi','reentrant','traps'):
 d=json.loads((W/(file+'.json')).read_text())
 for row in d['builds']:
  if row['side']!='after':continue
  cmd=list(row['command']);old=Path(cmd[cmd.index('-o')+1]);new=W/'identity-final'/old.name;new.parent.mkdir(exist_ok=True)
  cmd[2]=str(final);cmd[cmd.index('-o')+1]=str(new)
  out=execute(cmd);out.update(case=file,original=str(old),replacement=str(new));D['rows'].append(out);save();assert out['status']==0,out
  out.update(original_sha256=sha(old),replacement_sha256=sha(new));save();assert out['original_sha256']==out['replacement_sha256'],out
  print(file,old.name,'byte-identical',flush=True)
D['complete']=True;save()

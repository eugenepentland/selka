import json,subprocess
from pathlib import Path
root=Path.cwd();p=root/'.tmp-rc/inert-return';compiler=root/'.tmp-rc/profile/install-inert-return-final/bin/mylang';r=[]
for backend in ('qbe','llvm'):
 for mode in ('gc','rc'):
  cmd=[str(compiler),'test','tests/lang/rc_inert_returns.my','--gc-runtime' if mode=='gc' else '--rc-runtime=stats','--force','--json','--jobs=2']+(['--release'] if backend=='llvm' else [])
  run=subprocess.run(cmd,text=True,capture_output=True);data=json.loads(run.stdout);r.append({'command':cmd,'exit':run.returncode,'result':data,'stderr':run.stderr});(p/'final-guests.json').write_text(json.dumps(r,indent=2)+'\n')
  assert run.returncode==0 and len(data['tests'])==8 and all(t['status']=='passed' for t in data['tests']),(cmd,data,run.stderr)
  print(backend,mode,'8 passed',flush=True)

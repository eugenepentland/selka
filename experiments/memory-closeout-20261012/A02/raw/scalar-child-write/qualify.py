import json,subprocess
from pathlib import Path
w=Path('.tmp/memory-closeout/A02/scalar-child-validation')
r=[]
for ownership,modes in [('zero',['release','debug','verify','optimized_debug','no_facts']),('ordinary',['release','debug'])]:
 for mode in modes:
  command=['scripts/build-slot.sh','build','python3','-B',str(w/'native.py'),'--ownership',ownership,'--mode',mode]
  p=subprocess.run(command,text=True,capture_output=True)
  (w/('admission-'+ownership+'-'+mode+'.log')).write_text(p.stdout+p.stderr)
  r.append({'ownership':ownership,'mode':mode,'command':command,'status':p.returncode})
  (w/'native-batches.json').write_text(json.dumps(r,indent=2)+'\n')
  print(ownership,mode,p.returncode,flush=True)
  if p.returncode:raise SystemExit(p.returncode)

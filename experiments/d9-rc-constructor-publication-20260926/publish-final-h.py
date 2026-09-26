import hashlib,json,subprocess
from pathlib import Path
p=Path(__file__).resolve().parent;root=p.parents[1];compiler=p/'install-publish/bin/mylang'
r={'source_sha256':hashlib.sha256((root/'tests/lang/rc_aggregate_values.my').read_bytes()).hexdigest(),'cases':{}}
for backend in ('qbe','llvm'):
 for mode in ('gc','rc'):
  cmd=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'test','tests/lang/rc_aggregate_values.my','--filter','*constructor_publishes_nested_holds*','--force','--json','--jobs=1']
  if mode=='rc':cmd+=['--rc-runtime=stats']
  if backend=='llvm':cmd+=['--release']
  d=subprocess.run(cmd,text=True,capture_output=True);data=json.loads(d.stdout)
  r['cases'][backend+'/'+mode]={'command':cmd,'exit':d.returncode,'result':data,'stderr':d.stderr}
  (p/'publish-final-h.json').write_text(json.dumps(r,indent=2)+'\n')
  assert d.returncode==0 and data['passed']==1 and data['failed']==0
  print(backend,mode,'passed',flush=True)

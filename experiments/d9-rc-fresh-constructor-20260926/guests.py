"""Focused existing aggregate/history controls using the candidate compiler."""
import json,os,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp-mut-argument/fresh-guests';work.mkdir(exist_ok=True)
compiler=root/'.tmp-mut-argument/fresh-candidate/bin/mylang'
result=[]
for backend in ('qbe','llvm'):
 for name in ('rc_aggregate_values','rc_semantic_history','mut_argument_places','mut_dictionary_arguments','option_niche','recursive_values','iteration_identity','rc_fresh_constructors'):
  command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'test',f'tests/lang/{name}.my','--json','--force','--rc-runtime=stats']
  if backend=='llvm':command+=['--release']
  run=subprocess.run(command,text=True,capture_output=True,env=dict(os.environ,TMPDIR=str(work)))
  row={'backend':backend,'name':name,'command':command,'exit':run.returncode,'stdout':run.stdout,'stderr':run.stderr}
  result.append(row);(work/'results.json').write_text(json.dumps(result,indent=2)+'\n')
  assert run.returncode==0,row
  output=json.loads(run.stdout); print(backend,name,output.get('summary',output.get('passed','PASS')),flush=True)

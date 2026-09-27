"""Record the exact advance body and its remaining journal publication sites."""
import hashlib,json,os,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp-mut-argument/scalar-run'
compilers={'before':root.parent/'d9-rc-integration/.tmp-rc/install-argv-return/bin/mylang','after':root/'.tmp-mut-argument/scalar-candidate/bin/mylang'}
result=[]
for arm,compiler in compilers.items():
 command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'emit-qbe','bench/parity/suite/nbody.my','--rc-runtime','--drop-step-checks','--drop-frame-checks']
 run=subprocess.run(command,text=True,capture_output=True,env=dict(os.environ,TMPDIR=str(work)))
 assert run.returncode==0,run.stderr
 data=json.loads(run.stdout);(work/f'{arm}-emitted.json').write_text(run.stdout)
 function=next(f for f in data['functions'] if f['name']=='advance'); il=function['il'];(work/f'{arm}-advance.ssa').write_text(il)
 row={'arm':arm,'command':command,'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'symbol':function.get('symbol'), 'live_publications':il.count(' storew 1,'),'native_calls':il.count('call $'),'ssa_bytes':len(il)}
 result.append(row);(work/'emission.json').write_text(json.dumps(result,indent=2)+'\n');print(row,flush=True)
assert result[0]['live_publications']==9 and result[1]['live_publications']==0,result

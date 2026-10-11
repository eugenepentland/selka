from pathlib import Path
from types import SimpleNamespace
import json,sys
root=Path('/home/epentland/.codex/worktrees/selka-selfhost-pilots/mylang');sys.path.insert(0,str(root/'selfhost/tests'));import run_body_check_qualification as D
work=Path('/home/epentland/.cache/mylang-tmp/selka-selfhost-pilots/b5-edit-rebuild-repro');work.mkdir()
args=SimpleNamespace(builder=root/'zig-out/tools/selka-components',zig=Path('/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig'))
q=SimpleNamespace(work=work,matrix=lambda:0)
original=D.F.execute;count=0
def retained(command,env,cwd,timeout=180):
 global count
 result=original(command,env,cwd,timeout);count+=1
 for suffix,data in [('stdout',result[1]),('stderr',result[2])]: (work/f'command-{count}.{suffix}').write_bytes(data)
 (work/f'command-{count}.json').write_text(json.dumps({'command':[str(x) for x in command],'status':result[0],'address_space_budget':D.F.ADDRESS_SPACE_BUDGET},indent=2)+'\n')
 return result
D.F.execute=retained
result=D.coordinator_edit(args,q)
(work/'receipt.json').write_text(json.dumps({'scope':'Coordinator rebuild only; matrix deliberately not executed in isolated failure reproduction','result':result},indent=2)+'\n')
print(json.dumps(result))

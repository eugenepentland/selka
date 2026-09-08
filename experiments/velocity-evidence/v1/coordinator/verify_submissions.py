"""Post-seal full declared .my application tests, outside development clocks."""
import sys,json,shutil,hashlib
from pathlib import Path
sys.path.insert(0,'/home/epentland/ai/canopy/mylang')
from experiments.application_comparison import session,trial_configuration,iteration_log
from experiments.application_comparison.storage import read_json,write_json,verify_snapshot,snapshot
from experiments.application_comparison.isolation import run,Limits
R=Path(__file__).parent
TASKS=['eda-clearance-boundary','planner-input-boundary','eda-pin-roles','planner-priority','eda-rotation','planner-cycle-groups','planner-dependency-lags','planner-slack']
def verify(task):
 r=R/task;cfg=read_json(r/'my-configuration.json');trial_configuration.verify(cfg);m=session.load(r/'my');assert m['phase']=='sealed'
 idx=m['final_submission'];row=m['submissions'][idx];source=r/'my/submissions'/f'{idx:03}'/'source';verify_snapshot(source,row['source'])
 out=r/'declared-tests';out.mkdir(exist_ok=False);snapshot(source,out/'source');(out/'cache').mkdir()
 result=run(out/'source',['/usr/bin/python3','-B','/tools/workflow/project.py','--compiler','/tools/compiler','--entry','/work/main.my','--manifest','/work/verify.json','--cache-dir','/cache/project','--report','/cache/full-manifest.json'],tools=cfg['tools'],cache=out/'cache',limits=Limits(wall_seconds=60,cpu_seconds=60,memory_bytes=4*1024**3))
 for stream in ('stdout','stderr'):(out/stream).write_bytes(result.pop(stream))
 verify_snapshot(source,row['source']);verify_snapshot(out/'source',row['source']);trial_configuration.verify(cfg)
 result['passed']=result['returncode']==0 and result['outcome']=='exited';result['development_clock_changed']=False;result['source_sha256']=row['source']['sha256'];write_json(out/'result.json',result)
 iteration_log.append(R,'sealed-declared-tests',{'task':task,'passed':result['passed'],'result_sha256':hashlib.sha256((out/'result.json').read_bytes()).hexdigest()})
 print(json.dumps({'task':task,'passed':result['passed'],'seconds':result['elapsed_seconds']}))
if __name__=='__main__':
 for task in TASKS if sys.argv[1]=='all' else [sys.argv[1]]:verify(task)

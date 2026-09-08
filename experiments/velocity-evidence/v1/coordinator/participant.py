"""Invoke only; coordinator sources and hidden packs are not participant materials."""
import sys,json
from pathlib import Path
sys.path.insert(0,'/home/epentland/ai/canopy/mylang')
from experiments.application_comparison import session
from experiments.application_comparison.participant_gateway import Gateway
from experiments.application_comparison.preparation_gateway import PreparationGateway
from experiments.application_comparison.storage import read_json
from experiments.application_comparison.isolation import Limits
R=Path(__file__).parent
task,op=sys.argv[1:3];args=json.loads(sys.argv[3]) if len(sys.argv)>3 else {}
if task not in ('eda-clearance-boundary','planner-input-boundary','eda-pin-roles','planner-priority','eda-rotation','planner-cycle-groups','planner-dependency-lags','planner-slack'):raise ValueError('task')
r=R/task;root=r/'my';cfg=read_json(r/'my-configuration.json')
if session.load(root)['phase']=='prepared':session.start_preparation(root)
g=Gateway(root,cfg['tools'],Limits(wall_seconds=60,cpu_seconds=60,memory_bytes=4*1024**3),adapter=cfg['task_adapter'],public_case=read_json(r/'pack/public/cases.json'),retain_command_cache=True)
if session.load(root)['phase']=='preparing':g=PreparationGateway(g,cfg['practice_adapter'],read_json(r/'my-practice/cases.json'))
try: print(json.dumps(g.dispatch(op,args),ensure_ascii=False))
except Exception as error:
 print(json.dumps({'error':type(error).__name__,'message':str(error)}));sys.exit(1)

"""Validate post-review test corrections, never rewrite timed submissions."""
import sys,json
from pathlib import Path
sys.path.insert(0,'/home/epentland/ai/canopy/mylang')
from experiments.application_comparison.isolation import run,Limits
from experiments.application_comparison.storage import read_json,write_json,path_identity
from experiments.application_comparison import iteration_log
R=Path(__file__).parent
MUTATIONS={
'eda-clearance-boundary':'''import test_clearance as t
t.invoke=lambda _: {'results':[]}
try:t.tests()
except ValueError:print('truncated results rejected')
else:raise AssertionError('truncated results accepted')
''',
'planner-slack':'''import test_slack as t
original=t.call
t.call=lambda _: {'results':[]}
try:t.Slack().test_exhaustive_feasible_schedules()
except ValueError:print('truncated results rejected')
else:raise AssertionError('truncated results accepted')
def missing(request):
 result=original(request)
 for item in result['results']:item['timings']=[];item['critical']=[]
 return result
t.call=missing
try:t.Slack().test_exhaustive_feasible_schedules()
except AssertionError:print('missing timing membership rejected')
else:raise AssertionError('missing timings accepted')
'''}
for task,filename in [('eda-clearance-boundary','test_clearance.py'),('planner-slack','test_slack.py')]:
 out=R/'review-followups'/task;source=out/'source';identity=path_identity(source);cfg=read_json(R/task/'my-configuration.json');rows=[]
 for label,argv in [('regressions',['/usr/bin/python3','-B',filename]),('test-completeness-mutations',['/usr/bin/python3','-B','-c',MUTATIONS[task]])]:
  folder=out/label;folder.mkdir();cache=folder/'cache';cache.mkdir();result=run(source,argv,tools=cfg['tools'],cache=cache,limits=Limits(wall_seconds=60,cpu_seconds=60,memory_bytes=4*1024**3))
  for stream in ('stdout','stderr'):(folder/stream).write_bytes(result.pop(stream))
  assert path_identity(source)==identity
  write_json(folder/'result.json',result);assert result['returncode']==0
  rows.append({'label':label,'passed':True,'result':path_identity(folder/'result.json')})
 report={'task':task,'passed':True,'source':identity,'tests':rows,'timed_submission_changed':False};write_json(out/'validation.json',report);iteration_log.append(R,'post-review-test-fix-validated',report);print(task,'passed',flush=True)

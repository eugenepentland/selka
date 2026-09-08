"""Post-seal replay of original five pre-frozen cycle resource groups."""
import sys,json,hashlib
from pathlib import Path
sys.path.insert(0,'/home/epentland/ai/canopy/mylang')
from experiments.application_comparison import session,trial_configuration
from experiments.application_comparison.execution import evaluate,correct
from experiments.application_comparison.inputs import decode_case
from experiments.application_comparison.storage import read_json,write_json,digest,verify_snapshot
R=Path(__file__).parent
FIXTURES=Path('/home/epentland/ai/canopy/application-trials/portable-planner-20260907/planner-cycle-groups/supplemental-limits.json')
EXPECTED='a7ffb3f1abf5667b5aa8d80b791c2e647dec75c43d52c1e9e479f9c5a390a318'
def main():
 assert hashlib.sha256(FIXTURES.read_bytes()).hexdigest()==EXPECTED
 r=R/'planner-cycle-groups';m=session.load(r/'my');assert m['phase']=='sealed'
 cfg=read_json(r/'my-configuration.json');trial_configuration.verify(cfg)
 idx=m['final_submission'];row=m['submissions'][idx];source=r/'my/submissions'/f'{idx:03}'/'source';verify_snapshot(source,row['source'])
 assert row['check']['passed'] and not row['scope_violations']
 out=r/'supplemental-limits';out.mkdir(exist_ok=True)
 plan={'version':'velocity-cycle-limit-replay-v1','fixtures_sha256':EXPECTED,'session_sha256':digest(m),'configuration_sha256':cfg['sha256'],'helper_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
 if (out/'plan.json').exists():assert read_json(out/'plan.json')==plan
 write_json(out/'plan.json',plan);results=[]
 for i,item in enumerate(read_json(FIXTURES)['cases']):
  p=out/f'case-{i:03}.json'
  if p.exists():
   result=read_json(p);assert result['plan_sha256']==digest(plan)
  else:
   request,raw,expected=decode_case(item['case']);execution=out/f'case-{i:03}-execution';assert not execution.exists(),'incomplete execution needs explicit recovery'
   result_raw=evaluate(source,row['source'],cfg['task_adapter'],request,execution,request_bytes=raw)
   result={'plan_sha256':digest(plan),'passed':correct(result_raw['outcome'],expected),'execution':result_raw};write_json(p,result)
  results.append(result)
 verify_snapshot(source,row['source']);trial_configuration.verify(cfg);assert digest(session.load(r/'my'))==plan['session_sha256']
 result={'version':'velocity-cycle-limit-result-v1','plan_sha256':digest(plan),'case_groups':len(results),'passed':all(x['passed'] for x in results),'cases':results};write_json(out/'result.json',result)
 print(json.dumps({k:v for k,v in result.items() if k!='cases'}))
if __name__=='__main__':main()

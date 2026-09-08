"""Replay historical maintenance cases against new sealed code; no clocks changed."""
import sys,json,shutil,hashlib
from pathlib import Path
sys.path.insert(0,'/home/epentland/ai/canopy/mylang/experiments/maintenance_trial')
import pack
from experiments.application_comparison.storage import read_json,write_json,verify_snapshot
R=Path(__file__).parent;OLD=Path('/home/epentland/ai/canopy/application-trials/maintenance-20260907')
def main():
 refs=read_json(R/'historical-inputs.json');out=R/'historical-replays';out.mkdir(exist_ok=True);rows=[]
 for name,ref in refs.items():
  prior=OLD/name/'grade.json';assert hashlib.sha256(prior.read_bytes()).hexdigest()==ref
  old=read_json(prior);current=R/'runs'/name;seal=read_json(current/'seal.json');verify_snapshot(current/'sealed',seal['source'])
  target=out/name
  if not target.exists():
   target.mkdir();shutil.copy2(current/'setup.json',target/'setup.json');shutil.copy2(current/'seal.json',target/'seal.json');shutil.copytree(current/'sealed',target/'sealed')
  assert read_json(target/'seal.json')==seal;assert read_json(target/'setup.json')==read_json(current/'setup.json')
  verify_snapshot(target/'sealed',seal['source'])
  if (target/'grade.json').exists():
   result=read_json(target/'grade.json');assert result['source']==seal['source'] and result['private_seed']==old['private_seed']
  else:result=pack.grade(target,old['private_seed'])
  rows.append({'run':name,'passed':result['behavior_passed'],'observations':len(result['outcomes']),'source_sha256':seal['source']['sha256'],'historical_grade_sha256':ref,'grade_sha256':hashlib.sha256((target/'grade.json').read_bytes()).hexdigest()})
 summary={'version':'velocity-maintenance-historical-replay-v1','rows':rows,'passed':all(x['passed'] for x in rows),'development_clock_changes':False}
 write_json(out/'summary.json',summary);print(json.dumps(summary))
if __name__=='__main__':main()

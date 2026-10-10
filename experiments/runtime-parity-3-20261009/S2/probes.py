#!/usr/bin/env python3
"""Build and checksum S2-owned cells, then pair CPU-8 instructions with M0."""
import argparse,hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'experiments/runtime-parity-3-20261009/tools'))
import ce,corpus_perf,pstat

def main():
 p=argparse.ArgumentParser();p.add_argument('--compiler',type=Path,required=True);p.add_argument('--tag',required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--rounds',type=int,default=5);a=p.parse_args()
 lane=ce.Lane(a.compiler,a.tag);lane.bins.mkdir(parents=True,exist_ok=True)
 jobs=[('eda',ce.EDA_SRC/'src/main.my',ce.EDA_SRC),('lox',ce.LOX_SRC/'main.my',ce.LOX_SRC)]
 jobs += [('parity-'+name,ROOT/('bench/parity/'+ce.PARITY[name]+'.my'),ROOT) for name in ('text_ops','scan_split','knucleotide')]
 for label,source,cwd in jobs:
  for kind in ('plain','count') if label=='parity-knucleotide' else ('plain',):
   target=lane.bins/(label+'-'+kind)
   command=[str(lane.compiler),'build',str(source),'-o',str(target),'--cache-dir',str(lane.cache),'--release']
   if kind=='count':command.append('--counters')
   status,stdout,stderr=ce.run(command,cwd=cwd,extra_env={'MYLANG_CORE_RUNTIME_CACHE':str(lane.runtime_cache)},slot=False)
   if status:raise RuntimeError((label,status,stderr.decode()[-4000:]))
   print('built',target,flush=True)
 selected={'parity/text_ops','parity/scan_split','parity/knucleotide','eda/rds3+flat','eda/labstation','lox/tree/string_equality','lox/vm/string_equality'}
 arms=[];checks={}
 for base in corpus_perf.arms_for('base'):
  if base['program'] not in selected:continue
  candidate={**base,'arm':a.tag,'argv':list(base['argv'])};candidate['argv'][0]=str(lane.bins/Path(base['argv'][0]).name)
  if base['program'].startswith('eda/'):
   at=candidate['argv'].index('--out-dir')+1
   output=ROOT/'.mylang-cache/rp3/s2-probe-out'/a.tag/base['program'].split('/')[1];output.mkdir(parents=True,exist_ok=True);candidate['argv'][at]=str(output)
  checked=[]
  for arm in (base,candidate):
   proc=subprocess.run(['taskset','-c','8',*arm['argv']],cwd=arm.get('cwd'),capture_output=True)
   checked.append({'status':proc.returncode,'stdout_sha256':hashlib.sha256(proc.stdout).hexdigest(),'stderr':proc.stderr.decode()[-1000:]})
  checks[base['program']]={'base':checked[0],'candidate':checked[1],'equal_stdout':checked[0]['stdout_sha256']==checked[1]['stdout_sha256']}
  if any(row['status'] for row in checked):raise RuntimeError(checks)
  arms.extend((base,candidate))
 refs=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-runtime-parity-3/.mylang-cache/rp3/parity-base/bin')
 for name in ('text_ops','scan_split'):
  arms.append({'program':'parity/'+name,'arm':'zig-safe','argv':[str(refs/(name+'.zig-safe'))]})
 arms.append({'program':'parity/text_ops','arm':'rung3','argv':[str(ROOT/'.mylang-cache/rp3/s2-ladder/text_ops.r3')]})
 armfile=a.out.with_suffix('.arms.json');armfile.write_text(json.dumps(arms,indent=1)+'\n')
 subprocess.run([sys.executable,str(ROOT/'experiments/runtime-parity-3-20261009/tools/pstat.py'),str(armfile),'--out',str(a.out),'--rounds',str(a.rounds)],check=True)
 data=json.loads(a.out.read_text());data['checks']=checks;data['compiler_sha256']=ce.digest(lane.compiler);a.out.write_text(json.dumps(data,indent=1)+'\n')
 counts=ROOT/'.mylang-cache/rp3/s2-probe-out'/a.tag/'knucleotide-count.json';counts.parent.mkdir(parents=True,exist_ok=True)
 status,stdout,stderr=ce.run([lane.bins/'parity-knucleotide-count'],extra_env={'MYLANG_COUNTERS':str(counts)})
 print('counted knucleotide',status,counts,flush=True)
 if status:raise RuntimeError(stderr.decode())
if __name__=='__main__':main()

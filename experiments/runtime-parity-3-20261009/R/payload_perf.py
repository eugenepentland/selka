#!/usr/bin/env python3
"""Measure the conservative payload prototype on unchanged Lox/EDA programs."""
import argparse,json,os,pathlib,subprocess,sys
ROOT=pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'experiments/runtime-parity-3-20261009/tools'))
import ce,corpus_perf,pstat
p=argparse.ArgumentParser();p.add_argument('--compiler',type=pathlib.Path,required=True);p.add_argument('--tag',required=True);p.add_argument('--against',default='base');p.add_argument('--prebuilt',action='store_true');p.add_argument('--out',type=pathlib.Path);a=p.parse_args()
assert pathlib.Path(os.readlink('/proc/self/fd/9')).name.startswith('build')
lane=ce.Lane(a.compiler,a.tag);lane.bins.mkdir(parents=True,exist_ok=True);lane.cache.mkdir(parents=True,exist_ok=True)
for name,source,cwd in ([] if a.prebuilt else [('lox',ce.LOX_SRC/'main.my',ce.LOX_SRC),('eda',ce.EDA_SRC/'src/main.my',ce.EDA_SRC)]):
 command=[str(lane.compiler),'build',str(source),'-o',str(lane.bins/(name+'-plain')),'--release','--cache-dir',str(lane.cache),'--emit-llvm',str(lane.cache/(name+'.ll'))]
 subprocess.run(command,cwd=cwd,env=dict(os.environ,MYLANG_CORE_RUNTIME_CACHE=str(lane.runtime_cache)),check=True)
 print('built',name,flush=True)
# Build only the two corpus executables: the other prebuilt arms are unnecessary.
all_arms=corpus_perf.arms_for('base');arms=[]
for base in all_arms:
 if not base['program'].startswith(('lox/','eda/')):continue
 base={**base,'arm':a.against,'argv':list(base['argv'])};base['argv'][0]=str(ce.CACHE/'bin'/a.against/pathlib.Path(base['argv'][0]).name)
 candidate={**base,'arm':a.tag,'argv':list(base['argv'])};candidate['argv'][0]=str(lane.bins/pathlib.Path(base['argv'][0]).name)
 if base['program'].startswith('eda/'):
  output=lane.cache/'perf-outputs'/base['program'].split('/',1)[1];output.mkdir(parents=True,exist_ok=True);candidate['argv'][candidate['argv'].index('--out-dir')+1]=str(output)
 arms.extend([base,candidate])
assert len(arms)==120
path=lane.cache/'arms.json';path.write_text(json.dumps(arms));out=a.out or ROOT/'experiments/runtime-parity-3-20261009/R'/(a.tag+'-cpu8.json')
subprocess.run([sys.executable,str(ROOT/'experiments/runtime-parity-3-20261009/tools/pstat.py'),str(path),'--rounds','3','--out',str(out)],check=True)

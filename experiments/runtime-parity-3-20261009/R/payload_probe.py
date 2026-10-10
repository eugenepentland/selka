#!/usr/bin/env python3
"""Build EDA with exact LLVM retained; qualify all 34 designs and sum P6 sites."""
import argparse,gzip,json,os,pathlib,shutil,subprocess,sys
ROOT=pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'experiments/runtime-parity-3-20261009/tools'))
import ce
p=argparse.ArgumentParser();p.add_argument('--compiler',type=pathlib.Path,required=True);p.add_argument('--tag',required=True);a=p.parse_args()
assert pathlib.Path(os.readlink('/proc/self/fd/9')).name.startswith('build')
area=ROOT/'experiments/runtime-parity-3-20261009/R'
snapshot=ROOT/'.mylang-cache/rp3/R/payload-probes'/a.tag;snapshot.mkdir(parents=True,exist_ok=True)
shutil.copyfile(a.compiler.resolve(),snapshot/'compiler');(snapshot/'compiler').chmod(0o755)
lane=ce.Lane(snapshot/'compiler',a.tag);lane.bins.mkdir(parents=True,exist_ok=True)
for kind in ['plain','count']:
 command=[str(lane.compiler),'build',str(ce.EDA_SRC/'src/main.my'),'-o',str(lane.bins/('eda-'+kind)),'--release','--cache-dir',str(lane.cache),'--emit-llvm',str(lane.cache/(kind+'.ll'))]
 lane.cache.mkdir(parents=True,exist_ok=True)
 if kind=='count':command+=['--counters']
 subprocess.run(command,cwd=ce.EDA_SRC,env=dict(os.environ,MYLANG_CORE_RUNTIME_CACHE=str(lane.runtime_cache)),check=True)
 print('built',kind,flush=True)
results=ce.run_eda(lane)
(area/(a.tag+'-eda.json')).write_text(json.dumps(results,indent=1))
assert len(results)==34 and all(r['status']==0 and r['same_output'] and r['counts'] for r in results.values())
summary={};all_copy=0
for label in sorted(results):
 data=json.load(gzip.open(lane.raw/(label+'.json.gz')))
 sites=[s for s in data['sites'] if s['kind']=='record_copy' and s['detail']=='list_push']
 summary[label]={'p6_bytes':sum(s['bytes'] for s in sites),'parse_list_p6_bytes':sum(s['bytes'] for s in sites if 'parse_list' in s['function']),'record_copy':data['kinds']['record_copy'],'parse_list_sites':[s for s in sites if 'parse_list' in s['function']]}
 all_copy+=summary[label]['parse_list_p6_bytes']
receipt={'compiler_sha256':ce.digest(lane.compiler),'tag':a.tag,'p6_bytes':all_copy,'p6_base_bytes':444833472,'p6_fraction':all_copy/444833472,'cells':summary}
(area/(a.tag+'-copies.json')).write_text(json.dumps(receipt,indent=1));print('P6',all_copy,'fraction',receipt['p6_fraction'],flush=True)

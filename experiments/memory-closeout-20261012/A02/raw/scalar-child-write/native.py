import argparse,json,os,sys
from pathlib import Path
root=Path.cwd();sys.path.insert(0,str(root/'experiments/memory-closeout-20261012/A02'))
from qualification_support import *
p=argparse.ArgumentParser();p.add_argument('--mode',required=True);p.add_argument('--ownership',choices=['zero','ordinary'],default='zero');args=p.parse_args()
w=root/'.tmp/memory-closeout/A02/scalar-child-validation';registered=json.loads((w/'registered.json').read_text());compiler=Path(registered['compiler']['path'])
assert sha(compiler)==registered['compiler']['sha256']
flags={'release':['--release'],'debug':['--unoptimized'],'verify':['--release','--verify-facts'],'optimized_debug':['--optimize-debug'],'no_facts':['--release','--no-facts']}[args.mode]
out=fresh_output(w/('native-'+args.ownership+'-'+args.mode));result={'compiler':registered['compiler'],'mode':args.mode,'ownership':args.ownership,'cases':{},'complete':False,'qualified':False}
for name,expected in [('oracle','302 2\n550278 1 1\n'),('reduced',''),('control','rhs\n99 2 1\n')]:
 source=w/'sources'/(name+'.my');directory=out/name;directory.mkdir();binary=directory/'program';llvm=directory/'program.ll';counts=directory/'counts.json'
 row={'source_sha256':sha(source),'expected':expected};result['cases'][name]=row
 row['build']=call([compiler,'build',source,*mode_flags(args.ownership),*flags,'--cache-dir',w/'native-cache','--zig',os.environ['ZIG'],'--counters','--emit-llvm',llvm,'-o',binary],env=clean_env(),timeout=60)
 if row['build']['status']==0:
  row['run']=call([binary],env=dict(clean_env(),MYLANG_COUNTERS=str(counts),MYL_CORE_LEAKCHECK='1'),timeout=20)
  row.update(counter_audit(counts));row.update(artifact_audit(binary,llvm))
  row['pass']=row['run']['status']==0 and row['run']['stdout']==expected and row['run']['stderr']=='' and row['leak_free'] and (args.ownership=='ordinary' or owned_clean(row,row))
  if name=='control':
   row['trap']=call([binary,'bounds'],env=clean_env(),timeout=20)
   row['pass'] &= row['trap']['status']==1 and 'R_LIST_BOUNDS' in row['trap']['stderr'] and row['trap']['stdout']=='rhs\n'
 else:row['pass']=False
 save(out/'results.json',result);print(name,args.ownership,args.mode,row['pass'],flush=True)
if args.ownership=='zero':
 result['overlap_check']=call([compiler,'check',w/'sources/overlap.my','--experimental-zero-rc'],env=clean_env(),timeout=20)
 result['overlap_refused']=result['overlap_check']['status']==1 and 'E_SINGLE_OWNER_OVERLAP' in result['overlap_check']['stderr']
else:result['overlap_refused']=None
result['complete']=True;result['qualified']=all(row['pass'] for row in result['cases'].values()) and result['overlap_refused'] is not False;save(out/'results.json',result)
assert sha(compiler)==registered['compiler']['sha256']
raise SystemExit(0 if result['qualified'] else 1)

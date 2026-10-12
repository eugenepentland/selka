import json,os,sys
from pathlib import Path
root=Path.cwd();sys.path.insert(0,str(root/'experiments/memory-closeout-20261012/A02'))
from qualification_support import *
w=root/'.tmp/memory-closeout/A02/public-constructors-validation';registered=json.loads((w/'registered.json').read_text());compiler=Path(registered['compiler']['path'])
assert sha(compiler)==registered['compiler']['sha256']
out=fresh_output(w/'allocation-controls');result={'compiler':registered['compiler'],'cases':{},'complete':False}
for name,expected in [('fresh_generator','word-9 32\n'),('fresh_manual','word-9 32\n'),('copied_generator','word-9\n'),('copied_manual','word-9\n'),('borrowed_generator','word-9\n'),('borrowed_manual','word-9\n'),('set_characters','3\n')]:
 source=w/'sources'/(name+'.my');directory=out/name;directory.mkdir();binary=directory/'program';llvm=directory/'program.ll';counts=directory/'counts.json'
 row={'source_sha256':sha(source),'expected':expected};result['cases'][name]=row
 row['build']=call([compiler,'build',source,'--experimental-zero-rc','--release','--cache-dir',w/'native-cache','--zig',os.environ['ZIG'],'--counters','--emit-llvm',llvm,'-o',binary],env=clean_env(),timeout=60)
 if row['build']['status']==0:
  row['run']=call([binary],env=dict(clean_env(),MYLANG_COUNTERS=str(counts),MYL_CORE_LEAKCHECK='1'),timeout=20)
  row.update(counter_audit(counts));row.update(artifact_audit(binary,llvm))
  row['pass']=row['run']['status']==0 and row['run']['stdout']==expected and row['run']['stderr']=='' and owned_clean(row,row)
 else:row['pass']=False
 save(out/'results.json',result);print(name,row['pass'],flush=True)
result['complete']=True;result['pass']=all(r['pass'] for r in result['cases'].values());save(out/'results.json',result)
assert sha(compiler)==registered['compiler']['sha256']
raise SystemExit(0 if result['pass'] else 1)

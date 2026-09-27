from pathlib import Path
import gzip,json,statistics,hashlib
p=Path(__file__).resolve().parent
load=lambda name:json.load(gzip.open(p/(name+'.json.gz')))
d=load('results');base=load('accepted-gc-builds')
assert len(d['builds'])==16 and all(x['ok'] for x in d['builds'])
assert len(d['checks'])==16 and all(x['ok'] for x in d['checks'])
assert len(d['runs'])==48 and len(d['counts'])==8 and len(d['samples'])==8
for key,sample in d['samples'].items():
 for side in ['gc','rc']:
  rs=[x for x in d['runs'] if x['key']==key and x['side']==side]
  assert len(rs)==3 and all(x['status']==0 for x in rs)
  assert sample['medians'][side]==statistics.median(x['instructions'] for x in rs)
  if side=='gc':assert all(x['binary_sha256']==base['builds'][key]['sha256'] for x in rs)
 assert sample['rc_gc_ratio']==sample['medians']['rc']/sample['medians']['gc']
 assert len({x['stdout'] for x in d['runs'] if x['key']==key})==1
for x in d['counts']:
 c=x['counts'];assert x['status']==0 and c['runtime']=='rc-v3-counting' and not c['saturated']
 assert c['heap_allocate']==c['retire'] and c['owner_acquire']+c['heap_allocate']==c['owner_release'] and c['hold_acquire']==c['hold_release']
 other=next(y for y in d['counts'] if y['key'].rsplit('.',1)[0]==x['key'].rsplit('.',1)[0] and y['key']!=x['key']);assert c==other['counts']
print('Verified 16 builds/output checks, 48 timing receipts and 8 balanced counted executions against accepted GC.')

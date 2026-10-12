#!/usr/bin/env python3
"""Aggregate complete corpus receipts, retaining failed/censored arms in the denominator.
Only complete nine-round arms receive ratios. Partial-corpus ratios are explicitly
labelled and never reported as full-suite comparisons. Output JSON to stdout.
"""
import argparse,collections,hashlib,json,math,pathlib,statistics
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--spec-dir',type=pathlib.Path,default=pathlib.Path(__file__).with_name('specs'))
p.add_argument('receipts',nargs='+');a=p.parse_args()
expected={json.loads(p.read_text())['cell'] for p in a.spec_dir.glob('*.json')}
expected.discard('lox/vm/step')
assert [sum(c.startswith(g) for c in expected) for g in ['lox/tree/','lox/vm/','eda/']]==[13,13,34]
cells={};receipts=[];binary_identities={}
for arg in a.receipts:
 path=pathlib.Path(arg);d=json.loads(path.read_text());cell=d['spec']['cell']
 names=set(d['spec']['arms']); app=cell.split('/')[0]
 for name,argv in d['spec']['arms'].items():
  binary=argv[0];identity=d['identities'][binary];key=(app,name)
  assert binary_identities.setdefault(key,identity)==identity,(app,name,'binary changed across cells')
 target=cells.setdefault(cell,{'identities':d['identities'],'arms':{name:{'wall_samples':[],'rss_samples':[],'failures':[]} for name in names},'warmups':0,'round_keys':set()})
 assert set(target['arms'])==names,(cell,'arm set changed')
 assert target['identities']==d['identities'],(cell,'identities changed')
 target['warmups']+=d['warmups']
 for name,status in d.get('arm_status',{}).items():
  if status['status']!='ok':target['arms'][name]['failures'].append(status)
 for kind in ['wall_samples','rss_samples']:
  for sample in d[kind]:
   name=sample['arm'];arm=target['arms'][name]
   if kind=='wall_samples':
    key=(name,sample['round']);assert key not in target['round_keys'],(cell,'duplicate round',key)
    target['round_keys'].add(key)
   arm[kind].append(sample['value'])
 receipts.append({'path':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
assert set(cells)==expected,('cell coverage','missing',sorted(expected-set(cells)),'extra',sorted(set(cells)-expected))
armsets={tuple(sorted(d['arms'])) for d in cells.values()};assert len(armsets)==1,('arm coverage differs',armsets)
assert {'zig-safe','zig-fast','rust','go'}<=set(next(iter(armsets)))
for cell,d in cells.items():
 assert d['warmups']==2,(cell,'warmup count')
 for name,arm in d['arms'].items():
  complete=(not arm['failures'] and {(name,r) for r in range(9)}<=(d['round_keys']) and len(arm['wall_samples'])==9 and len(arm['rss_samples'])==3)
  assert complete or arm['failures'],(cell,name,'missing samples without recorded failure')
  arm['complete']=complete
  for field in ['wall_samples','rss_samples']:
   values=arm[field]
   arm[field+'_summary']=None if not complete else {'median':statistics.median(values),'min':min(values),'max':max(values)}
 del d['round_keys']
 for name,arm in d['arms'].items():
  arm['wall_ratio_vs']={ref:arm['wall_samples_summary']['median']/v['wall_samples_summary']['median'] for ref,v in d['arms'].items() if arm['complete'] and v['complete']}
groups={}
for group in ['lox/tree/','lox/vm/','eda/']:
 rows=[d for c,d in cells.items() if c.startswith(group)];names=sorted(rows[0]['arms']);ratios={}
 for name in names:
  ratios[name]={}
  for ref in names:
   values=[d['arms'][name]['wall_ratio_vs'][ref] for d in rows if ref in d['arms'][name]['wall_ratio_vs']]
   gm=math.exp(statistics.mean(math.log(v) for v in values)) if values else None
   ratios[name][ref]={'paired_cells':len(values),'total_cells':len(rows),'full_suite_geomean':gm if len(values)==len(rows) else None,'complete_pair_subset_geomean':gm}
 groups[group]={'cells':len(rows),'complete_cells_by_arm':{name:sum(d['arms'][name]['complete'] for d in rows) for name in names},'wall_ratios':ratios}
print(json.dumps({'receipts':receipts,'binary_sha256_by_application':{app:{name:v for (g,name),v in binary_identities.items() if g==app} for app in ['lox','eda']},'cells':cells,'groups':groups},indent=2))

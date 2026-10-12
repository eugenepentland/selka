#!/usr/bin/env python3
"""Aggregate non-overlapping chunks, retaining all samples and ranges.
Input receipts only (not generated specs). Output JSON to stdout.
"""
import argparse,collections,hashlib,json,math,pathlib,statistics,sys
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--spec-dir',type=pathlib.Path,default=pathlib.Path(__file__).with_name('specs'))
parser.add_argument('receipts',nargs='+')
a=parser.parse_args()
expected={json.loads(p.read_text())['cell'] for p in a.spec_dir.glob('*.json')}
expected.discard('lox/vm/step')
assert len([c for c in expected if c.startswith('lox/tree/')])==13
assert len([c for c in expected if c.startswith('lox/vm/')])==13
assert len([c for c in expected if c.startswith('eda/')])==34
cells={};receipts=[]
for arg in a.receipts:
 p=pathlib.Path(arg);d=json.loads(p.read_text());cell=d['spec']['cell']
 target=cells.setdefault(cell,{'identities':d['identities'],'arms':{},'warmups':0,'round_keys':set()})
 assert target['identities']==d['identities'],(cell,'identities changed')
 target['warmups']+=d['warmups']
 for kind in ['wall_samples','rss_samples']:
  for sample in d[kind]:
   name=sample['arm'];arm=target['arms'].setdefault(name,{'wall_samples':[],'rss_samples':[]})
   if kind=='wall_samples':
    key=(name,sample['round']);assert key not in target['round_keys'],(cell,'duplicate round',key)
    target['round_keys'].add(key)
   arm[kind].append(sample['value'])
 receipts.append({'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
assert set(cells)==expected,('cell coverage','missing',sorted(expected-set(cells)),'extra',sorted(set(cells)-expected))
armsets={tuple(sorted(d['arms'])) for d in cells.values()}
assert len(armsets)==1,('arm coverage differs',armsets)
assert {'zig-safe','zig-fast','rust','go'}<=set(next(iter(armsets)))
for cell,d in cells.items():
 assert d['round_keys']=={(name,rnd) for name in d['arms'] for rnd in range(9)},(cell,'round coverage')
 del d['round_keys']
 for name,arm in d['arms'].items():
  assert len(arm['wall_samples'])==9,(cell,name,'runtime sample count')
  assert len(arm['rss_samples'])==3,(cell,name,'RSS sample count')
  for field in ['wall_samples','rss_samples']:
   values=arm[field];arm[field+'_summary']={'median':statistics.median(values),'min':min(values),'max':max(values)}
 assert d['warmups']==2,(cell,'warmup count')
 for name,arm in d['arms'].items():
  arm['wall_ratio_vs']={ref:arm['wall_samples_summary']['median']/v['wall_samples_summary']['median'] for ref,v in d['arms'].items()}
groups={}
for group in ['lox/tree/','lox/vm/','eda/']:
 rows=[d for c,d in cells.items() if c.startswith(group)]
 if not rows:continue
 names=set(rows[0]['arms']);assert all(set(d['arms'])==names for d in rows)
 ratios={}
 for name in sorted(names):
  ratios[name]={ref:math.exp(statistics.mean(math.log(d['arms'][name]['wall_ratio_vs'][ref]) for d in rows)) for ref in sorted(names)}
 groups[group]={'cells':len(rows),'geomean_wall_ratios':ratios}
print(json.dumps({'receipts':receipts,'cells':cells,'groups':groups},indent=2))

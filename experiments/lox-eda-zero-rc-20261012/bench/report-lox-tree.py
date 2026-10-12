#!/usr/bin/env python3
"""Publish the complete 13-case tree corpus only after every arm is qualified."""
import argparse,csv,gzip,hashlib,json,math,pathlib,statistics
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--root',type=pathlib.Path,default=pathlib.Path('/home/epentland/ai/canopy/mylang-memory-20261012'));p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args();bench=a.root/'experiments/lox-eda-zero-rc-20261012/bench'
names=['mylang-original-rc','mylang-migrated-rc','mylang-zero-rc','zig-fast','zig-safe','rust','go'];expected={json.loads(p.read_text())['cell'] for p in (bench/'frozen-specs').glob('tree-*.json')};assert len(expected)==13
cells={};identities={};receipts=[]
for directory in ['initial-fib','lox-remaining']:
 for path in sorted((bench/'results'/directory).glob('tree-*.json')):
  if path.name.endswith('.spec.json'):continue
  d=json.loads(path.read_text());cell=d['spec']['cell'];assert cell in expected;assert set(d['spec']['arms'])==set(names)
  row=cells.setdefault(cell,{'warmups':0,'identities':d['identities'],'arms':{n:{'wall':{},'rss':[],'failures':[]} for n in names}});assert row['identities']==d['identities'];row['warmups']+=d['warmups']
  for name,argv in d['spec']['arms'].items():assert identities.setdefault(name,d['identities'][argv[0]])==d['identities'][argv[0]],(cell,name,'binary identity changed')
  for name,status in d['arm_status'].items():
   if status['status']!='ok':row['arms'][name]['failures'].append(status)
  for sample in d['wall_samples']:
   arm=row['arms'][sample['arm']];assert sample['round'] not in arm['wall'];arm['wall'][sample['round']]=sample['value']
  for sample in d['rss_samples']:row['arms'][sample['arm']]['rss'].append(sample['value'])
  receipts.append({'path':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
assert set(cells)==expected,('missing cells',expected-set(cells))
for cell,row in cells.items():
 assert row['warmups']==2,(cell,'warmups',row['warmups'])
 for name,arm in row['arms'].items():
  assert not arm['failures'] and set(arm['wall'])==set(range(9)) and len(arm['rss'])==3,(cell,name,'incomplete',len(arm['wall']),len(arm['rss']),arm['failures'])
  for key in ['wall','rss']:
   values=list(arm[key].values()) if key=='wall' else arm[key];arm[key+'_summary']={k:f(values) for k,f in [('median',statistics.median),('min',min),('max',max)]}
def gm(values):return math.exp(statistics.mean(map(math.log,values)))
summary={name:{'complete_cells':13,'wall_ratio_vs':{ref:gm(row['arms'][name]['wall_summary']['median']/row['arms'][ref]['wall_summary']['median'] for row in cells.values()) for ref in names},'largest_case_median_peak_rss_mib':max(row['arms'][name]['rss_summary']['median']/1024 for row in cells.values())} for name in names}
historical=json.load(gzip.open(a.root/'experiments/fs-x-20261009/results/lox-runtime.json.gz','rt'))['summary'];old={'mylang-original-rc':'mylang:release','zig-fast':'zig:release','zig-safe':'zig:release-safe','rust':'rust:release','go':'go:release'}
a.output.mkdir(parents=True,exist_ok=True)
with (a.output/'lox-tree-per-case.csv').open('w',newline='') as f:
 w=csv.writer(f);w.writerow(['cell','arm','wall_median_s','wall_min_s','wall_max_s','child_peak_rss_median_kib','child_peak_rss_min_kib','child_peak_rss_max_kib','historical_cpu10_wall_median_s','historical_rss_kib'])
 for cell,row in sorted(cells.items()):
  case=cell.split('/')[-1]
  for name,arm in row['arms'].items():
   past=historical[case+'/tree'].get(old.get(name,''),{});w.writerow([cell,name,*[arm['wall_summary'][k] for k in ['median','min','max']],*[arm['rss_summary'][k] for k in ['median','min','max']],past.get('median_s'),past.get('maxrss_kib')])
(a.output/'lox-tree-runtime-summary.json').write_text(json.dumps({'coverage':13,'arms':summary,'cells':cells,'binary_sha256':identities,'receipts':receipts},indent=2)+'\n')
lines=['# Full Lox tree comparison','', 'All 13 full tree-interpreter workloads completed across seven arms with matching output oracles. Ratios below are geometric means over all 13 cases; no VM or bytecode subset is included.','', '| Arm | Complete cases | Wall / original RC | Wall / migrated RC | Largest case-median peak RSS (MiB) |','|---|---:|---:|---:|---:|']
for name,s in summary.items():lines.append(f'| {name} | 13/13 | {s["wall_ratio_vs"]["mylang-original-rc"]:.3f} | {s["wall_ratio_vs"]["mylang-migrated-rc"]:.3f} | {s["largest_case_median_peak_rss_mib"]:.3f} |')
lines+=['', '| Reference | Historical Oct9 mylang / reference | Current zero-RC / freshly rerun reference |','|---|---:|---:|']
for ref in names[3:]:
 ratio=gm(historical[c.split('/')[-1]+'/tree']['mylang:release']['median_s']/historical[c.split('/')[-1]+'/tree'][old[ref]]['median_s'] for c in cells);lines.append(f'| {ref} | {ratio:.3f} | {summary["mylang-zero-rc"]["wall_ratio_vs"][ref]:.3f} |')
lines+=['', 'Each current arm has two warmups, nine alternating uninstrumented wall samples and three separate GNU-time child peak-RSS samples, on CPU 8 with a recorded 120-second guest deadline. Whole CLI launch/startup is included; no tree arm failed or was censored. Per-case medians and ranges are in lox-tree-per-case.csv; raw samples, input and binary identities and receipt hashes are preserved in lox-tree-runtime-summary.json.', '', 'Original RC uses the modern original application source. Migrated RC and checked zero-RC share the same migrated source, so their ratio isolates memory-mode behavior on that source, including explicit snapshot copies. This result does not describe the separate VM engine. Managed allocation and RC counters are measured separately; child RSS is not cumulative allocation or managed peak.', '', 'The three mylang arms were built with compiler source e2893d2707cbe057a09abf94e04c4b12d16b7b8b, compiler SHA256 6e7938a14ad4abc46b76c149ef12551b170f6c7e6f462beec2f81db18d40a83d. The final integration gate later rebuilt the compiler to SHA256 8e58720cd72de8632aa48df373d18fc8238d46ec27010f8b182820a0eaaf10fa with unchanged production source bytes; benchmark guests were not rebuilt or relabeled.', '', 'Existing Zig/Rust/Go executables were copied, hashed and freshly rerun, not rebuilt in this session. Historical Oct9 measurements used CPU 10 and different compiler/source/artifact identities. Their group ratios and per-case values are context, not isolated compiler improvements; old receipts do not establish identical reference executable identities. The full 60-cell aggregator remains separate and requires all 26 Lox and 34 EDA cells.', '']
(a.output/'LOX-TREE-COMPARISON.md').write_text('\n'.join(lines));print(json.dumps(summary,indent=2))

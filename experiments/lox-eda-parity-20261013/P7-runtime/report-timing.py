#!/usr/bin/env python3
"""Report completed diagnostic chunks; censored arms never receive a ratio."""
import pathlib,json,statistics,hashlib
root=pathlib.Path.cwd();base=root/'experiments/lox-eda-parity-20261013/P7-runtime/timing-combined-001';plan=json.loads((base/'comparison.json').read_text());report={'purpose':'bounded C1 runtime diagnostic; two cases cannot establish full-corpus parity','cases':{}}
for item in plan['commands']:
 case=item['case'];docs=[];pins={}
 for n in range(10):
  p=base/(case+f'.chunk{n:02}.json');docs.append(json.loads(p.read_text()));pins[str(p)]=hashlib.sha256(p.read_bytes()).hexdigest()
 final=docs[-1];row={'receipt_hashes':pins,'calibration':docs[0]['relative_timeout_policy'],'arms':{}}
 for arm in final['arm_status']:
  status=final['arm_status'][arm];walls=[s['value'] for d in docs for s in d['wall_samples'] if s['arm']==arm];rss=[s['value'] for d in docs for s in d['rss_samples'] if s['arm']==arm]
  entry={'status':status,'wall_samples':walls,'rss_samples_kib':rss}
  if status['status']=='ok':
   assert len(walls)==9 and len(rss)==3,(case,arm,len(walls),len(rss));entry.update(wall_median_seconds=statistics.median(walls),peak_rss_median_kib=statistics.median(rss),peak_rss_max_kib=max(rss))
  row['arms'][arm]=entry
 for arm,entry in row['arms'].items():
  baseline=row['arms']['baseline-relinked'];zig=row['arms']['zig-fast']
  if 'wall_median_seconds' in entry and 'wall_median_seconds' in baseline:
   entry['runtime_vs_baseline_relinked']=entry['wall_median_seconds']/baseline['wall_median_seconds']
   paired=[value/control for value,control in zip(entry['wall_samples'],baseline['wall_samples'])];entry['paired_runtime_vs_baseline_samples']=paired;entry['paired_runtime_vs_baseline_median']=statistics.median(paired)
  if 'wall_median_seconds' in entry and 'wall_median_seconds' in zig:entry['runtime_vs_zig']=entry['wall_median_seconds']/zig['wall_median_seconds']
 report['cases'][case]=row
(base/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({c:{a:{k:v for k,v in x.items() if k not in ['wall_samples','rss_samples_kib']} for a,x in r['arms'].items()} for c,r in report['cases'].items()},indent=2))

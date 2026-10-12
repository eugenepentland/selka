#!/usr/bin/env python3
"""Produce auditable current/historical per-cell tables from the full aggregator.
Historical rows are context only; CPU/toolchain/executable identities differ.
"""
import argparse,csv,gzip,json,pathlib,math
p=argparse.ArgumentParser(description=__doc__);p.add_argument('summary',type=pathlib.Path);p.add_argument('--root',type=pathlib.Path,required=True);p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args()
data=json.loads(a.summary.read_text());assert len(data['cells'])==60;a.output.mkdir(parents=True,exist_ok=True)
historical={name:json.loads(gzip.open(a.root/f'experiments/fs-x-20261009/results/{name}-runtime.json.gz','rt').read()) for name in ['lox','eda']}
labels={'mylang-original-rc':'original RC','mylang-migrated-rc':'migrated RC','mylang-zero-rc':'checked zero-RC','zig-fast':'Zig Fast','zig-safe':'Zig Safe','rust':'Rust','go':'Go'}
oldlox={'zig-fast':'zig:release','zig-safe':'zig:release-safe','rust':'rust:release','go':'go:release','mylang-original-rc':'mylang:release'};oldeda={**{k:k for k in ['zig-fast','zig-safe','rust','go']},'mylang-original-rc':'mylang-final'}
with (a.output/'per-cell.csv').open('w',newline='') as stream:
 writer=csv.writer(stream);writer.writerow(['cell','arm','complete','wall_median_s','wall_min_s','wall_max_s','rss_median_kib','rss_min_kib','rss_max_kib','historical_cpu10_wall_s','historical_rss_kib','failure_statuses'])
 for cell,value in sorted(data['cells'].items()):
  app=cell.split('/')[0]
  if app=='lox':_,engine,case=cell.split('/');old=historical['lox']['summary'][case+'/'+engine];mapping=oldlox
  else:old=historical['eda']['per_case'][cell.split('/',1)[1]];mapping=oldeda
  for arm,metric in sorted(value['arms'].items()):
   wall=metric['wall_samples_summary'] or {};rss=metric['rss_samples_summary'] or {};past=old.get(mapping.get(arm,''),{})
   oldrss=past.get('maxrss_kib') if app=='lox' else (past['rss_exact_mib']*1024 if 'rss_exact_mib' in past else None)
   writer.writerow([cell,arm,metric['complete'],*[wall.get(k) for k in ['median','min','max']],*[rss.get(k) for k in ['median','min','max']],past.get('median_s'),oldrss,';'.join(sorted({v['status'] for v in metric['failures']}))])
lines=['# Fresh full-application comparisons','', 'Current results use CPU 8, the same frozen compiler for all three mylang arms, unchanged canonical inputs, and four existing competitor executables copied and hashed, then freshly rerun; these references were not rebuilt in this session. Each complete arm has two warmups, nine alternating wall samples, and three separate GNU-time child peak-RSS samples. Wall time includes CLI launch and startup. All output oracles are checked; instrumentation is separate.','', 'Ratios below are wall time divided by the comparison arm. Only full groups receive geometric means. Failed or censored arms remain in the stated group denominator; unavailable ratios are not replaced by a subset estimate.','', '| Group | Arm | Complete cells | vs original RC | vs migrated RC | vs Zig Fast | vs Zig Safe | vs Rust | vs Go | Largest case-median peak RSS (MiB) |','|---|---|---:|---:|---:|---:|---:|---:|---:|---:|']
for group,g in data['groups'].items():
 for arm in labels:
  complete=g['complete_cells_by_arm'][arm];ratios=g['wall_ratios'][arm]
  def ratio(ref):
   item=ratios[ref];value=item['full_suite_geomean'];return f'{value:.3f}' if value is not None else f'— ({item["paired_cells"]}/{item["total_cells"]})'
  rss=[v['arms'][arm]['rss_samples_summary']['median']/1024 for c,v in data['cells'].items() if c.startswith(group) and v['arms'][arm]['complete']]
  maxrss=f'{max(rss):.2f}' if rss and complete==g['cells'] else '—'
  lines.append('| '+ ' | '.join([group.rstrip('/'),labels[arm],f'{complete}/{g["cells"]}',*[ratio(ref) for ref in ['mylang-original-rc','mylang-migrated-rc','zig-fast','zig-safe','rust','go']],maxrss])+' |')
lines+=['', '| Group | Comparison reference | Historical mylang / reference | Current checked zero-RC / reference |', '|---|---|---:|---:|']
for group,g in data['groups'].items():
 for ref in ['zig-fast','zig-safe','rust','go']:
  values=[]
  for cell in data['cells']:
   if not cell.startswith(group):continue
   if cell.startswith('lox/'):
    _,engine,case=cell.split('/');row=historical['lox']['summary'][case+'/'+engine];oldmy='mylang:release';oldref=oldlox[ref]
   else:row=historical['eda']['per_case'][cell.split('/',1)[1]];oldmy='mylang-final';oldref=oldeda[ref]
   values.append(row[oldmy]['median_s']/row[oldref]['median_s'])
  assert len(values)==g['cells']
  oldratio=math.exp(sum(map(math.log,values))/len(values));current=g['wall_ratios']['mylang-zero-rc'][ref]['full_suite_geomean']
  lines.append(f'| {group.rstrip("/")} | {labels[ref]} | {oldratio:.3f} | '+(f'{current:.3f}' if current is not None else 'incomplete')+' |')
lines+=['','Historical context is preserved per case in per-cell.csv. The Oct9 receipts used CPU 10 and different compiler/executable identities; no cross-date ratio establishes a compiler or ownership speedup. EDA historical RSS uses rss_exact_mib, excluding the launching Python wait4 high-water floor. The distinct reader/printer EDA subset and expanded Lox bytecode subset are excluded.','', 'The original RC arm isolates the current compiler on the modern original application source. Migrated RC and checked zero-RC share the same migrated source: their comparison includes the cost of implementing explicit value snapshots under each memory mode. RC can retain/share such copies and defer copying until mutation; checked zero-RC owns independent snapshots. Allocation/copy counters are needed to explain that cost; RSS alone cannot show cumulative allocation traffic.','']
(a.output/'COMPARISON.md').write_text('\n'.join(lines));print(a.output/'COMPARISON.md')

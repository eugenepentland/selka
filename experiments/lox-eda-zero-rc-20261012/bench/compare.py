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
lines=['# Fresh full-application comparisons','', 'Current results use CPU 8, the same frozen compiler for all three mylang arms, unchanged canonical inputs, and four existing competitor executables copied and hashed, then freshly rerun; these references were not rebuilt in this session. Each complete arm has two warmups, nine alternating wall samples, and three separate GNU-time child peak-RSS samples. Wall time includes CLI launch and startup. Every completed guest run passes its output oracles; failed or censored guests remain explicit and cannot establish full-size output qualification. Instrumentation is separate.','', 'Ratios below are wall time divided by the comparison arm. Only full groups receive geometric means. Failed or censored arms remain in the stated group denominator; unavailable ratios are not replaced by a subset estimate.','', '| Group | Arm | Complete cells | vs original RC | vs migrated RC | vs Zig Fast | vs Zig Safe | vs Rust | vs Go | Largest case-median peak RSS (MiB) |','|---|---|---:|---:|---:|---:|---:|---:|---:|---:|']
for group,g in data['groups'].items():
 for arm in labels:
  complete=g['complete_cells_by_arm'][arm];ratios=g['wall_ratios'][arm]
  def ratio(ref):
   item=ratios[ref];value=item['full_suite_geomean'];return f'{value:.3f}' if value is not None else f'— ({item["paired_cells"]}/{item["total_cells"]})'
  rss=[v['arms'][arm]['rss_samples_summary']['median']/1024 for c,v in data['cells'].items() if c.startswith(group) and v['arms'][arm]['complete']]
  maxrss=f'{max(rss):.2f}' if rss and complete==g['cells'] else '—'
  lines.append('| '+ ' | '.join([group.rstrip('/'),labels[arm],f'{complete}/{g["cells"]}',*[ratio(ref) for ref in ['mylang-original-rc','mylang-migrated-rc','zig-fast','zig-safe','rust','go']],maxrss])+' |')
failures=[(cell,arm,metric['failures'][0]) for cell,row in sorted(data['cells'].items()) for arm,metric in sorted(row['arms'].items()) if metric['failures']]
if failures:
 lines+=['', 'Uninstrumented guest failures/censors are listed below. These cells stay in their full group denominator; the affected group ratios remain unavailable.', '', '| Cell | Arm | Status | Phase | Deadline (s) |', '|---|---|---|---|---:|']
 for cell,arm,status in failures:lines.append(f'| {cell} | {arm} | {status["status"]} | {status.get("phase","—")} | {status.get("timeout_seconds","—")} |')
lines+=['', '| VM case | Original RC median (s) | Migrated RC median (s) | Zero-RC median (s) or status | Zero / original | Zero / migrated | Original / zero-RC peak RSS (MiB) |', '|---|---:|---:|---:|---:|---:|---:|']
for cell,row in sorted(data['cells'].items()):
 if not cell.startswith('lox/vm/'):continue
 arms=row['arms'];original=arms['mylang-original-rc'];migrated=arms['mylang-migrated-rc'];zero=arms['mylang-zero-rc']
 def median(metric):
  return f'{metric["wall_samples_summary"]["median"]:.6f}' if metric['complete'] else '/'.join(sorted({v['status'] for v in metric['failures']})) or 'unavailable'
 values=[cell.rsplit('/',1)[1],median(original),median(migrated),median(zero)]
 for ref in ['mylang-original-rc','mylang-migrated-rc']:
  value=zero['wall_ratio_vs'].get(ref);values.append(f'{value:.3f}' if value is not None else '—')
 rss=[]
 for metric in [original,zero]:rss.append(f'{metric["rss_samples_summary"]["median"]/1024:.3f}' if metric['complete'] else 'unavailable')
 values.append(' / '.join(rss))
 lines.append('| '+' | '.join(values)+' |')
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
lines+=['','Historical context is preserved per case in per-cell.csv. The Oct9 receipts used CPU 10 and different compiler/executable identities; no cross-date ratio establishes a compiler or ownership speedup. EDA historical RSS uses rss_exact_mib, excluding the launching Python wait4 high-water floor. Historical Lox RSS is GNU-time child peak RSS maximized across timing rounds; current Lox RSS is the median of three separately measured child peak samples. Their RSS estimators therefore differ. The distinct reader/printer EDA subset and expanded Lox bytecode subset are excluded.','', 'This conservative migration increases Lox explicit copy sites from 2 to 184, with 76 staging temporaries; EDA increases from 3 to 843 copy sites across 121 modules, with source lines increasing from 21,792 to 21,856. Its measured costs describe this migration, not an inherent lower bound for every possible zero-RC implementation. The original RC arm isolates the current compiler on the modern original application source. Migrated RC and checked zero-RC share the same migrated source: their comparison includes the cost of implementing explicit value snapshots under each memory mode. RC can retain/share such copies and defer copying until mutation; checked zero-RC owns independent snapshots. Allocation/copy counters are needed to explain that cost; RSS alone cannot show cumulative allocation traffic.','']
lines += ['Across the 13 tree cases, the matched-case geometric ratio of zero-RC to original RC child peak RSS is 1.5932. Both largest case-median peaks occur in tree/trees: 47,568 KiB for original RC and 98,296 KiB for zero-RC. These are child resident-memory measurements, separate from managed counters.', '', 'Allocation attribution supplies a concrete explanation for the copy burden, without constituting CPU profiling. Full-size VM Fibonacci counted runs record 2,712,877,890 allocations and 664,969,560,232 cumulative allocated bytes in checked zero-RC, versus 460 allocations and 505,496 bytes in both RC arms. Managed peak is 831,536 versus 416,368 bytes, with zero exit-live bytes. vm::run accounts for 621,857,290,208 allocation bytes; its per-opcode frame.copy() boundary appears at migrated vm.my line 434.', '', 'EDA rds3+flat counted runs record 2,588,797,232 cumulative allocated bytes in zero-RC versus 191,320,104 in original RC. kicad_sch_textbox::overlaps_of accounts for 1,123,681,184 bytes of allocation plus reallocation growth, and sexpr_ast::as_list for 429,875,760 bytes. The textbox path iterates ordered[i+1:len(ordered)] on each outer iteration (kicad_sch_textbox.my line 137); the core slice builder constructs a fresh list and explicitly copies managed elements in zero_rc (build_list_methods.zig lines 274–300). sexpr_ast.my lines 81–84 returns children.copy() from as_list. These source paths corroborate the allocation counters; they do not prove the fraction of CPU time spent at each site.', '', 'All 102 full-size EDA counted runs completed correctly (34 designs across three mylang arms). Cumulative allocated bytes summed over those independent runs are 3,118,944,232 for original RC, 3,119,064,808 for migrated RC and 24,324,668,504 for zero-RC. The matched-case cumulative-allocation geometric ratio of zero-RC to migrated RC is 7.0514. Largest managed peak is 51,415,480 bytes for either RC arm versus 86,587,128 for zero-RC; all exit-live bytes are zero. Zero-RC compiler/runtime/shared retain-release, share-mark and uniqueness-test events are zero. See ../eda-counted-summary.json and its raw gzip archive for complete metrics.', '', 'Across the 34 EDA cases, the matched-case geometric zero/original child peak-RSS ratio is 1.3550. Both largest case-median child peaks occur in rds3+flat: 53,964 KiB for original RC versus 90,132 KiB for zero-RC. This is separate from managed peak and cumulative allocation traffic.', '', 'Full-size Lox counted coverage is 26/26 cells for each RC arm and 20/26 for checked zero-RC. Six VM instrumented runs were censored at 120 seconds: equality, invocation, method_call, properties, string_equality and zoo_batch. On the exact common 20-cell subset, cumulative allocated bytes summed across independent runs are 10,024,638,912 for original RC, 10,121,124,840 for migrated RC and 7,466,718,651,880 for zero-RC. These sums measure allocation traffic; managed peak remains a per-case quantity. On those same 20 cases, original RC allocates 114,979,544 times, migrated RC 114,997,063 times and zero-RC 16,578,222,271 times. All completed counted runs exit with zero live managed bytes; zero-RC compiler/runtime/shared retain-release and uniqueness-test counts are zero. Its 16,576,177,741 direct destructions are not RC events.', '', 'Counted guest runs have their own 120-second deadline. A counted VM censor does not imply an uninstrumented runtime censor; the runtime status and denominators above are derived solely from uninstrumented receipts.', '', 'Benchmark mylang guests were built with compiler SHA256 6e7938a14ad4abc46b76c149ef12551b170f6c7e6f462beec2f81db18d40a83d. The later final integration gate rebuilt the compiler to 8e58720cd72de8632aa48df373d18fc8238d46ec27010f8b182820a0eaaf10fa with unchanged production source bytes. Existing benchmark guests were not rebuilt or relabeled.', '']
(a.output/'COMPARISON.md').write_text('\n'.join(lines));print(a.output/'COMPARISON.md')

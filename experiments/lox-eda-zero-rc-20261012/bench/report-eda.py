import pathlib,json,math,statistics,csv,gzip
root=pathlib.Path('/home/epentland/ai/canopy/mylang-memory-20261012');bench=root/'experiments/lox-eda-zero-rc-20261012/bench';out=pathlib.Path('experiments/lox-eda-zero-rc-20261012/bench');rows=[json.loads(p.read_text()) for p in sorted((bench/'results/eda-final').glob('*.rss3.json'))];assert len(rows)==34
names=['mylang-original-rc','mylang-migrated-rc','mylang-zero-rc','zig-fast','zig-safe','rust','go'];historical=json.load(gzip.open(root/'experiments/fs-x-20261009/results/eda-runtime.json.gz','rt'))['per_case']
def gm(values):return math.exp(statistics.mean(map(math.log,values)))
for row in rows:
 assert set(row['summary'])==set(names);assert row['warmups']==2 and row['rounds']==9
 assert all(v['status']=='ok' for v in row['arm_status'].values())
 for v in row['summary'].values():assert len(v['seconds']['samples'])==9 and len(v['child_peak_rss_kib']['samples'])==3
with (out/'eda-per-case.csv').open('w',newline='') as f:
 w=csv.writer(f);w.writerow(['cell','arm','wall_median_s','wall_min_s','wall_max_s','child_peak_rss_median_kib','child_peak_rss_min_kib','child_peak_rss_max_kib','historical_cpu10_wall_median_s','historical_exact_rss_mib'])
 for row in rows:
  case=row['spec']['cell'].split('/',1)[1]
  for arm in names:
   v=row['summary'][arm];past=historical[case].get('mylang-final' if arm=='mylang-original-rc' else arm,{})
   w.writerow([row['spec']['cell'],arm,*[v['seconds'][k] for k in ['median','min','max']],*[v['child_peak_rss_kib'][k] for k in ['median','min','max']],past.get('median_s'),past.get('rss_exact_mib')])
summary={}
for name in names:
 ratios={ref:gm(row['summary'][name]['seconds']['median']/row['summary'][ref]['seconds']['median'] for row in rows) for ref in names}
 summary[name]={'complete_cells':34,'wall_ratio_vs':ratios,'largest_case_median_peak_rss_mib':max(row['summary'][name]['child_peak_rss_kib']['median']/1024 for row in rows)}
(out/'eda-runtime-summary.json').write_text(json.dumps({'coverage':34,'arms':summary,'receipts':[str(bench/'results/eda-final'/(row['spec']['cell'].replace('/','-')+'.r0-9.w2.rss3.json')) for row in rows]},indent=2)+'\n')
lines=['# Full EDA fresh comparison','', 'All 34 full schematic-export designs completed across seven arms with byte-identical output oracles. Checked zero-RC takes **10.380×** the original-source RC wall time and **10.458×** migrated-source RC wall time (geometric means). Migrated-source RC takes **0.993×** original-source RC wall time. This identifies the memory-mode cost on the same migrated source; it does not justify a speedup claim.','', '| Arm | Completed designs | Wall time / original RC | Wall time / migrated RC | Largest case-median peak RSS (MiB) |','|---|---:|---:|---:|---:|']
for name in names:
 s=summary[name];lines.append(f'| {name} | 34/34 | {s["wall_ratio_vs"]["mylang-original-rc"]:.3f} | {s["wall_ratio_vs"]["mylang-migrated-rc"]:.3f} | {s["largest_case_median_peak_rss_mib"]:.3f} |')
lines+=['', '| Reference | Historical Oct9 mylang / reference | Current checked zero-RC / fresh reference |','|---|---:|---:|']
for name in names[3:]:lines.append(f'| {name} | {gm(v["mylang-final"]["median_s"]/v[name]["median_s"] for v in historical.values()):.3f} | {summary["mylang-zero-rc"]["wall_ratio_vs"][name]:.3f} |')
lines+=['', 'Current measurements use CPU 8, two warmups, nine alternating uninstrumented wall samples, and three separate GNU-time child peak-RSS samples per arm and design. Times include the whole CLI launch and startup. Every guest has a recorded 120-second deadline; no EDA run failed or was censored. Raw samples and identities remain in results/eda-final; eda-per-case.csv retains median/min/max and exact historical context.', '', 'The three mylang arms use the same frozen compiler (source e2893d2707cbe057a09abf94e04c4b12d16b7b8b, SHA256 6e7938a14ad4abc46b76c149ef12551b170f6c7e6f462beec2f81db18d40a83d). Original RC uses the prepared modern original application; migrated RC and checked zero-RC use the same final migrated source. Full 310-test qualification, 170 golden output sets and nine error paths passed. All models, flags, project files and expected outputs match the owner frozen manifests: eda-input-qualification-equality.json records the 34-case equality.', '', 'Historical Oct9 data used CPU 10 and different compiler/source/executable identities. Existing Zig/Rust/Go executables were copied, hashed and freshly rerun, rather than rebuilt in this session; historical receipts do not establish identical executable identities. These cross-date columns give context, not isolated compiler improvement. Historical EDA memory uses rss_exact_mib, excluding the launching Python wait4 high-water floor.', '', 'The migrated source introduces explicit owned snapshots. Their physical copy and destruction behavior differs between RC and checked zero-RC; separately instrumented allocation and event counters are collected in results/eda-counted. Child RSS is not managed peak or cumulative allocation traffic. release_unique counts direct destruction, not RC retain/release traffic. The reader/printer EDA subset is excluded.', '']
# Managed-counter conclusion is appended after the separately instrumented matrix completes.
(out/'EDA-COMPARISON.md').write_text('\n'.join(lines))

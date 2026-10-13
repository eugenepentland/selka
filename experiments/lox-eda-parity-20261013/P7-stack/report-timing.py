import pathlib,json,statistics
base=pathlib.Path(__file__).resolve().parent;out=base/'timing-001';plan=json.loads((out/'comparison.json').read_text());results=[]
for item in plan['commands']:
 case=item['case'];docs=[json.loads((out/(case+f'.chunk{n:02}.json')).read_text()) for n in range(10)];wall={a:{} for a in ['zig-fast','baseline','candidate']};rss={a:[] for a in wall};statuses={}
 for d in docs:
  statuses.update(d['arm_status'])
  for r in d['wall_samples']:
   if r.get('status','ok')=='ok':wall[r['arm']][r['round']]=r['value']
  for r in d['rss_samples']:
   if r.get('status','ok')=='ok':rss[r['arm']].append(r['value'])
 rows={'case':case,'status':statuses,'wall_seconds':{a:statistics.median(list(v.values())) if v else None for a,v in wall.items()},'rss_kib':{a:statistics.median(v) if v else None for a,v in rss.items()},'valid_wall_samples':{a:len(v) for a,v in wall.items()},'valid_rss_samples':{a:len(v) for a,v in rss.items()}}
 if all(len(v)==9 for v in wall.values()):
  ratios=[wall['candidate'][i]/wall['baseline'][i] for i in range(9)];rows.update(candidate_baseline_paired_ratios=ratios,candidate_baseline_median=statistics.median(ratios),candidate_wins=sum(r<1 for r in ratios),candidate_zig_median=statistics.median([wall['candidate'][i]/wall['zig-fast'][i] for i in range(9)]))
 results.append(rows)
(out/'report.json').write_text(json.dumps({'scope':'Controlled C2 LLVM runtime-object replacement only; no compiler/application speedup attribution','cases':results},indent=2)+'\n');print(json.dumps(results,indent=2))

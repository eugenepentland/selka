#!/usr/bin/env python3
"""Preserve full per-cell managed counters with explicit coverage and RC audit."""
import argparse,json,pathlib
p=argparse.ArgumentParser(description=__doc__);p.add_argument('receipts',nargs='+',type=pathlib.Path);p.add_argument('--expected',type=int,required=True);a=p.parse_args()
cells={}
for path in a.receipts:
 d=json.loads(path.read_text());assert d['cell'] not in cells;cells[d['cell']]=d
assert len(cells)==a.expected,(len(cells),a.expected)
names={'mylang-original-rc','mylang-migrated-rc','mylang-zero-rc'}
for d in cells.values():assert set(d['arms'])==names
summary={}
for arm in sorted(names):
 rows=[d['arms'][arm] for d in cells.values()];good=[r for r in rows if r['metrics'] is not None];metrics={}
 for key in good[0]['metrics'] if good else []:
  values=[r['metrics'][key] for r in good];metrics[key]={'min':min(values),'max':max(values),'sum_over_independent_runs':sum(values)}
 kinds={key:{'min':min(r['counters']['kinds'][key]['count'] for r in good),'max':max(r['counters']['kinds'][key]['count'] for r in good)} for key in good[0]['counters']['kinds']} if good else {}
 runtime_totals={key:{'min':min(r['counters']['totals'][key] for r in good),'max':max(r['counters']['totals'][key] for r in good)} for key in good[0]['counters']['totals']} if good else {}
 summary[arm]={'runtime_total_ranges':runtime_totals,'complete_cells':len(good),'total_cells':a.expected,'metrics':metrics,'event_count_ranges':kinds}
print(json.dumps({'separate_instrumented_runs':True,'release_unique_is_direct_destruction_not_rc':True,'cells':cells,'summary':summary},indent=2))

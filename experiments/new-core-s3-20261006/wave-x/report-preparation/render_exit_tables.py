#!/usr/bin/env python3
"""Render qualified S3 exit receipts without rounding the gate decision."""
import argparse,json
from pathlib import Path
p=argparse.ArgumentParser()
p.add_argument('--performance',type=Path,required=True)
p.add_argument('--counts',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args()
perf=json.loads(a.performance.read_text()); counts=json.loads(a.counts.read_text())
assert perf['valid'] and perf['all_within_both_limits'] and counts['valid']
assert len(perf['rows'])==40 and set(perf['rows'])==set(counts['rows'])
assert not a.output.exists()
lines=["All paired cells are **4096 / 64**. Cycles use each row's registry unit; decisions use unrounded ratios.",'',
 '| Row | Unit | Old | New | Rust | Zig ReleaseSafe | New/old | New/Zig |',
 '|---|---|---:|---:|---:|---:|---:|---:|']
for row,data in perf['rows'].items():
 sizes=[data['sizes'][str(n)] for n in (4096,64)]
 assert all(x['within_both_limits'] for x in sizes)
 values=[' / '.join(f"{x['configurations'][name]['cycles_per_unit']:.3f}" for x in sizes) for name in ('old core --release','new core release','Rust','Zig ReleaseSafe')]
 values+=[' / '.join(f"{x[key]:.3f}" for x in sizes) for key in ('new_over_old','new_over_zig')]
 lines.append('| '+row+' | '+data['unit']+' | '+' | '.join(values)+' |')
lines+=['','Counts below are static tagged caller sites in the shared size-parameterized binary. They have the same static scope at both sizes. `unknown` preserves missing tag or clock authority; opaque runtime/callee/header effects are not proved zero.','',
 '| Row | Inner loops | Inner stores | Of which count=1 | Other constant stores | Dynamic reads | Saturated reads | Parent stores | Timed nonloop stores | Setup stores | Unknown/callee loops | Timed opaque calls |',
 '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|']
for row,data in counts['rows'].items():
 total=data['timing']['totals']; tagged=data['count_tag_metadata_survives']
 def field(scope,key):
  return str(total[scope][key]) if total and tagged else 'unknown'
 values=[str(total['timed_innermost_loops']) if total else 'unknown']
 values += [field('timed_innermost',key) for key in ('count_stores','constant_one_count_stores','other_constant_count_stores','dynamic_count_reads','saturated_count_reads')]
 values += [field(scope,'count_stores') for scope in ('timed_parent_exclusive','timed_nonloop','before_start_loops_exclusive')]
 values += [str(total[key]) if total else 'unknown' for key in ('unknown_or_callee_loops','timed_opaque_call_sites')]
 lines.append('| '+row+' | '+' | '.join(values)+' |')
a.output.write_text('\n'.join(lines)+'\n')

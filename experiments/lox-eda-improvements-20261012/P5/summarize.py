#!/usr/bin/env python3
"""Summarize tiny overlap probes, excluding retained failed/argument-miss attempts."""
from pathlib import Path
import json
HERE=Path(__file__).resolve().parent
FIELDS=('alloc_bytes','realloc_added_bytes','buffer_copies','buffer_copy_bytes','list_copies','list_copy_bytes')
summary={}
for phase in ('baseline','indexed','indices'):
    summary[phase]={}
    for n in (64,128):
        d=json.loads((HERE/f'{phase}-{n}-counters.json').read_text());t=d['totals']
        assert t['live_bytes_at_exit']==0
        assert all(t[k]==0 for k in ('runtime_retains','runtime_releases','shared_retains','shared_releases','share_marks','share_bytes'))
        assert all(d['kinds'][k]['count']==0 for k in ('retain','release','unique_test'))
        functions={f['name']:{k:f[k] for k in FIELDS} for f in d['functions'] if 'overlaps_of' in f['name'] or 'support_sort::' in f['name']}
        summary[phase][str(n)]={'total_traffic':t['alloc_bytes']+t['realloc_added_bytes'],'peak_live_bytes':t['peak_live_bytes'],'live_bytes_at_exit':t['live_bytes_at_exit'],'buffer_copies':t['buffer_copies'],'functions':functions}
        assert f'{n},1000,' in (HERE/f'{phase}-{n}-output.txt').read_text()
        if phase=='indices':
            assert t['buffer_copies']==6
            assert all(f['buffer_copies']==0 for name,f in functions.items() if 'support_sort::' in name)
(HERE/'counter-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
for phase,rows in summary.items():
    for n,row in rows.items():print(phase,n,row['total_traffic'],row['peak_live_bytes'])

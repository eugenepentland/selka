#!/usr/bin/env python3
"""Bounded allocation counters; no elapsed-time measurement."""
from pathlib import Path
import os,json,subprocess,sys
binary=Path(sys.argv[1]).resolve()
root=Path(__file__).resolve().parent
rows=[]
for arm in ('fresh','published_setters'):
    counts=root/(arm+'-counters.json')
    r=subprocess.run([str(binary)]+(['old'] if arm=='published_setters' else []),env=dict(os.environ,MYLANG_COUNTERS=str(counts)),capture_output=True,text=True,timeout=30)
    (root/(arm+'.stdout')).write_text(r.stdout);(root/(arm+'.stderr')).write_text(r.stderr)
    assert r.returncode==0 and r.stdout.strip()=='True True True True',(arm,r.returncode,r.stdout,r.stderr)
    d=json.loads(counts.read_text());t=d['totals']
    assert t['runtime_retains']==0 and t['runtime_releases']==0 and t['live_bytes_at_exit']==0
    rows.append(dict(arm=arm,stdout=r.stdout.strip(),totals=t,functions=[f for f in d['functions'] if any(x in f['name'] for x in ('allocate_call_env','allocate_env','set_env_slot','object::new_env'))]))
(root/'counter-summary.json').write_text(json.dumps(rows,indent=2)+'\n')
print(json.dumps(rows,indent=2))

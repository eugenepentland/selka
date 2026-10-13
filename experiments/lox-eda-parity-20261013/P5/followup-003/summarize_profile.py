#!/usr/bin/env python3
from collections import Counter
import hashlib
import gzip
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
spec = json.loads((HERE.parent / 'followup-001/prepared-common001-profile.json').read_text())
outputs = json.loads((HERE.parent / 'followup-001/current-common001-profile-outputs.json').read_text())
pids = {r['guest_pid'] for r in outputs}
leaf = []
pattern = re.compile(r'^\s*(\S+)\s+(\d+)/(\d+)\s+(\S+):\s+([0-9a-f]+)\s+(.+?)\s+\((.+)\)$')
for line in (HERE / 'perf-leaf.txt').read_text().splitlines():
    if not line.strip():
        continue
    match = pattern.match(line)
    assert match, line
    comm, pid, tid, event, ip, symbol, dso = match.groups()
    leaf.append(dict(comm=comm, pid=int(pid), tid=int(tid), event=event, ip=ip, symbol=symbol, dso=dso))
guests = [s for s in leaf if s['pid'] in pids]
excluded = [s for s in leaf if s['pid'] not in pids]
app = [s for s in guests if s['dso'] == spec['binary']]
report = (HERE / 'perf-report-all.txt').read_text()
recorded = int(re.search(r'# Samples:\s+(\d+)', report).group(1))
lost = int(re.search(r'# Total Lost Samples:\s+(\d+)', report).group(1))
assert len(leaf) == recorded
blocks = (HERE / 'perf-script.txt').read_text().strip().split('\n\n')
header = re.compile(r'^\S+\s+(\d+)/(\d+)\s+')
frame = re.compile(r'^\s+[0-9a-f]+\s+(.+?)\s+\((.+)\)$')
chains = []
for block in blocks:
    lines = block.splitlines()
    match = header.match(lines[0])
    assert match, lines[0]
    if int(match.group(1)) not in pids:
        continue
    frames = [frame.match(l) for l in lines[1:] if l.strip()]
    assert all(frames)
    chains.append([{'symbol':f.group(1), 'dso':f.group(2)} for f in frames])
assert len(chains) == len(guests)
known_app_chains = [c for c in chains if any(f['dso'] == spec['binary'] for f in c)]
rows = lambda c: [{'name':k, 'samples':v} for k,v in c.most_common()]
summary = {'label':'C1 RDS3-flat cycles samples only; no timing comparison',
    'recorded_samples':recorded, 'lost_samples':lost, 'included_guest_pid_samples':len(guests),
    'excluded_driver_other_pid_samples':len(excluded), 'included_guest_app_dso_leaf_samples':len(app),
    'included_guest_other_dso_leaf_samples':len(guests)-len(app),
    'guest_pids':sorted(pids), 'seen_guest_pids':sorted({s['pid'] for s in guests}),
    'excluded_by_pid':rows(Counter(str(s['pid'])+':'+s['comm'] for s in excluded)),
    'guest_leaf_dso_counts':rows(Counter(s['dso'] for s in guests)),
    'guest_leaf_symbols':rows(Counter(s['symbol'] for s in guests)),
    'guest_app_dso_leaf_symbols':rows(Counter(s['symbol'] for s in app)),
    'guest_callchains_with_frames':sum(bool(c) for c in chains),
    'guest_callchains_with_app_frames':len(known_app_chains),
    'callgraph_limit':'DWARF captured but native application call chains do not reconstruct; no allocation caller or inclusive attribution claim.' if not known_app_chains else 'Inspect available application frame counts before caller attribution.',
    'raw_sha256':hashlib.sha256(gzip.decompress((HERE / 'C1-rds3-flat.perf.data.gz').read_bytes())).hexdigest(),
    'decodes':{f:hashlib.sha256((HERE/f).read_bytes()).hexdigest() for f in ['perf-leaf.txt','perf-script.txt','perf-report-all.txt']}}
(HERE / 'profile-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps({k:v for k,v in summary.items() if k not in ['decodes','guest_leaf_symbols','guest_app_dso_leaf_symbols','guest_leaf_dso_counts']},indent=2))
print('Top guest leaf symbols:',summary['guest_leaf_symbols'][:15])

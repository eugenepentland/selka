#!/usr/bin/env python3
"""Read-only paired diagnostic summary; no trimming and no compound benefit claim."""
import hashlib,json,math,random,statistics
from pathlib import Path
HERE=Path(__file__).resolve().parent
plan=json.loads((HERE/'timing-plan.json').read_text())
def paired(values):
 rng=random.Random(42)
 med=[statistics.median(rng.choices(values,k=len(values))) for _ in range(10000)]
 med.sort()
 return {'ratios':values,'median':statistics.median(values),'geometric_mean':math.exp(statistics.mean([math.log(x) for x in values])),'bootstrap_median_95_interval':[med[249],med[9749]],'bootstrap_iterations':10000,'bootstrap_seed':42}
summary={'protocol':'three approved C2 prototype diagnostics;9paired rounds each,2warmups,3chunks, freshZig3x/120cap;runtime-only, no sample exclusion','cases':{}}
for case in ('fib','binary_trees','string_equality'):
 docs=[json.loads((HERE/'diagnostics'/f'{case}.chunk{k}.json').read_text()) for k in range(3)]
 for k,d in enumerate(docs):
  assert d['rounds']==3 and d['round_start']==k*3 and d['warmups']==(2 if k==0 else 0)
  assert d['measurement_harness_sha256']==plan['measurer_sha256']
  assert d['relative_timeout_policy']['factor']==3 and d['relative_timeout_policy']['absolute_ceiling_seconds']==120
  assert all(v['status']=='ok' for v in d['arm_status'].values()),d['arm_status']
  assert d['identities']==docs[0]['identities']
  for f,h in d['identities'].items():assert hashlib.sha256(Path(f).read_bytes()).hexdigest()==h
 maps={arm:{s['round']:s['value'] for d in docs for s in d['wall_samples'] if s['arm']==arm} for arm in ('zig-fast','baseline','candidate')}
 assert all(set(v)==set(range(9)) for v in maps.values())
 summary['cases'][case]={'sample_seconds':maps,'medians_seconds':{arm:statistics.median(v.values()) for arm,v in maps.items()},'candidate_over_baseline':paired([maps['candidate'][i]/maps['baseline'][i] for i in range(9)]),'candidate_over_zig':paired([maps['candidate'][i]/maps['zig-fast'][i] for i in range(9)]),'baseline_over_zig':paired([maps['baseline'][i]/maps['zig-fast'][i] for i in range(9)]),'relative_timeout_policy':docs[0]['relative_timeout_policy'],'receipts':[str(HERE/'diagnostics'/f'{case}.chunk{k}.json') for k in range(3)]}
(HERE/'paired-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
for case,row in summary['cases'].items():
 p=row['candidate_over_baseline'];print(case,'candidate/baseline',p['median'],'interval',p['bootstrap_median_95_interval'],'candidate/Zig',row['candidate_over_zig']['median'])

import importlib.util,json,statistics
from pathlib import Path
spec=importlib.util.spec_from_file_location('compare',Path('experiments/d9-rc-acceptance-20260926/compare.py').resolve());m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
states={s:json.loads((m.WORK/(s+'-builds.json')).read_text()) for s in ('gc','rc')}
result={'compiler_commit':states['rc']['compiler_commit'],'compiler_sha256':states['rc']['compiler_sha256'],'kind':'early diagnostic; not complete corpus acceptance','samples':{}}
for p in m.programs():
 if p['id'] not in {'parity/suite/binary_trees','parity/suite/fannkuch_redux','parity/suite/matmul','parity/suite/nbody'}:continue
 for arm in ('qbe','llvm'):
  key=p['build_key']+'.'+arm
  if not all(states[s]['builds'].get(key,{}).get('ok') for s in states):continue
  for s in states:assert m.sha(m.WORK/'bin'/s/key)==states[s]['builds'][key]['sha256']
  runs={s:m.pc.run_spec(p,m.WORK/'bin'/s/key,'early-'+s+'-'+arm,'') for s in states}
  checks={s:m.pc.check(p,run) for s,run in runs.items()}
  assert all(c['ok'] for c in checks.values()),checks
  counts={s:[] for s in states}
  for i in range(3):
   for s in (('gc','rc') if i%2==0 else ('rc','gc')):
    row=m.pc.perf_counts(runs[s],2);assert row['status']==0 and row.get('instructions',0)>0,row
    counts[s].append(row)
  ratio=statistics.median(c['instructions'] for c in counts['rc'])/statistics.median(c['instructions'] for c in counts['gc'])
  result['samples'][p['id']+'|'+arm]={'checks':checks,'counts':counts,'ratio':ratio}
  m.write(m.WORK/'early-counts-39f.json',result);print(p['id'],arm,ratio,flush=True)

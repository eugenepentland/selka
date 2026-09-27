import json,pathlib
w=pathlib.Path(__file__).parent
p=w/'validation.json'
data=json.loads(p.read_text()) if p.exists() else json.loads(__import__('gzip').decompress((w/'validation.json.gz').read_bytes()))
assert len(data['rows'])==28
assert sum(len(row['runs']) for row in data['rows'])==32
for row in data['rows']:
 assert row['build_status']==0
 for run in row['runs']:
  c=run['counts']
  assert run['status']==(1 if run['expected'] else 0)
  assert not run['expected'] or run['expected'] in run['stderr']
  assert c['heap_allocate']==c['retire'] and c['owner_release']==c['heap_allocate']+c['owner_acquire']
  assert c['hold_acquire']==c['hold_release']
# Before/after codes, outputs and all counters must agree, including trap cleanup.
for backend in ['qbe','llvm']:
 before={row['case']:row for row in data['rows'] if row['backend']==backend and row['side']=='before'}
 after={row['case']:row for row in data['rows'] if row['backend']==backend and row['side']=='after'}
 for key in before:
  for a,b in zip(before[key]['runs'],after[key]['runs']):
   assert (a['status'],a['stdout'])==(b['status'],b['stdout']),(key,a,b)
   # Physical stack frames may shrink under LLVM; unlike logical limits, the
   # number of activations before the native floor is not a fixed budget.
   ignored={'hold_acquire','hold_release'} if key=='floor' else set()
   assert {k:v for k,v in a['counts'].items() if k not in ignored}=={k:v for k,v in b['counts'].items() if k not in ignored},(key,a,b)
   trace=lambda run:'\n'.join(line for line in run['stderr'].splitlines() if not line.startswith('MYLANG_RC_COUNTS '))
   assert trace(a)==trace(b),(key,a,b)
print('all paired controls passed',flush=True)

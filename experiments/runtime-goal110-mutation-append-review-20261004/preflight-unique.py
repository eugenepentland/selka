import hashlib,json,re
from pathlib import Path
from datetime import datetime,timezone
ROOT=Path.cwd(); w=ROOT.parent/'goal110-unique-capture-20261004'
p=w/'.mylang-cache/goal110-unique-capture-debug/native-differential/native-differential.json'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def artifact(a):assert sha(a['path'])==a['sha256'] and Path(a['path']).stat().st_size==a['bytes']
d=json.loads(p.read_text());assert d['status']=='passed' and d['source_revision']=='d4c28bdace208ee284fe22cc63f074b183990967'
for a in [*d['compilers'].values(),*d['tools'].values(),d['fixture'],d['runner']]:artifact(a)
for x in d['builds']:assert x['result']['status']==0;artifact(x['binary'])
for x in d['compiler_receipts'].values():
 artifact(x['artifact']);r=json.loads(Path(x['artifact']['path']).read_text());assert r==x['receipt'] and r['status']=='complete' and r['exit_status']==0
 assert r['sources_before']==r['sources_after'] and sha(r['compiler_path'])==r['compiler_sha256']
for name,h in d['production_source_hashes'].items():assert sha(w/name)==h
seen=set();success=errors=budgets=0
for c in d['comparisons']:
 a,b=c['outcomes']['before'],c['outcomes']['after']
 for field in ['status','stdout','stderr']:assert a[field]==b[field]
 if 'runtime_options' in c:
  key=(c['config'],c['runtime_options']);assert key not in seen;seen.add(key)
  code='R_STEP_LIMIT' if '--max-steps' in c['runtime_options'] else 'R_FRAME_LIMIT'
  assert b['status']==1 and b['stdout']=='' and f'error[{code}]' in b['stderr'];budgets+=1;continue
 kind,index,count=c['case'];key=(c['config'],kind,index,count);assert key not in seen;seen.add(key)
 for outcome in [a,b]:assert outcome['command'][1:]==list(map(str,c['case']))
 idx=index+2 if index<0 else index;values=[7,11];code=None
 if (kind in [0,1] or kind in [2,3,8] and count>0) and not 0<=idx<2:code='R_LIST_BOUNDS'
 elif kind==0:
  values[idx]=count;value=sum(values)+1
  if not -(1<<63)<=value<(1<<63):code='R_OVERFLOW'
 elif kind==1:value=values[idx]*100+13
 elif kind in [2,3,8]:
  total=0
  for step in range(1,max(count,0)+1):
   old=values[idx];values[idx]+=step
   if kind!=8:values[idx]%=1000003;total+=values[idx]+(old if kind==3 else 0)
  value=sum(values)+total
 else:value={4:13,5:33,6:13,7:36}[kind]
 if code:
  assert c['oracle']=={'failure':code};assert b['status']==1 and b['stdout']=='41\n' and f'error[{code}]' in b['stderr'];errors+=1
 else:
  expected={'value':value,'status':value%256,'stdout':f'41\n{value}\n'};assert c['oracle']==expected
  assert b['status']==expected['status'] and b['stdout']==expected['stdout'];success+=1
  if kind==5 and c['config'].startswith(('rc-v5-counting','rc-v5-sites')):
   counts=[s for s in b['stderr'].splitlines() if s.startswith('MYLANG_RC_COUNTS ')];assert len(counts)==1 and json.loads(counts[0].split(' ',1)[1])['hold_acquire']>0
assert len(d['comparisons'])==d['comparison_count']==872 and d['execution_count']==1744 and len(d['builds'])==14
out={'reviewed_utc':datetime.now(timezone.utc).isoformat(),'status':'passed','kind':'independent saved-oracle/direct-argv/status/stream replay and live identity check; no new executions','source_revision':d['source_revision'],'native_receipt':str(p),'native_receipt_sha256':sha(p),'paired_outcomes':len(d['comparisons']),'recorded_native_executions':1744,'successful_pairs':success,'failure_pairs':errors,'budget_refusal_pairs':budgets,'live_native_guests':14,'compilers':2,'script_sha256':sha(Path(__file__))}
(ROOT/'.mylang-cache/goal110-review-20261004-0535/preflight-unique.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out))

from pathlib import Path
import gzip,json,statistics,hashlib
p=Path(__file__).resolve().parent
load=lambda n:json.load(gzip.open(p/(n+'.json.gz')))
def balanced(c):
 assert c['runtime']=='rc-v3-counting' and not c['saturated']
 assert c['heap_allocate']==c['retire']
 assert c['owner_acquire']+c['heap_allocate']==c['owner_release']
 assert c['hold_acquire']==c['hold_release']
d=load('measurements');assert len(d['builds'])==32 and len(d['runs'])==64
for b in d['builds']:
 assert b['status']==0
 name=f"{b['case']}-{b['side']}-{b['backend']}-{'stats' if b['stats'] else 'rc'}.qbe-manifest"
 m=load(name);assert m['backend']==b['backend']
 if b['backend']=='llvm':assert m['optimization']=='3' and m['lto'] and not m['thin_lto']
for case in d['sources']:
 for backend in ['qbe','llvm']:
  pair=[]
  for side in ['before','after']:
   rows=[x for x in d['runs'] if x['case']==case and x['backend']==backend and x['side']==side]
   assert len(rows)==4 and all(x['status']==0 for x in rows)
   timings=[x for x in rows if not x.get('stats')]
   assert d['medians'][case+'-'+side+'-'+backend]==statistics.median(x['instructions'] for x in timings)
   counts=next(x['counts'] for x in rows if x.get('stats'));balanced(counts);pair.append(counts)
  assert pair[0]==pair[1]
 assert len({x['stdout'] for x in d['runs'] if x['case']==case})==1
for side in ['before','after']:
 for case in d['sources']:
  cs=[x['counts'] for x in d['runs'] if x['case']==case and x['side']==side and x.get('stats')];assert cs[0]==cs[1]
g=load('guests');assert len(g['runs'])==56
assert all(x['status']==0 and json.loads(x['stdout'])['failed']==0 and json.loads(x['stdout'])['cached']==0 for x in g['runs'])
assertions=sum(json.loads(x['stdout'])['passed'] for x in g['runs'])
c=load('controls');assert len(c['runs'])==48
for x in c['runs']:
 assert x['build_status']==0
 m=load(f"{x['case']}-{x['side']}-{x['backend']}-{x['mode']}.qbe-manifest")
 assert m['backend']==x['backend']
 if x['backend']=='llvm':assert m['optimization']=='3' and m['lto'] and not m['thin_lto']
 if x['case']=='positive':assert x['status']==0 and x['stdout']==''
 else:
  code={'overflow':'R_OVERFLOW','bounds':'R_LIST_BOUNDS','arena':'R_LIST_BOUNDS','steps':'R_STEP_LIMIT','iteration':'R_LIST_ITERATION_MUTATION'}[x['case']]
  assert x['status']==1 and code in x['stderr'] and x['stdout']=='entered\n'
 if x['mode']=='rc':balanced(x['counts'])
for case in ['positive','bounds','overflow','arena','steps','iteration']:
 for backend in ['qbe','llvm']:
  pair=[x['counts'] for x in c['runs'] if x['case']==case and x['backend']==backend and x['mode']=='rc'];assert pair[0]==pair[1]
a=load('accepted');base=load('accepted-gc-builds');assert len(a['runs'])==24 and len(a['ratios'])==8
for key,v in a['ratios'].items():
 rows=[x for x in a['runs'] if x['key']==key];assert len(rows)==3
 assert all(x['status']==0 and x['binary_sha256']==base['builds'][key]['sha256'] for x in rows)
 assert v['gc']==statistics.median(x['instructions'] for x in rows) and v['rc_gc']==v['rc']/v['gc']
 name,backend=key.rsplit('.',1)
 case={'parity-micro-alloc_churn':'alloc','parity-micro-list_append_sum':'append','parity-suite-sieve':'sieve','parity-suite-fannkuch_redux':'fannkuch'}[name]
 assert v['rc']==d['medians'][case+'-after-'+backend]
native={x['file']:x for x in json.loads((p/'native-identity.json').read_text())}
for case in ['alloc','fannkuch','append']:
 for backend in ['qbe','llvm']:
  assert native[f'{case}-before-{backend}-rc']['text_sha256']==native[f'{case}-after-{backend}-rc']['text_sha256']
e=load('emission')
for case in d['sources']:
 before={x['function']:x for x in e if x['case']==case and x['side']=='before'}
 after={x['function']:x for x in e if x['case']==case and x['side']=='after'}
 if case=='sieve':assert before['main']['nonheld']==0 and after['main']['nonheld']==4 and after['main']['holds']==3
 else:assert all(v['il_sha256']==after[k]['il_sha256'] for k,v in before.items())
print(f'Verified {assertions} uncached guest assertions, 48 paired controls, 72 timing receipts, 16 unchanged counted workload runs, and all native/backend identities.')

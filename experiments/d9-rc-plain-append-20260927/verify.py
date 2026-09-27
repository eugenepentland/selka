from pathlib import Path
import gzip,json,statistics
p=Path(__file__).resolve().parent
load=lambda name:json.load(gzip.open(p/(name+'.json.gz')))
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
g=load('guests');assert len(g['runs'])==40
assert all(x['status']==0 and json.loads(x['stdout'])['failed']==0 and json.loads(x['stdout'])['cached']==0 for x in g['runs'])
assert sum(json.loads(x['stdout'])['passed'] for x in g['runs'])==364
c=load('controls');assert len(c['runs'])==40
for x in c['runs']:
 assert x['build_status']==0
 if x['case']=='zero':assert x['status']==0 and x['stdout']=='entered\n4\n'
 else:
  code={'growth':'R_MEMORY_BUDGET','overflow':'R_OVERFLOW','bounds':'R_LIST_BOUNDS','iteration':'R_LIST_ITERATION_MUTATION'}[x['case']]
  assert x['status']==1 and code in x['stderr'] and x['stdout']=='entered\n'
 if x['mode']=='rc':balanced(x['counts'])
s=load('standalone');assert len(s['runs'])==2 and all(x['status']==0 for x in s['runs'])
assert s['runs'][0]['counts']==s['runs'][1]['counts'];balanced(s['runs'][0]['counts'])
a=load('accepted');base=load('accepted-gc-builds');assert len(a['runs'])==24 and len(a['ratios'])==8
for key,v in a['ratios'].items():
 rows=[x for x in a['runs'] if x['key']==key];assert len(rows)==3
 assert all(x['status']==0 and x['binary_sha256']==base['builds'][key]['sha256'] for x in rows)
 assert v['gc']==statistics.median(x['instructions'] for x in rows) and v['rc_gc']==v['rc']/v['gc']
 name,backend=key.rsplit('.',1)
 case={'parity-micro-alloc_churn':'alloc','parity-micro-list_append_sum':'append','parity-suite-sieve':'sieve','parity-suite-fannkuch_redux':'fannkuch'}[name]
 assert v['rc']==d['medians'][case+'-after-'+backend]
print('Verified 364 guest assertions, 40 paired controls, 72 timing receipts, 16 unchanged counted runs, and two balanced standalone runs.')

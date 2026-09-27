from pathlib import Path
import gzip,json,statistics
p=Path(__file__).resolve().parent
read=lambda name:json.load(gzip.open(p/(name+'.json.gz')))
m=read('measurements');checks=read('guests');controls=read('controls');eq=read('final-equivalence')
assert len(m['builds'])==24 and len(m['runs'])==48
for name,source in m['sources'].items():
 for backend in ['qbe','llvm']:
  pair=[]
  for side in ['before','after']:
   rs=[x for x in m['runs'] if x['case']==name and x['backend']==backend and x['side']==side]
   assert len(rs)==4 and all(x['status']==0 for x in rs)
   assert len({x['stdout'] for x in rs})==1
   assert m['medians'][f'{name}-{side}-{backend}']==statistics.median(x['instructions'] for x in rs if not x.get('stats'))
   c=next(x['counts'] for x in rs if x.get('stats'));pair.append(c)
   assert c['runtime']=='rc-v3-counting' and not c['saturated']
   assert c['heap_allocate']==c['retire'] and c['owner_acquire']+c['heap_allocate']==c['owner_release'] and c['hold_acquire']==c['hold_release']
  assert pair[1]['unique_check']<pair[0]['unique_check']
  assert {k:v for k,v in pair[0].items() if k!='unique_check'}=={k:v for k,v in pair[1].items() if k!='unique_check'}
 assert len({x['stdout'] for x in m['runs'] if x['case']==name})==1
assert len(checks['runs'])==36
assert sum(json.loads(x['stdout'])['passed'] for x in checks['runs'])==340
assert all(x['status']==0 and json.loads(x['stdout'])['failed']==0 for x in checks['runs'])
assert len(controls['runs'])==32
clean=lambda s:'\n'.join(l for l in s.splitlines() if not l.startswith('MYLANG_RC_COUNTS '))
for name in ['growth','zero','overflow','bounds']:
 for backend in ['qbe','llvm']:
  for mode in ['gc','rc']:
   a,b=[x for x in controls['runs'] if (x['case'],x['backend'],x['mode'])==(name,backend,mode)]
   assert (a['side'],b['side'])==('before','after')
   assert (a['status'],a['stdout'],clean(a['stderr']))==(b['status'],b['stdout'],clean(b['stderr']))
   assert a['status']==(0 if name=='zero' else 1)
   if mode=='rc':
    for row in [a,b]:
     c=row['counts'];assert c['heap_allocate']==c['retire'] and c['owner_acquire']+c['heap_allocate']==c['owner_release'] and c['hold_acquire']==c['hold_release']
    assert {k:v for k,v in a['counts'].items() if k!='unique_check'}=={k:v for k,v in b['counts'].items() if k!='unique_check'}
assert len(eq['emissions'])==3 and all(x['functions_equal'] for x in eq['emissions'])
assert len(eq['builds'])==12 and all(x['status']==0 and x['before_text_sha256']==x['final_text_sha256'] for x in eq['builds'])
print('Verified 24 builds, 36 timing runs, 12 balanced count runs, 340 assertions, 32 paired controls, 12 native text identities.')

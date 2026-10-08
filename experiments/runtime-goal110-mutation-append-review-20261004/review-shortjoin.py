import hashlib,json,statistics,sys
from pathlib import Path
from datetime import datetime,timezone
ROOT=Path.cwd();BASE=ROOT.parent
sys.path.insert(0,str(ROOT/'benchmarks/runtime/expanded'));from registry import checksum
sys.path.insert(0,str(ROOT/'benchmarks/runtime'));from compare_candidate import bootstrap

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text())
def replay(path,repeat):
 d=read(path);assert d['status']=='complete';outcomes=0;rows=[]
 screen=d['six_arm_screen'];sp=Path(screen['path'] if isinstance(screen,dict) else screen)
 if not sp.is_absolute():sp=path.parents[2]/sp
 assert sha(sp)==(screen['sha256'] if isinstance(screen,dict) else d['six_arm_screen_sha256'])
 plans={(p['case'],p['profile']):p for p in read(sp)['plans']}
 for arm,fp in d['binaries'].items():assert sha(fp)==d['binary_hashes_before_after'][arm]
 for r in d['rows']:
  p=r['plan'];assert p==plans[p['case'],p['profile']]
  expected=checksum(p['case'],p['size'],p['iterations'],p['seed']);assert p['expected']==expected
  values={};seen=set()
  for s in r['samples']:
   assert s['checksum']==expected and s['exit_status']==0 and s['kernel_ns']>0
   key=(s['arm'],s['round']);assert key not in seen;seen.add(key);values.setdefault(s['arm'],{})
   if s['round']>=0:values[s['arm']][s['round']]=s['kernel_ns']/p['iterations']
   outcomes+=1
  assert seen=={(arm,n) for arm in values for n in range(-d['warmups'],d['rounds'])}
  meds={a:statistics.median(v.values()) for a,v in values.items()}
  assert meds==r.get('medians_ns_per_op',r.get('medians_ns_per_iteration'))
  candidate='after' if 'after-llvm' in values else 'candidate';ratios={}
  for backend in ['llvm','qbe']:
   ca=candidate+'-'+backend;be='before-'+backend;ratio=meds[ca]/meds[be]
   declared=r['after_before_ratios'][backend] if 'after_before_ratios' in r else r['comparisons'][backend]['candidate_to_before'];assert ratio==declared
   ratios[backend]={'after_before':ratio,'before_ns':meds[be],'after_ns':meds[ca]}
   if repeat:ratios[backend]['independent_paired_95']=bootstrap([values[ca][n] for n in range(d['rounds'])],[values[be][n] for n in range(d['rounds'])],p['case']+'/'+p['profile']+'/'+backend)
  rows.append({'case':p['case'],'profile':p['profile'],'ratios':ratios,'calibration':p['calibration']})
 return {'path':str(path),'sha256':sha(path),'measurement_session_id':d.get('measurement_session_id',d.get('session_id')),'paired_outcomes':outcomes,'live_binary_bindings':len(d['binaries']),'rows':rows,'rounds':d['rounds'],'warmups':d['warmups']}
a=BASE/'goal110-join-short-20261004/.mylang-cache/goal110-join-short'
paths=[(a/'short-before-after.json',False),(a/'short-repeat.json',True)]
r=[replay(p,repeat) for p,repeat in paths]
assert r[1]['measurement_session_id'] is not None
out={'reviewed_utc':datetime.now(timezone.utc).isoformat(),'status':'passed','kind':'independent paired oracle, median, ratio, live binary and screen-plan replay; exploratory evidence only','paired_outcomes':sum(x['paired_outcomes'] for x in r),'reports':r,'script_sha256':sha(Path(__file__))}
p=ROOT/'benchmarks/runtime/candidates/goal110-shortjoin-448ee20c-20261004-review.json'
with p.open('x') as f:json.dump(out,f,indent=2);f.write('\n')
print(json.dumps({'status':'passed','paired_outcomes':out['paired_outcomes'],'repeat_results':r[1]['rows']}))

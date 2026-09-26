"""Exact historical27 parity +3 schematic +13 VM comparison through pc.py."""
import concurrent.futures,hashlib,importlib.util,json,os,statistics,subprocess,sys,time
from pathlib import Path
HERE=Path(__file__).resolve().parent
TREE=HERE.parent
BASE=TREE/'.tmp-perf43-scoped/baseline'
os.environ['PC_WORK']=str(HERE)
spec=importlib.util.spec_from_file_location('pc',TREE/'experiments/perf-gc-dict-20260925/scripts/pc.py')
pc=importlib.util.module_from_spec(spec);spec.loader.exec_module(pc)
historical=json.loads((TREE/'experiments/perf-gc-dict-20260925/results.json').read_text())
parity={key.rsplit('|',1)[0] for key in historical['samples'] if key.startswith('parity/')}
programs=[p for p in pc.programs() if p['id'] in parity or p['id'].startswith(('schematic/','lox/vm/'))]
assert len(parity)==27 and len(programs)==43,(len(parity),len(programs))
compiler=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-d9-stage3f-prep/.tmp-stage3f/install-rootlive/bin/mylang')
base_state=json.loads((BASE/'state/base.json').read_text())
assert base_state['compiler_sha256']=='48427e9ac1c01b74e60d1b4c098c8fc149a6b5fef3c07e110c7fb4ba16cbb545'

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def write(path,item):path.write_text(json.dumps(item,indent=2)+'\n')
def load(path):return json.loads(path.read_text())

def build():
 state={'compiler':str(compiler),'compiler_sha256':sha(compiler),'compiler_commit':'178d43dc','source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=TREE,text=True).strip(),'program_ids':[p['id'] for p in programs],'builds':{},'source_sha256':{str(p.relative_to(TREE)):sha(p) for root in [TREE/'bench/parity',TREE/'src/schematic/guest',pc.LOX_PORT] for p in sorted(root.rglob('*.my'))},'provider_sha256':sha(pc.SCHEMATIC_PROVIDER)}
 jobs={}
 for p in programs:
  for arm in ['qbe','llvm']:
   key=p['build_key']+'.'+arm
   if key in jobs:continue
   binary=HERE/'bin/current'/key
   cmd,cwd=pc.build_command(p,str(compiler),arm,binary,TREE/'.tmp-perf43-scoped'/('guest-'+arm))
   cmd=[str(TREE/'scripts/build-slot.sh'),'build',*cmd]
   jobs[key]={'bin':binary,'cmd':cmd,'cwd':cwd}
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
  futures={pool.submit(pc.do_build,job):key for key,job in jobs.items()}
  for future in concurrent.futures.as_completed(futures):
   key=futures[future];outcome=future.result();state['builds'][key]=outcome
   write(HERE/'builds.json',state)
   print('build',key,'PASS' if outcome['ok'] else 'FAIL',outcome.get('stderr','')[-1000:] if not outcome['ok'] else '',flush=True)
 schematic=next(p for p in programs if p['kind']=='schematic')
 cmd,cwd=pc.emit_command(schematic,str(compiler));
 emit=subprocess.run(cmd,cwd=cwd,capture_output=True,env=pc.clean_env(),timeout=1200)
 assert emit.returncode==0,emit.stderr.decode()
 state['schematic_declared']=pc.declared_of(emit.stdout)
 state['schematic_il_sha256']=hashlib.sha256(pc.il_text(emit.stdout).encode()).hexdigest()
 write(HERE/'builds.json',state)
 assert all(x['ok'] for x in state['builds'].values())

def measure():
 state=load(HERE/'builds.json')
 result={'meta':{'compiler_commit':state['compiler_commit'],'source_commit':state['source_commit'],'compiler_sha256':state['compiler_sha256'],'baseline_commit':'60b668cf','baseline_compiler_sha256':base_state['compiler_sha256'],'cpu':2,'perf_reps':3,'harness':'experiments/perf-gc-dict-20260925/scripts/pc.py','vm_size':'tree-calibrated, historical harness configuration','program_ids':[p['id'] for p in programs],'status':'corrected default candidate; awaiting complete acceptance results','binaries':{},'source_sha256':state['source_sha256'],'provider_sha256':state['provider_sha256']},'samples':{}}
 if (HERE/'results43.json').exists():
  previous=load(HERE/'results43.json')
  assert previous['meta']['compiler_sha256']==result['meta']['compiler_sha256']
  assert previous['meta']['source_sha256']==result['meta']['source_sha256']
  result=previous
 for p in programs:
  for arm in ['qbe','llvm']:
   buildkey=p['build_key']+'.'+arm;key=p['id']+'|'+arm
   while buildkey not in state['builds'] or (p['kind']=='schematic' and 'schematic_declared' not in state):
    time.sleep(1)
    try:state=load(HERE/'builds.json')
    except json.JSONDecodeError:continue
   assert state['builds'][buildkey]['ok'],(buildkey,state['builds'][buildkey])
   base=BASE/'bin/base'/buildkey;current=HERE/'bin/current'/buildkey
   assert sha(base)==base_state['builds'][buildkey]['sha256'],buildkey
   assert sha(current)==state['builds'][buildkey]['sha256'],buildkey
   result['meta']['binaries'][buildkey]={'base':sha(base),'current':sha(current)}
   if key in result['samples'] and 'ratio' in result['samples'][key]: continue
   runs={side:pc.run_spec(p,binary,side+'-'+arm,base_state['il']['schematic']['declared'] if side=='base' else state.get('schematic_declared')) for side,binary in [('base',base),('current',current)]}
   checks={side:pc.check(p,run) for side,run in runs.items()}
   row={'checks':checks};result['samples'][key]=row
   if not all(check['ok'] for check in checks.values()):
    print('CHECK FAIL',key,checks,flush=True);write(HERE/'results43.json',result);continue
   samples={side:[] for side in runs}
   for rep in range(3):
    for side in (['base','current'] if rep%2==0 else ['current','base']):
     one=pc.perf_counts(runs[side],2)
     assert one.get('status')==0 and 'instructions' in one,(key,side,one)
     samples[side].append(one)
   med={side:statistics.median(x['instructions'] for x in values) for side,values in samples.items()}
   row.update(perf=samples,medians=med,ratio=med['current']/med['base'])
   print(key,'ratio',row['ratio'],med,flush=True)
   write(HERE/'results43.json',result)
 expected={p['id']+'|'+arm for p in programs for arm in ['qbe','llvm']}
 complete=set(result['samples'])==expected and all('ratio' in r and all(c['ok'] for c in r['checks'].values()) for r in result['samples'].values())
 result['acceptance']={'complete':complete,'arms':{}}
 accepted=complete
 for arm in ['qbe','llvm']:
  ratios={k:r['ratio'] for k,r in result['samples'].items() if k.endswith('|'+arm) and 'ratio' in r}
  geomean=statistics.geometric_mean(ratios.values()) if ratios else None
  outliers={k:v for k,v in ratios.items() if v>1.3}
  passed=len(ratios)==43 and geomean<=1.05 and not outliers
  result['acceptance']['arms'][arm]={'count':len(ratios),'geomean':geomean,'outliers':outliers,'passed':passed}
  accepted=accepted and passed
  print('SUMMARY',arm,len(ratios),geomean,'over1.3',outliers,flush=True)
 result['acceptance']['passed']=bool(accepted)
 result['meta']['status']='PASS: complete stage3 performance acceptance' if accepted else 'FAIL: stage3 performance acceptance not met'
 write(HERE/'results43.json',result)
 print('ACCEPTANCE','PASS' if accepted else 'FAIL',flush=True)
 if not accepted:raise SystemExit(1)

if __name__=='__main__':
 if sys.argv[1]=='build':build()
 elif sys.argv[1]=='measure':
  if sha(compiler)=='cdd9bed601bb0ade5705c5af8c962e7d10c55463128bba7fb57c915b271ac5cd':
   print('Measurement deferred: this frozen compiler omits ref_local liveness; await corrected joined compiler.',flush=True)
  else:measure()
 else:raise SystemExit('expected build|measure')

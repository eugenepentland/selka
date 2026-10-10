#!/usr/bin/env python3
"""Run the already reviewed final measurement tools, preserving each stage receipt."""
import argparse,ast,gzip,hashlib,json,os,re,shutil,subprocess,sys,time
from pathlib import Path
ROOT=Path.cwd()
AREA=ROOT/'experiments/runtime-parity-3-20261009'
TOOLS=AREA/'tools'
sys.path.insert(0,str(TOOLS))
import qualify_tree,timing_data
BASE=Path('/home/epentland/.cache/mylang/rp3-base-41ed360fb/bin/mylang')
parser=argparse.ArgumentParser()
parser.add_argument('--tag',default='final')
parser.add_argument('--run',default='timing-run-01')
args=parser.parse_args()
assert re.fullmatch(r'[a-z0-9-]+',args.tag)
assert re.fullmatch(r'timing-run-[0-9]+',args.run)
TAG,RUN=args.tag,args.run
COMPILE_TAG=f'x-{TAG}-{RUN}-compile'
FINAL=ROOT/'.mylang-cache/rp3/compilers'/TAG/'release-fast/bin/mylang'
OUT=AREA/'X'/RUN
LOG=ROOT/'.tmp/rp3'/RUN

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def git(*args): return subprocess.check_output(['git',*args],text=True).strip()
def write(p,d): p.write_text(json.dumps(d,indent=1)+'\n')
def archive(p):
 data=p.read_bytes(); target=p.with_suffix(p.suffix+'.gz');assert not target.exists()
 with target.open('wb') as f:
  with gzip.GzipFile(filename='',mode='wb',fileobj=f,mtime=0,compresslevel=9) as z: z.write(data)
 assert gzip.decompress(target.read_bytes())==data
 p.unlink()
 return {'path':str(target.relative_to(ROOT)),'raw_sha256':hashlib.sha256(data).hexdigest(),'gzip_sha256':sha(target)}

def main():
 assert ROOT.name=='codex-runtime-parity-3' and 10 in os.sched_getaffinity(0), 'launch directly from coordinator, with CPU10 available'
 assert not git('status','--porcelain','--untracked-files=no')
 gate_path=AREA/'X'/f'gates-{TAG}'/'receipt.json'
 gate=json.loads(gate_path.read_text())
 ce_bins=ROOT/'.mylang-cache/rp3/ce/bin'/TAG
 assert Path(gate['guest_binaries']['directory']).resolve()==ce_bins.resolve()
 assert gate['complete'] and gate['fuzz_cases_per_family']==200
 assert sha(FINAL)==gate['release_fast_compiler']['sha256']
 assert sha(BASE)=='b6db112b3faeab165422d2da80e64afa94c4135cf83cd7abe3eb41cd15308131'
 assert git('rev-parse','main')==gate['main_commit']
 targets=['results/lox-runtime.json','results/eda-runtime.json','results/parity-pair.json',*[f'results/all46-{n}.json' for n in (1,2,3)],'X/compile-times.json','X/final-exit-counts.json','X/hot-counts.json','X/hot-counts.md',*[f'X/profile-{family}-{tag}.json' for family in ('alloc','text') for tag in ('base','final')],'X/r5-four-arms.json','X/r5-timed-identities.json','X/r5-cpu8.json','X/r5-cpu10.json','X/text-ops-bound-spec.json','X/text-ops-bound.json','X/nbody-bound-spec.json','X/nbody-bound.json','X/gap.json','X/gap.md','X/review-perf.json','logs/all46-build.log','logs/parity-pair.stdout.txt','logs/parity-pair.stderr.txt',*[f'logs/all46-{n}.log' for n in (1,2,3)]]
 for name in targets:
  path=AREA/name;assert not path.exists() and not path.with_suffix(path.suffix+'.gz').exists(),('preserve prior output; prepare a deliberate continuation',path)
 for name in [f'.mylang-cache/rp3/compile-times/{COMPILE_TAG}',*[f'{parent}/{RUN}-{label}' for parent in ('.mylang-cache/u2/profile','.mylang-cache/rp3/s2-profile') for label in ('base','final')]]:
  assert not (ROOT/name).exists(),('preserve prior cache; prepare a deliberate continuation',name)
 OUT.mkdir(exist_ok=False);LOG.mkdir(exist_ok=False)
 head=git('rev-parse','HEAD');corpora=qualify_tree.corpora_identity()
 assert corpora=={k:v for k,v in gate['corpora'].items() if k!='unchanged_after_gates'}
 assert gate['corpora']['unchanged_after_gates'] and gate['guest_binaries']['unchanged_after_gates']
 changed=git('diff','--name-only',gate['source_commit'],head).splitlines()
 prefix='experiments/runtime-parity-3-20261009/'
 assert all(name.startswith(prefix) and not name.startswith(prefix+'tools/') and Path(name).suffix not in {'.py','.sh'} for name in changed),('non-evidence change after qualification',changed)
 result={'complete':False,'candidate_tag':TAG,'measurement_run':RUN,'qualification_receipt':{'path':str(gate_path.relative_to(ROOT)),'sha256':sha(gate_path)},'source_commit':head,'qualified_commit':gate['source_commit'],'integrated_main':gate['main_commit'],'base_sha256':sha(BASE),'final_sha256':sha(FINAL),'corpora':corpora,'evidence_only_changes_after_qualification':changed,'steps':[],'archives':[]}
 env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1',RP3_FINAL=str(FINAL),RP3_CE_TAG=TAG,RP3_TAG=f'x-{TAG}-{RUN}',MYLANG_SLOT_POLL='1',TMPDIR=str(LOG),ZIG_LOCAL_CACHE_DIR=str(ROOT/'.zig-cache-rp3'),MYLANG_CORE_RUNTIME_CACHE=str(ROOT/f'.mylang-cache/runtime-rp3-x-{TAG}-{RUN}'))
 Path(env['MYLANG_CORE_RUNTIME_CACHE']).mkdir(exist_ok=True)
 def stable():
  assert git('rev-parse','HEAD')==head
  assert git('rev-parse','main')==gate['main_commit']
  assert not git('status','--porcelain','--untracked-files=no')
  assert sha(BASE)==result['base_sha256'] and sha(FINAL)==result['final_sha256']
  assert qualify_tree.corpora_identity()==corpora
  assert all(sha(Path(gate['guest_binaries']['directory'])/name)==digest for name,digest in gate['guest_binaries']['sha256'].items())
 def run(name,argv,build=False):
  stable(); argv=list(map(str,argv))
  if build: argv=[str(ROOT/'scripts/build-slot.sh'),'build',*argv]
  path=LOG/(name+'.log'); print('RUN',name,flush=True); start=time.time()
  with path.open('x') as f: status=subprocess.run(argv,env=env,stdout=f,stderr=subprocess.STDOUT).returncode
  row={'name':name,'command':argv,'status':status,'seconds':time.time()-start,'log':str(path.relative_to(ROOT)),'log_sha256':sha(path)}
  result['steps'].append(row);write(OUT/'receipt.json',result);stable()
  if status: raise RuntimeError(name+' failed: '+path.read_text(errors='replace')[-4000:])
  print('PASS',name,flush=True)
 py=[sys.executable,'-B']
 run('compile-times',[*py,TOOLS/'compile_times.py','--base',BASE,'--candidate',FINAL,'--tag',COMPILE_TAG,'--out',AREA/'X/compile-times.json'],True)
 run('exit-counts',[*py,TOOLS/'final_exit_counts.py','--base-tag','base','--candidate-tag',TAG,'--out',AREA/'X/final-exit-counts.json'])
 run('hot-counts',[*py,TOOLS/'hot_counts.py','--tag',TAG,'--out',AREA/'X'])
 for label,tag in (('base','base'),('final',TAG)):
  for family,helper,cache in [('alloc','U2/profile_alloc.py','.mylang-cache/u2/profile'),('text','S2/profile_text.py','.mylang-cache/rp3/s2-profile')]:
   cache_tag=f'{RUN}-{label}'
   assert not (ROOT/cache/cache_tag).exists(),('preserve prior profile',cache,cache_tag)
   run('profile-'+family+'-'+label,[*py,AREA/helper,'--tag',tag,'--cache-tag',cache_tag,'--repeat','40','--out',AREA/'X'/('profile-'+family+'-'+label+'.json')],True)
 run('timing-prep',['bash',TOOLS/'timing-prep.sh'])
 # Exact final row binaries from the timing runner, not an assumed CE equivalent.
 template=AREA/'X/tool-audit/r5-four-arms.template.json'
 spec=json.loads(template.read_text());spec.pop('instruction');spec['ready']=True
 identity=[]
 for cell in spec['cells']:
  assert set(cell['arms'])=={'actual-m0','reconstructed','probe','final'}
  row=cell['row']; timed=ROOT/'.mylang-cache/rp3/all46'/('row_'+row+'_new')
  old=ROOT/'.mylang-cache/rp3/all46'/('row_'+row+'_old')
  assert sha(old)==cell['arms']['actual-m0']['sha256']
  ce=ce_bins/('row-'+row+'-plain')
  assert sha(ce)==gate['guest_binaries']['sha256'][ce.name]
  identity.append({'row':row,'ce_binary':str(ce),'ce_sha256':sha(ce),'timed_sha256':sha(timed),'identical':sha(ce)==sha(timed)})
  cell['arms']['final']={'binary':str(timed),'sha256':sha(timed)}
  for arm in cell['arms'].values(): assert sha(arm['binary'])==arm['sha256']
 write(AREA/'X/r5-four-arms.json',spec);write(AREA/'X/r5-timed-identities.json',identity)
 run('r5-cpu8',[*py,TOOLS/'r5_cpu8.py','--tools',TOOLS,'--spec',AREA/'X/r5-four-arms.json','--out',AREA/'X/r5-cpu8.json'],True)
 lox=ROOT/'.mylang-cache/lox/results';before=set(lox.glob('*-runtime'))
 run('lox',['bash',TOOLS/'part3.sh','lox'])
 new=set(lox.glob('*-runtime'))-before;assert len(new)==1,new
 source=new.pop()/'runtime.json';target=AREA/'results/lox-runtime.json';assert not target.exists()
 shutil.copy2(source,target);timing_data.lox(json.loads(target.read_text()),True)
 result['archives'].append(archive(target));write(OUT/'receipt.json',result)
 run('eda',['bash',TOOLS/'part3.sh','eda'])
 target=AREA/'results/eda-runtime.json';timing_data.eda(json.loads(target.read_text()),True)
 result['archives'].append(archive(target));write(OUT/'receipt.json',result)
 run('parity',['bash',TOOLS/'part3.sh','parity'])
 pair=json.loads((AREA/'results/parity-pair.json').read_text())
 def arm(name,label):
  value=pair['benchmarks'][name]['arms'][label];cmd=value['build']['cmd']
  binary=str(ROOT/'.mylang-cache/rp3/parity/pair/bin'/(name+'.'+label))
  assert sha(binary)==value['binary_sha256'];return [binary]
 ladder=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-rp3-s2/.mylang-cache/rp3/s2-ladder/text_ops.r3')
 assert sha(ladder)=='a8f3682e123c348f4b7e4f6922fc9ed5258e34d2be219499b0c43562baf8c849'
 spec={'name':'text_ops reachable rung 3 bound','expected_stdout_sha256':'0967b572d16c244fceff04c57b479c96e1e0fc0580feae10a3dbaa6c6e0a76bf','reference':'rung3','arms':{'rung3':[str(ladder)],'base':arm('text_ops','base-my'),'final':arm('text_ops','my'),'zig-safe':arm('text_ops','zig-safe'),'rust-checked':arm('text_ops','rust-checked')}}
 write(AREA/'X/text-ops-bound-spec.json',spec)
 r=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-rp3-r/.mylang-cache/rp3/R/nbody-ladder')
 hashes=['c5a66f8f0486b676ce2a759ff57be971d06fd893794788c44efbe739607eb054','9c019699d9192cd650d87b045b838c1396c9d3e95ab587bc444aef0cd3e85e88','84afa1247d0494de07b7b930eb01348ddca80b67c038594b2b27402885bb1631']
 for i,h in enumerate(hashes): assert sha(r/str(i))==h
 spec={'name':'nbody fixed-N ladder','expected_stdout_sha256':'179a443bca1492bd09db9648ca9f9d7f3ae224f95c6e59a3bcb3601907c98245','reference':'base','arms':{'base':arm('nbody','base-my'),'final':arm('nbody','my'),'final-class':arm('nbody','my-class'),'zig-safe':arm('nbody','zig-safe'),'rust-checked':arm('nbody','rust-checked'),**{'rung'+str(i):[str(r/str(i)),'5'] for i in range(3)}}}
 write(AREA/'X/nbody-bound-spec.json',spec)
 result['archives'].append(archive(AREA/'results/parity-pair.json'));write(OUT/'receipt.json',result)
 for n in range(1,4):
  run('rows-'+str(n),['bash',TOOLS/'part3.sh','rows',str(n)])
  result['archives'].append(archive(AREA/'results'/('all46-'+str(n)+'.json')));write(OUT/'receipt.json',result)
 run('text-ops-bound',[*py,TOOLS/'confirm_bound.py','--spec',AREA/'X/text-ops-bound-spec.json','--out',AREA/'X/text-ops-bound.json'])
 run('nbody-bound',[*py,TOOLS/'confirm_bound.py','--spec',AREA/'X/nbody-bound-spec.json','--out',AREA/'X/nbody-bound.json'])
 run('r5-cpu10',[*py,TOOLS/'confirm_rows_bound.py','--spec',AREA/'X/r5-four-arms.json','--out',AREA/'X/r5-cpu10.json'])
 run('gap',[*py,TOOLS/'x_gap.py','--input',AREA/'results','--out',AREA/'X'])
 run('review-perf',[*py,TOOLS/'review_perf.py','--gap',AREA/'X/gap.json','--rounds','7','--out',AREA/'X/review-perf.json'],True)
 stable();result['complete']=True;result['analysis_pending']=True;write(OUT/'receipt.json',result)
 print('Measurement sequence complete; regression classification, exits and final report remain mandatory.',flush=True)

if __name__=='__main__': main()

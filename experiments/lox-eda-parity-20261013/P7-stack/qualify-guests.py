#!/usr/bin/env python3
import pathlib,json,os,hashlib,subprocess,shutil
from counter_policy import compare
root=pathlib.Path.cwd();base=root/'experiments/lox-eda-parity-20261013/P7-stack';work=root/'.tmp/lox-eda-parity/P7-stack';out=base/'qualification-005';out.mkdir();assert os.environ['MYLANG_ADMISSION_KIND']=='build';co=pathlib.Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012');un=json.loads((base/'guest-builds-001/receipt.json').read_text());count=json.loads((base/'counted-guests-001/receipt.json').read_text());pins={**un['inputs'],**count['inputs']};rows=[];cases=['eda-rds3+flat','eda-rds3-rf-selector','tree-binary_trees','tree-fib','vm-fib']
def sha(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def stable(value):
 if isinstance(value,dict):return {k:stable(v) for k,v in value.items() if k not in ['realloc_moves','realloc_moved_bytes']}
 if isinstance(value,list):return [stable(v) for v in value]
 return value
def tree(p):return {str(q.relative_to(p)):sha(q) for q in p.rglob('*') if q.is_file()}
for case in cases:
 sp=co/'experiments/lox-eda-parity-20261013/attempts/runtime-001/specs'/(case+'.json');spec=json.loads(sp.read_text());pins[str(sp)]=sha(sp);app='eda' if case.startswith('eda-') else 'lox';directory=work/'qualification-005-outputs'/case;cwd=work/'qualification-005-cwd'/case;cwd.mkdir(parents=True);paths=list(spec['files']);paths.extend(str(p) for d in spec.get('identity_dirs',[]) for p in pathlib.Path(d).rglob('*') if p.is_file());pins.update({p:sha(p) for p in paths});oracle=None;oracle_err=None;oracle_count=None
 arms={'installed-C2':{'path':str(co/'.tmp/lox-eda-parity/P6/native-002'/app/'zero-rc'),'sha256':un['inputs'][str(co/'.tmp/lox-eda-parity/P6/native-002'/app/'zero-rc')]},**un['variants'][app]}
 oldcount=co/'.tmp/lox-eda-parity/P6/native-002'/app/'zero-rc-counted';arms['installed-C2-counted']={'path':str(oldcount),'sha256':sha(oldcount)};arms.update({'counted-'+name:item for name,item in count['variants'][app].items()})
 for arm,item in arms.items():
  assert all(sha(p)==h for p,h in pins.items());assert sha(item['path'])==item['sha256'];pins[item['path']]=item['sha256'];label=case+'-'+arm;cp=out/(label+'.counts.json');argv=[item['path'],*spec['arms']['mylang-zero-rc'][1:]]
  if '--out-dir' in argv:
   if directory.exists():shutil.rmtree(directory)
   argv[argv.index('--out-dir')+1]=str(directory)
  env={**os.environ,'MYL_CORE_LEAKCHECK':'1','MYLANG_COUNTERS':str(cp)};r=subprocess.run(argv,cwd=spec.get('cwd',str(cwd)),env=env,capture_output=True,timeout=120);(out/(label+'.stdout')).write_bytes(r.stdout);(out/(label+'.stderr')).write_bytes(r.stderr);row={'case':case,'arm':arm,'argv':argv,'cwd':spec.get('cwd',str(cwd)),'returncode':r.returncode,'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr).hexdigest()};rows.append(row);(out/'commands.json').write_text(json.dumps(rows,indent=2)+'\n');assert r.returncode==0,(label,r.stderr)
  if oracle is None:oracle=r.stdout;oracle_err=r.stderr
  assert r.stdout==oracle and r.stderr==oracle_err,(label,'output mismatch')
  if 'golden_dir' in spec:assert tree(directory)==tree(pathlib.Path(spec['golden_dir'])),label
  elif 'expected_stdout' in spec:assert r.stdout==pathlib.Path(spec['expected_stdout']).read_bytes(),label
  if 'counted' in arm:
   counters=json.loads(cp.read_text());assert counters['totals']['live_bytes_at_exit']==0
   if oracle_count is None:oracle_count=counters
   compare(oracle_count,counters);row['counter_sha256']=sha(cp)
  print(label,flush=True)
assert all(sha(p)==h for p,h in pins.items());(out/'receipt.json').write_text(json.dumps({'status':'passed_untimed','cases':cases,'runs':len(rows),'counter_equality_exception':['realloc_moves','realloc_moved_bytes'],'inputs':pins,'commands':rows,'outer_lease':{'kind':os.environ['MYLANG_ADMISSION_KIND'],'directory':os.environ['MYLANG_ADMISSION_DIR']}},indent=2)+'\n')

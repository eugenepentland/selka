#!/usr/bin/env python3
"""Replay every immutable per-file/configured/directory command; audit migration differences."""
import argparse,concurrent.futures,hashlib,json,os,subprocess,time
from pathlib import Path

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v): p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,indent=2,sort_keys=True)+'\n')
def main():
 a=argparse.ArgumentParser();a.add_argument('corpus',choices=['lox','eda']);a.add_argument('--compiler',type=Path,required=True);a.add_argument('--output',type=Path,required=True);a.add_argument('--jobs',type=int,default=3);a.add_argument('--frozen-property-seed',type=int);a.add_argument('--preserve-property-seed',type=int);a=a.parse_args()
 area=Path(__file__).resolve().parent;source=area/'sources'/a.corpus;reference=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-frontend-integration/experiments/frontend-current-lang-oracle-20261008')/a.corpus
 compiler=a.compiler.resolve();output=a.output.resolve();assert not output.exists();output.mkdir(parents=True);cache=output/'cache';ident=json.loads((reference/'identity.json').read_text());oldroot=Path(ident['source_worktree']);items=[]
 for category in ['current','configured']:
  for mode in ['debug','release','verify']:
   p=reference/(category+'-'+mode+'.json')
   if not p.exists():continue
   for name,saved in json.loads(p.read_text())['files'].items():items.append((category+'/'+mode+'/'+name,saved))
 for mode,saved in json.loads((reference/'directory.json').read_text()).items():items.append(('directory/'+mode,saved))
 if a.frozen_property_seed is not None:items=[item for item in items if item[0].startswith('directory/') or item[0].endswith('/sexpr_parser_test')]
 env=dict(os.environ,MYL_CORE_LEAKCHECK='1',PYTHONDONTWRITEBYTECODE='1');candidate_sha=sha(compiler)
 compiler_source=area.parents[2]
 production={str(p.relative_to(compiler_source)):sha(p) for name in ['src','std','stdlib'] for p in (compiler_source/name).rglob('*') if p.is_file()}
 production.update({name:sha(compiler_source/name) for name in ['build.zig','build.zig.zon']})
 migrated={str(p.relative_to(source)):sha(p) for p in source.rglob('*') if p.is_file() and '.git' not in p.parts}
 runner_sha=sha(Path(__file__))
 write(output/'input-identities.json',{'compiler_sha256':candidate_sha,'production':production,'migrated':migrated,'runner_sha256':runner_sha,'environment':{k:v for k,v in env.items() if k.startswith(('MYLANG_','MYL_','ZIG_'))}})
 def one(item):
  label,saved=item;receipt_path=reference/saved['receipt'];receipt=json.loads(receipt_path.read_text());cmd=receipt['command'].copy();assert cmd[0]==ident['oracle']['path'];cmd[0]=str(compiler)
  if a.frozen_property_seed is not None:cmd.extend(['--seed',str(a.frozen_property_seed)])
  elif a.preserve_property_seed is not None and (label.startswith('directory/') or label.endswith('/sexpr_parser_test')):cmd.extend(['--seed',str(a.preserve_property_seed)])
  cmd[cmd.index('--cache-dir')+1]=str(cache)
  for i,s in enumerate(cmd):
   if s.startswith(str(oldroot)+'/'):cmd[i]=str(source)+s[len(str(oldroot)):]
  cwd=str(source) if receipt['cwd']==str(oldroot) else receipt['cwd'];started=time.monotonic();timeout=False
  try:d=subprocess.run(cmd,cwd=cwd,env=env,capture_output=True,timeout=600)
  except subprocess.TimeoutExpired as e:timeout=True;d=subprocess.CompletedProcess(cmd,124,e.stdout or b'',e.stderr or b'')
  path=output/'commands'/label;path.parent.mkdir(parents=True,exist_ok=True);path.with_suffix('.stdout').write_bytes(d.stdout);path.with_suffix('.stderr').write_bytes(d.stderr)
  actual=None
  try:actual=json.loads(d.stdout)
  except (ValueError,UnicodeDecodeError):pass
  expected=json.loads(receipt_path.with_suffix('.stdout').read_text())
  expected_tests=[t['name'] for t in expected['tests']];mapped=[('src.'+n if a.corpus=='eda' else n) for n in expected_tests];actual_tests=[t['name'] for t in actual.get('tests',[])] if isinstance(actual,dict) else []
  expected_statuses={('src.'+t['name'] if a.corpus=='eda' else t['name']):t['status'] for t in expected['tests']}
  statuses=[t['status'] for t in actual.get('tests',[])] if isinstance(actual,dict) else []
  changes=[]
  if isinstance(actual,dict):
   for k in sorted(set(expected)|set(actual)):
    if expected.get(k)!=actual.get(k):changes.append({'field':k,'reference':expected.get(k),'candidate':actual.get(k)})
  result={'command':cmd,'reference_command':receipt['command'],'cwd':cwd,'returncode':d.returncode,'reference_returncode':receipt['returncode'],'timeout':timeout,'elapsed_seconds':time.monotonic()-started,'reference_receipt_sha256':sha(receipt_path),'stdout_sha256':sha(path.with_suffix('.stdout')),'stderr_sha256':sha(path.with_suffix('.stderr')),'membership_equal_after_explicit_module_mapping':sorted(mapped)==sorted(actual_tests),'reference_tests':len(expected_tests),'actual_tests':len(actual_tests),'nonpassing':sum(s!='passed' for s in statuses),'complete_report_exact':actual==expected,'report_changes':changes,'stderr_exact':d.stderr==receipt_path.with_suffix('.stderr').read_bytes(),'process_status_equal':d.returncode==receipt['returncode'],'expected_statuses_equal':isinstance(actual,dict) and {t['name']:t['status'] for t in actual.get('tests',[])}==expected_statuses,'functional_membership_pass':isinstance(actual,dict) and sorted(mapped)==sorted(actual_tests) and all(s=='passed' for s in statuses) and d.returncode==receipt['returncode'] and not timeout}
  write(path.with_suffix('.json'),result);print(label, 'functional_membership_pass' if result['functional_membership_pass'] else 'FAILED',flush=True);return label,result
 with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:results=dict(pool.map(one,items))
 assert sha(compiler)==candidate_sha
 assert sha(Path(__file__))==runner_sha
 assert all(sha(compiler_source/p)==v for p,v in production.items())
 assert {str(p.relative_to(source)):sha(p) for p in source.rglob('*') if p.is_file() and '.git' not in p.parts}==migrated
 write(output/'summary.json',{'compiler':str(compiler),'compiler_sha256':candidate_sha,'source_pin':json.loads((area/(a.corpus+'-snapshot.json')).read_text())['pin'],'module_name_mapping':'prefix src. to frozen EDA names' if a.corpus=='eda' else 'identity','commands':len(results),'functional_membership_pass_commands':sum(r['functional_membership_pass'] for r in results.values()),'tests_by_command':{k:r['actual_tests'] for k,r in results.items()},'report_differences_require_review':True,'results':results})
if __name__=='__main__':main()

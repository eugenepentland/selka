#!/usr/bin/env python3
"""Check real backend resolution, conservative foreign argv, and warm reuse."""
from pathlib import Path
import hashlib,json,os,subprocess,sys
lane=Path(__file__).resolve().parents[2];work=lane/'.tmp-lox-native-policy-20261003'
compiler=work/'compiler-final/bin/mylang'
selected=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release/bin/qbe')
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert sha(selected)=='99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
base=work/'producer-check-v2';base.mkdir();source=base/'policy_program.my'
text=(lane/'test/native_variant_policy.zig').read_text().split('const source =\n',1)[1].split('\n;',1)[0]
source.write_text('\n'.join(line.split('\\\\',1)[1] for line in text.splitlines())+'\n')
wrapper=base/'foreign.py'
wrapper.write_text('#!/usr/bin/env python3\nimport json,os,subprocess,sys\nargs=sys.argv[1:]\nwith open(os.environ["POLICY_TRACE"],"a") as f:f.write(json.dumps(args)+"\\n")\nif any(a.startswith("--native-variants=") for a in args):sys.exit(97)\nsys.exit(subprocess.run([os.environ["POLICY_REAL_COMPILER"],*args]).returncode)\n')
wrapper.chmod(0o755)
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'}
env.update(TMPDIR=str(work/'tmp'),ZIG_GLOBAL_CACHE_DIR=str(work/'global-cache'),MYLANG_TIMING_CPUS='2,3,10,11')
from prefixes import snapshot
prefix_before=snapshot()
report={'complete_source_descriptor_sha256':sha(work/'frozen-source-complete.json'),'immutable_prefixes_before':prefix_before,'compiler':str(compiler),'compiler_sha256':sha(compiler),'qbe':str(selected),'qbe_sha256':sha(selected),'source_sha256':sha(source),'runs':[],'verified_after':False}
for name,backend,foreign,fast in [('self-qbe','qbe',False,True),('self-llvm','llvm',False,False),('self-legacy','legacy',False,False),('foreign-qbe','qbe',True,False),('foreign-llvm','llvm',True,False),('foreign-legacy','legacy',True,False)]:
 cache=base/('cache-'+name);binary=base/name;local=env.copy();trace=base/(name+'.argv.jsonl')
 if foreign:local.update(MYLANG_HOST_COMPILER=str(wrapper),POLICY_TRACE=str(trace),POLICY_REAL_COMPILER=str(compiler))
 args=[str(lane/'scripts/build-slot.sh'),'build',str(compiler),'build',str(source),'--project','--rc-runtime','--keep-symbols','--cache-dir',str(cache),'-o',str(binary),'--report']
 if foreign:args+=['--whole-program']
 if backend=='llvm':args+=['--backend','llvm','--llvm-opt','3','--lto']
 else:args+=['--qbe',str(selected) if backend=='qbe' else str(base/'never-read/qbe_llvm.py')]
 for round_ in range(2):
  name_round=name+'-'+str(round_);stdout=base/(name_round+'.stdout');stderr=base/(name_round+'.stderr')
  with stdout.open('xb') as out,stderr.open('xb') as err:result=subprocess.run(args,cwd=lane,env=local,stdout=out,stderr=err)
  row={'name':name,'round':round_,'argv':args,'status':result.returncode,'stdout':str(stdout),'stderr':str(stderr),'binary':str(binary),'foreign':foreign,'expected_policy':'qbe-v2' if fast else 'original'}
  report['runs'].append(row);(base/'qualification.json').write_text(json.dumps(report,indent=2)+'\n')
  assert result.returncode==0,stderr.read_text()
  data=json.loads(stdout.read_text());row['resolved_backend']=data['backend'];row['binary_sha256']=sha(binary)
  assert data['backend']==('qbe' if backend=='qbe' else 'llvm')
  if round_==1:assert data['compiled_functions']==0,data
  emitted=[p for p in cache.rglob('*') if p.is_file() and (p.suffix in ('.ssa','.json') or p.parent.name=='il')]
  marked=[str(p) for p in emitted if b'# RC-NATIVE-VARIANT-1' in p.read_bytes()]
  row['marked_artifacts']=marked
  assert bool(marked)==fast,(name,marked)
 if foreign:
  argv=[json.loads(line) for line in trace.read_text().splitlines()];assert argv and all(not any(a.startswith('--native-variants=') for a in row) for row in argv)
  report['foreign_argv_'+name]=argv
assert sha(compiler)==report['compiler_sha256'] and sha(selected)==report['qbe_sha256'] and sha(source)==report['source_sha256']
report['immutable_prefixes_after']=snapshot();assert prefix_before==report['immutable_prefixes_after']
report['verified_after']=True;(base/'qualification.json').write_text(json.dumps(report,indent=2)+'\n')
print('12 cold/warm real-backend and conservative foreign-producer builds passed; no perf')

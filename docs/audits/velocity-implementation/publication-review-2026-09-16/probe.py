import sys,os,json,subprocess,hashlib,time,shutil
from pathlib import Path
work=Path(__file__).parent
repo=Path('/home/epentland/ai/canopy/mylang')
sys.path.insert(0,str(repo/'scripts'))
import profile_large_project as h
compiler=Path('/tmp/vel-rf-pub/bin/mylang')
entry,paths=h.generate_managed(work/'sources',4,2)
log=work/'qbe-calls.jsonl'
wrapper=work/'qbe'
wrapper.write_text('#!/usr/bin/python3\nimport os,sys,json\nfrom pathlib import Path\np=Path(sys.argv[-1])\nif p.suffix==".ssa":\n with open('+repr(str(log))+',"a") as out: out.write(json.dumps({"argv":sys.argv[1:],"il":p.read_text()})+"\\n")\nos.execv('+repr(str(repo/'zig-out/bin/qbe'))+','+'['+repr(str(repo/'zig-out/bin/qbe'))+']+sys.argv[1:])\n')
wrapper.chmod(0o755)
env=dict(os.environ,MYLANG_SEMANTIC_BUDGET='16777216')
base=[str(compiler),'test',str(entry),'--json','--report','--cache-dir='+str(work/'cache'),'--zig',shutil.which('zig'),'--qbe',str(wrapper),'--mode','ReleaseFast']
records=[]
for state,extra in [('cold',[]),('forced',['--force']),('template_edit',[]),('forced_after_edit',['--force']),('one_provider_body_edit',[])]:
 if state=='template_edit':
  p=paths['pricing']; p.write_text(p.read_text().replace('return P.price(policy, subtotal) + P.tag(policy)','return P.price(policy, subtotal) + P.tag(policy) + 1000'))
 if state=='one_provider_body_edit':
  p=work/'sources/provider000.my'; p.write_text(p.read_text().replace('return subtotal - unwrap(policy)','return subtotal - unwrap(policy) + 23'))
 prior=log.read_text().splitlines() if log.exists() else []
 begin=time.monotonic(); r=subprocess.run(base+extra,env=env,text=True,capture_output=True,timeout=60)
 now=log.read_text().splitlines() if log.exists() else []
 calls=[json.loads(line) for line in now[len(prior):]]
 report={'state':state,'exit':r.returncode,'diagnostic_wall_ms':(time.monotonic()-begin)*1000,'qbe_compiles':len(calls),'calls':calls,'stdout':r.stdout,'stderr':r.stderr}
 records.append(report)
 print(json.dumps({k:report[k] for k in ('state','exit','qbe_compiles')}) ,flush=True)
 if r.returncode: print(r.stderr[-2000:],flush=True); break
result={'version':'publication-review-v1','compiler':str(compiler),'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'providers':4,'functions_per_provider':2,'note':'QBE wrapper captures actual native-test child IL; diagnostic counts, not benchmark latency. No repository gates invoked.','samples':records}
(work/'probe.json').write_text(json.dumps(result,indent=2)+'\n')
print(str(work/'probe.json'),flush=True)

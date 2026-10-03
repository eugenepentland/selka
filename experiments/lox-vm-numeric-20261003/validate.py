#!/usr/bin/env python3
"""Exact bounded RC/GC numeric guest comparison; no timing or performance runs."""
from pathlib import Path
from collections import Counter
from datetime import datetime,timezone
import ast,gzip,hashlib,json,os,re,subprocess
lane=Path(__file__).resolve().parents[2];work=lane/'.tmp-lox-vm-numeric-20261003';dest=work/'native';dest.mkdir(exist_ok=False);(dest/'tmp').mkdir()
root=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003');borrow=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-borrow-assert-20261003/.tmp-lox-borrow-assert-20261003')
compiler=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release/bin/mylang');source=work/'numeric-qualified';control=root/'.tmp-lox-round3/ast';bench=root/'.tmp-lox-parity/reference/benchmarks/lox/bench';helper=root/'experiments/lox-parity-tree-20261003/validate.py'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();files=lambda p:{str(f.relative_to(p)):sha(f) for f in sorted(p.rglob('*')) if f.is_file()}
write=lambda name,v:(dest/name).write_text(json.dumps(v,indent=2)+'\n')
build=json.loads((work/'builds.json').read_text());assert build['verified_after'];assert files(source)==build['source37'];assert files(control)==json.loads((work/'source-final.json').read_text())['baseline']
bins={};bins.update({'control-'+b:str(borrow/('fixed-'+b+'-ast')) for b in ['llvm','qbe']})
for row in build['runs']:
 assert row['status']==0 and sha(row['binary'])==row['binary_sha256']
 backend=row['backend'];runtime=row['runtime']
 if runtime=='rc':bins['numeric-rc-'+backend]=row['binary']
 else:bins['numeric-ordinary-'+backend]=row['binary'];bins['numeric-gc-'+backend]=row['binary']
write('binaries.json',{'binaries':bins})
text=(source/'driver_tests.my').read_text();block=text[text.index('public def test_run_numeric_carrier_ieee'):];ieee_source=ast.literal_eval(re.search(r'    source = (b".*")\n',block)[1]).decode();ieee_stdout=ast.literal_eval(re.search(r'    expected = (b".*")\n',block)[1]).decode()
cases=[{'name':'numeric-carrier-ieee','source':ieee_source,'stdout':ieee_stdout},{'name':'numeric-carrier-closure-roots','source':'class Box { init(v) { this.v = v; } } fun outer() { var box = Box(6); fun f(x) { var y = box.v; return (y - x) * (y / x); } return f; } var f = outer(); print f(2); print f(3); print 0 / -1; print -0 - 0;','stdout':'12\n6\n-0\n-0\n'},{'name':'numeric-carrier-underflow','source':'var t = 0.00000000000000000001; t = t * t; t = t * t; t = t * t; t = t * t; t = t * t; print t; print -t / 2; print 1 / t; print -1 / t; var n = t / t; print n < n; print n > n; print n == n;','stdout':'0\n-0\ninf\n-inf\nfalse\nfalse\nfalse\n'}]
write('cases.json',cases)
paths={compiler,compiler.with_name('qbe'),helper,Path(__file__).resolve(),work/'builds.json',work/'source-final.json',dest/'binaries.json',dest/'cases.json',root/'.tmp-lox-parity/inputs/pinned-SPEC.md',borrow/'static-builds.json'}
paths.update(p for p in bench.rglob('*') if p.is_file());paths.update(root/'docs/audits/evidence'/n for n in ['d9-lox-env-reads-runs.json.gz','d9-lox-class-method-runs.json.gz'])
for binary in set(bins.values()):
 p=Path(binary);manifest=Path(binary+'.qbe-manifest.json');paths.update([p,manifest,Path(binary+'.qbe-receipt'),Path(json.loads(manifest.read_text())['runtime_object'])])
snapshot=lambda:{'candidate37':files(source),'control37':files(control),'artifacts_sha256':{str(p):sha(p) for p in sorted(paths)}}
assert not set(os.sched_getaffinity(0))&{2,3,10,11};before=snapshot();write('preflight.json',before)
assert before['artifacts_sha256'][str(compiler)]=='d14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040';assert sha(compiler.with_name('qbe'))=='99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
assert sha(bins['control-llvm'])=='180575c3fc2e46a16ed8dd290e289963a87603b5a7c0cf8bb0e03ba7cf794361';assert sha(bins['control-qbe'])=='246f21781fd58c7141dbe0992101c842e62d732d9ce47e209d55821d02b11b25'
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env['TMPDIR']=str(dest/'tmp')
argv=['python3',str(helper),'--work',str(dest),'--bench',str(bench),'--manifest',str(dest/'binaries.json'),'--out',str(dest/'observations.json'),'--jobs','2','--cases',str(dest/'cases.json'),'--native-cases','closures,instantiation,properties']
write('command.json',{'argv':argv,'cwd':str(lane),'environment':{'TMPDIR':env['TMPDIR']},'affinity':sorted(os.sched_getaffinity(0)),'launcher':[str(lane/'scripts/build-slot.sh'),'build','python3',str(Path(__file__).resolve())]})
with (dest/'observations.log').open('xb') as out:run=subprocess.run(argv,cwd=lane,env=env,stdout=out,stderr=subprocess.STDOUT)
assert run.returncode==0,(run.returncode,dest/'observations.log')
r=json.loads((dest/'observations.json').read_text());assert len(r['samples'])==856 and len(r['unrun'])==80 and r['verified_after'];assert all(row['actual']==row['expected'] for row in r['samples'])
identity=lambda row:(row['name'],row['tier'],row['engine'],row['arm'],row['lox_gc_stress']);actual={identity(row) for row in r['samples']};unrun={identity(row) for row in r['unrun']};keys={(row['name'],row['tier'],row['engine']) for row in r['samples']};expected={(n,t,e,arm,stress) for n,t,e in keys for arm in bins if not arm.startswith('control-') for stress in [False,True]}
assert len(keys)==78 and len(actual)==856 and len(unrun)==80;assert actual.isdisjoint(unrun) and actual|unrun==expected
counts=Counter('native_gc_stress' if row['native_gc_stress'] else 'rc' if '-rc-' in row['arm'] else 'ordinary_gc' for row in r['samples']);assert counts=={'rc':312,'ordinary_gc':312,'native_gc_stress':232}
def observe(binary,path,engine,lox,native):
 cmd=[binary,'--engine='+engine,'--stats']+(['--gc-stress'] if lox else [])+[str(path)];launch=dict(env)
 if native:launch['MYLANG_OPTIONS']='--gc-stress'
 done=subprocess.run(cmd,env=launch,capture_output=True,timeout=120);return {'status':done.returncode,'stdout':done.stdout.decode(),'stderr':done.stderr.decode()},cmd
# Ten errors exercise each operation with either numeric tag rejected after both
# side effects. Compare exact per-engine traces and collector statistics.
extra=[]
for op in ['>','<','-','*','/']:
 for reversed in [False,True]:
  left='2' if reversed else '"bad"';right='"bad"' if reversed else '2';program=f'fun left() {{ print "L"; return {left}; }}\nfun right() {{ print "R"; return {right}; }}\nfun leaf() {{ return left() {op} right(); }}\nfun outer() {{ return leaf(); }}\nouter();'
  path=dest/'validation-inputs'/('numeric-error-'+str(['>','<','-','*','/'].index(op))+'-'+str(int(reversed))+'.lox');path.write_text(program)
  for backend in ['llvm','qbe']:
   for engine in ['vm','tree']:
    for lox in [False,True]:
     control_result,ca=observe(bins['control-'+backend],path,engine,lox,False);prefix='Operands must be numbers.\n'+('[line 3] in leaf()\n[line 4] in outer()\n[line 5] in script\n' if engine=='vm' else '[line 3]\n')
     assert control_result['status']==70 and control_result['stdout']=='L\nR\n' and control_result['stderr'].startswith(prefix)
     for mode in ['rc','ordinary','gc']:
      arm='numeric-'+mode+'-'+backend;actual_result,cmd=observe(bins[arm],path,engine,lox,mode=='gc');assert actual_result==control_result
      extra.append({'name':path.stem,'source_sha256':sha(path),'backend':backend,'engine':engine,'arm':arm,'lox_gc_stress':lox,'native_gc_stress':mode=='gc','argv':cmd,'control_argv':ca,'actual':actual_result,'expected':control_result})
assert len(extra)==240;write('numeric-errors.json',{'samples':extra})
refusals=[];path=dest/'validation-inputs/closures.vm.smoke.lox'
for backend in ['llvm','qbe']:
 for engine in ['vm','tree']:
  for lox in [False,True]:
   control_result,ca=observe(bins['control-'+backend],path,engine,lox,True);actual_result,cmd=observe(bins['numeric-rc-'+backend],path,engine,lox,True);assert actual_result==control_result and actual_result['status']==2 and actual_result['stdout']=='' and '--gc-runtime' in actual_result['stderr']
   refusals.append({'backend':backend,'engine':engine,'lox_gc_stress':lox,'argv':cmd,'control_argv':ca,'environment':{'MYLANG_OPTIONS':'--gc-stress'},'actual':actual_result,'expected':control_result})
assert len(refusals)==8;write('rc-native-stress-refusals.json',{'pairs':refusals,'meaning':'checked refusal pairs, not program passes'})
after=snapshot();assert after==before;write('completed.json',{'before':before,'after':after,'verified_after':True,'mode_counts':dict(counts),'bounded_pairs':856,'numeric_error_pairs':240,'total_program_pairs':1096,'rc_native_stress_refusal_pairs':8,'native_smoke_unrun':r['unrun'],'receipt_sha256':{name:sha(dest/name) for name in ['binaries.json','command.json','cases.json','observations.json','observations.log','numeric-errors.json','rc-native-stress-refusals.json']},'finished_utc':datetime.now(timezone.utc).isoformat()});print('1096 exact native program pairs +8 checked refusals;80 native smoke cells unrun',flush=True)

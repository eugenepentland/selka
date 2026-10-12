#!/usr/bin/env python3
"""Bounded real guest-runner groups; every unsupported result fails qualification."""
import argparse, hashlib, json, os, pathlib, subprocess
ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / '.tmp/memory-closeout/A10/equality'
FIXTURES = pathlib.Path('/home/epentland/ai/canopy/mylang-memory-20261012-support7')
MODES = {'release':['--release'], 'debug':['--unoptimized'], 'verified':['--release','--verify-facts'], 'optimized_debug':['--optimize-debug'], 'no_facts':['--release','--no-facts']}
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser();p.add_argument('--compiler',type=pathlib.Path,required=True);p.add_argument('--group',choices=[*MODES,'cache','ordinary'],required=True);args=p.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    env=dict(os.environ,MYL_CORE_LEAKCHECK='1',MYLANG_COMPONENT_DIR=str(ROOT/'zig-out/libexec/mylang/components'))
    compiler=args.compiler.resolve(); before=sha(compiler); results=[]
    if args.group=='cache': env.pop('MYL_CORE_LEAKCHECK',None)
    def run(label, source, flags, expected, cached=False):
        path=FIXTURES/source
        argv=[str(compiler),'test',str(path),'--json','--jobs','1','--seed','7','--property-runs','12','--cache-dir',str(OUT/'cache-v2'/args.group),*flags]
        got=subprocess.run(argv,cwd=ROOT,env=env,text=True,capture_output=True)
        try: data=json.loads(got.stdout)
        except ValueError: data={}
        passed=(got.returncode==0 and data.get('unsupported')==0 and data.get('failed')==0 and data.get('skipped')==0 and data.get('cached' if cached else 'passed')==expected)
        results.append(dict(label=label,source=str(path),source_sha256=sha(path),argv=argv,returncode=got.returncode,stdout=got.stdout,stderr=got.stderr,report=data,passed=passed))
    if args.group in MODES:
        flags=['--experimental-zero-rc','--force',*MODES[args.group]]
        run('all-seven-equality','tests/lang/value_equality.my',flags,7)
        for name in ['test_deep_hashing_and_nominal_rendering','test_shared_nan_is_not_reflexive']:
            run(name,'test/core/m_recursive_values.my',[*flags,'--filter',name],1)
    elif args.group=='ordinary':
        run('ordinary-control','tests/lang/value_equality.my',['--release','--force'],7)
    else:
        for mode in ['reference','shadow','component']:
            env['MYLANG_CACHE_PLAN_MODE']=mode
            for warm in [False,True]:
                run(mode+('-warm' if warm else '-cold'),'tests/lang/value_equality.my',['--experimental-zero-rc','--release'],7,warm)
    assert sha(compiler)==before,'compiler changed during qualification'
    report=dict(schema='a10-equality-guest-qualification-v1',compiler=str(compiler),compiler_sha256=before,fixture_revision='bed11cf3bf3102ffec44487e431a1573fdf02ad5',harness_sha256=sha(pathlib.Path(__file__)),group=args.group,leakcheck=args.group!='cache',results=results,passed=all(x['passed'] for x in results))
    (OUT/(args.group+'.json')).write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(dict(group=args.group,passed=report['passed'],commands=len(results),rows=sum(x['report'].get('passed',0)+x['report'].get('cached',0) for x in results))))
    raise SystemExit(0 if report['passed'] else 1)
if __name__=='__main__':main()

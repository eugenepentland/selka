#!/usr/bin/env python3
"""Bounded exact VM output/diagnostic/stats comparisons; no performance runs."""
from pathlib import Path
import gzip, hashlib, json, os, re, subprocess

lane = Path(__file__).resolve().parents[2]
work = lane/'.tmp-lox-vm-stack-read-v2-20261003'
root = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003')
build = json.loads((work/'builds.json').read_text())
assert build['verified_after']
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
bins = {'control-'+backend: root/'.tmp-lox-round3/bin'/('ast-'+backend) for backend in ('llvm', 'qbe')}
for row in build['runs']:
    backend, runtime = Path(row['binary']).name.split('-')[-2:]
    bins[runtime+'-'+backend] = Path(row['binary'])
hashes = {k: sha(p) for k,p in bins.items()}
sources = lambda: {str(f.relative_to(Path(build['source']))): sha(f) for f in sorted(Path(build['source']).rglob('*')) if f.is_file()}
assert sources() == build['source_sha256']
inputs = work/'validation-inputs'
inputs.mkdir(exist_ok=True)
receipt = {'build_receipt_sha256': sha(work/'builds.json'), 'source_sha256': sources(), 'binaries': {k:str(p) for k,p in bins.items()}, 'binary_sha256': hashes, 'samples': [], 'verified_after': False,
           'v1_commit': 'f4d3fbcced87816210732a200aa765366a0ff8cf',
           'scope': 'VM only; all23 existing exact errors, four bounded corpus smokes, two new equality programs; RC, ordinary GC and native GC stress, each with Lox collector normal/stress. No whole corpus/performance claim.'}
dest = work/'native-validation.json'
assert not dest.exists()
bench = root/'.tmp-lox-parity/reference/benchmarks/lox/bench'
sizes = json.loads((bench/'sizes.json').read_text())
cases = []
for name in ('fib', 'strings', 'string_equality', 'closures'):
    _,body = (bench/'scripts'/(name+'.lox')).read_text().split('\n',1)
    cases.append({'name':name,'tier':'smoke','source':f"var N = {sizes[name]['smoke']};\n{body}", 'stdout': (bench/'expected'/(name+'.smoke.out')).read_text(), 'status': 0})
for name in ('test_run_readonly_stack_equality_tags_and_order', 'test_run_readonly_stack_equality_preserves_snapshots'):
    text = (Path(build['source'])/'driver_tests.my').read_text()
    body = text.split('public def '+name+'(',1)[1].split('\n\n',1)[0]
    source_text = re.search(r'    source = (b".*")\n',body)[1]
    expected_text = re.search(r'    expected = (b".*")\n',body)[1]
    import ast
    source = ast.literal_eval(source_text).decode()
    if name.endswith('snapshots'):
        # The direct public fixture owns the host snapshots; the standalone
        # Lox run exercises the same compare/allocate loop after its setup.
        setup = ast.literal_eval(re.search(r'    setup = (b".*")\n',body)[1]).decode()
        source = setup + source
    cases.append({'name':name,'tier':'regression','source':source,'stdout':ast.literal_eval(expected_text).decode(),'status':0})
with gzip.open(root/'docs/audits/evidence/d9-lox-class-method-runs.json.gz') as f:
    seen=set()
    for row in json.load(f)['traces']:
        if row['name'] in seen: continue
        seen.add(row['name'])
        cases.append({'name':row['name'],'tier':'error','source':row['source'],'stdout':row['expected']['stdout'],'status':row['expected']['status'],'stderr_prefix':row['expected']['stderr']})
assert len(seen)==23 and len(cases)==29
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}

def observe(binary, source, lox_stress, native_stress):
    argv=[str(binary),'--engine=vm','--stats']
    if lox_stress: argv.append('--gc-stress')
    argv.append(str(source))
    launch=dict(env)
    if native_stress: launch['MYLANG_OPTIONS']='--gc-stress'
    run=subprocess.run(argv,env=launch,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=120)
    return {'status':run.returncode,'stdout':run.stdout.decode(),'stderr':run.stderr.decode()},argv

for case in cases:
    source=inputs/(case['tier']+'-'+case['name']+'.lox')
    source.write_text(case['source'])
    for backend in ('llvm','qbe'):
        for lox_stress in (False,True):
            expected,control_argv=observe(bins['control-'+backend],source,lox_stress,False)
            assert expected['status']==case['status'] and expected['stdout']==case['stdout'], (case,expected)
            if 'stderr_prefix' in case: assert expected['stderr'].startswith(case['stderr_prefix'])
            for runtime,native in (('rc',False),('gc',False),('gc',True)):
                key=runtime+'-'+backend
                actual,argv=observe(bins[key],source,lox_stress,native)
                row={'name':case['name'],'tier':case['tier'],'backend':backend,'runtime':runtime,'lox_gc_stress':lox_stress,'native_gc_stress':native,
                     'source':str(source),'source_sha256':sha(source),'control_argv':control_argv,'argv':argv,'expected':expected,'actual':actual,'passed':actual==expected}
                receipt['samples'].append(row)
                dest.write_text(json.dumps(receipt,indent=2)+'\n')
                assert row['passed'], row
    print('PASS',case['tier'],case['name'],flush=True)
assert len(receipt['samples'])==348
assert {k:sha(p) for k,p in bins.items()}==hashes and sources()==receipt['source_sha256']
receipt['verified_after']=True
dest.write_text(json.dumps(receipt,indent=2)+'\n')

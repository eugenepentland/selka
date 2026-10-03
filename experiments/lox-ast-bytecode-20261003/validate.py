#!/usr/bin/env python3
"""Qualify actual combined AST+bytecode ELFs against frozen selected AST controls."""
from collections import Counter
from datetime import datetime, timezone
import hashlib, json, os, subprocess
from pathlib import Path

OWN = Path(__file__).resolve().parents[2]
WORK = OWN/'.tmp-lox-ast-bytecode-20261003/native'
OLD = OWN/'.tmp-lox-ast-bytecode-20261003'
ROOT = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003')
STACK = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-vm-20261003')
SOURCE = OLD/'candidate'
BASE = ROOT/'.tmp-lox-round3/ast'
COMPILER = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release/bin/mylang')
HELPER = ROOT/'experiments/lox-parity-tree-20261003/validate.py'
CASES = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-vm-bytecode-20261003/experiments/lox-vm-bytecode-20261003/regressions.json')
FOCUSED = STACK/'.tmp-lox-ast-carrier-20261003/focused-regressions-final.json'
BENCH = ROOT/'.tmp-lox-parity/reference/benchmarks/lox/bench'
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
files = lambda root: {str(p.relative_to(root)): sha(p) for p in sorted(root.rglob('*')) if p.is_file()}

def write(name, value):
    (WORK/name).write_text(json.dumps(value, indent=2)+'\n')

bins = {'control-'+b: str(ROOT/('.tmp-lox-round3/bin/ast-'+b)) for b in ['llvm', 'qbe']}
for backend in ['llvm', 'qbe']:
    bins['combined-rc-'+backend] = str(OLD/('combined-rc-'+backend))
    for mode in ['ordinary', 'gc']:
        bins['combined-'+mode+'-'+backend] = str(OLD/('combined-gc-'+backend))
assert not (WORK/'binaries.json').exists()
write('binaries.json', {'binaries': bins})


def snapshot():
    paths = {COMPILER, COMPILER.with_name('qbe'), HELPER, CASES, Path(__file__).resolve(),
             WORK/'binaries.json', OLD/'builds.json', FOCUSED, OLD/'public-qualification.json',
             OWN/'experiments/lox-ast-bytecode-20261003/source.json', OWN/'experiments/lox-ast-bytecode-20261003/replay.json',
             OWN/'experiments/lox-ast-bytecode-20261003/build.py', OWN/'experiments/lox-ast-bytecode-20261003/public.py',
             OWN/'experiments/lox-ast-bytecode-20261003/ast-bytecode.patch',
             ROOT/'.tmp-lox-round3/ast-build.json', ROOT/'.tmp-lox-round3/combined.json', ROOT/'.tmp-lox-parity/inputs/pinned-SPEC.md'}
    for name in ['d9-lox-env-reads-runs.json.gz', 'd9-lox-class-method-runs.json.gz']:
        paths.add(ROOT/'docs/audits/evidence'/name)
    paths.update(p for p in BENCH.rglob('*') if p.is_file())
    for binary in set(bins.values()):
        binary = Path(binary)
        manifest = Path(str(binary)+'.qbe-manifest.json')
        paths.update([binary, manifest, Path(str(binary)+'.qbe-receipt')])
        paths.add(Path(json.loads(manifest.read_text())['runtime_object']))
    return {'candidate37': files(SOURCE), 'control37': files(BASE),
            'artifacts_sha256': {str(p): sha(p) for p in sorted(paths)}}

assert not (set(os.sched_getaffinity(0)) & {2, 3, 10, 11})
assert not (WORK/'preflight.json').exists()
before = snapshot()
assert len(before['candidate37']) == len(before['control37']) == 37
prior = json.loads((OLD/'builds.json').read_text())
assert before['candidate37'] == prior['source37'] and prior['verified_after']
gc = json.loads((OLD/'builds.json').read_text())
assert before['candidate37'] == gc['source37'] and gc['verified_after']
assert sha(COMPILER) == prior['compiler_sha256'] == gc['compiler_sha256']
assert sha(COMPILER) == 'd14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040'
assert sha(COMPILER.with_name('qbe')) == prior['qbe_sha256'] == gc['qbe_sha256']
assert sha(COMPILER.with_name('qbe')) == '99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
assert sha(bins['control-llvm']) == '180575c3fc2e46a16ed8dd290e289963a87603b5a7c0cf8bb0e03ba7cf794361'
assert sha(bins['control-qbe']) == '246f21781fd58c7141dbe0992101c842e62d732d9ce47e209d55821d02b11b25'
for row in prior['runs']:
    assert row['status'] == 0
    if 'binary' in row: assert sha(row['binary']) == row['binary_sha256']
    if 'runtime_object' in row: assert sha(row['runtime_object']) == row['runtime_object_sha256']
before.update(started_utc=datetime.now(timezone.utc).isoformat(), runner_affinity=sorted(os.sched_getaffinity(0)))
write('preflight.json', before)
env = {k: v for k, v in os.environ.items() if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
env['TMPDIR'] = str(WORK/'tmp')
argv = ['python3', str(HELPER), '--work', str(WORK), '--bench', str(BENCH),
        '--manifest', str(WORK/'binaries.json'), '--out', str(WORK/'observations.json'),
        '--jobs', '2', '--cases', str(CASES), '--native-cases', 'closures,instantiation,properties']
write('command.json', {'argv': argv, 'cwd': str(OWN), 'environment': {'TMPDIR': env['TMPDIR']},
                       'affinity': sorted(os.sched_getaffinity(0)),
                       'launcher': [str(OWN/'scripts/build-slot.sh'), 'build', 'python3', str(Path(__file__).resolve())]})
with (WORK/'observations.log').open('w') as out:
    run = subprocess.run(argv, cwd=OWN, env=env, stdout=out, stderr=subprocess.STDOUT)
assert run.returncode == 0, (run.returncode, WORK/'observations.log')
r = json.loads((WORK/'observations.json').read_text())
assert len(r['samples']) == 1192 and len(r['unrun']) == 80 and r['verified_after']
identity = lambda row: (row['name'], row['tier'], row['engine'], row['arm'], row['lox_gc_stress'])
actual = {identity(row) for row in r['samples']}
unrun = {identity(row) for row in r['unrun']}
keys = {(row['name'], row['tier'], row['engine']) for row in r['samples']}
expected = {(n, t, e, arm, stress) for n, t, e in keys for arm in bins if not arm.startswith('control-') for stress in [False, True]}
assert len(keys) == 106 and len(actual) == 1192 and len(unrun) == 80
assert actual.isdisjoint(unrun) and actual|unrun == expected
assert all(row['actual'] == row['expected'] for row in r['samples'])
counts = Counter('native_gc_stress' if row['native_gc_stress'] else 'rc' if '-rc-' in row['arm'] else 'ordinary_gc' for row in r['samples'])
assert counts == {'rc': 424, 'ordinary_gc': 424, 'native_gc_stress': 344}


def observe(binary, script, engine, lox, native):
    argv = [binary, '--engine='+engine, '--stats']
    if lox: argv.append('--gc-stress')
    argv.append(str(script))
    launch = dict(env)
    if native: launch['MYLANG_OPTIONS'] = '--gc-stress'
    run = subprocess.run(argv, env=launch, capture_output=True, timeout=120)
    return {'status': run.returncode, 'stdout': run.stdout.decode(), 'stderr': run.stderr.decode()}, argv

refusals = []
script = WORK/'validation-inputs/closures.vm.smoke.lox'
for backend in ['llvm', 'qbe']:
    for engine in ['tree', 'vm']:
        for lox in [False, True]:
            control, ca = observe(bins['control-'+backend], script, engine, lox, True)
            candidate, cmd = observe(bins['combined-rc-'+backend], script, engine, lox, True)
            assert candidate == control and candidate['status'] == 2 and candidate['stdout'] == '' and '--gc-runtime' in candidate['stderr']
            refusals.append({'backend': backend, 'engine': engine, 'lox_gc_stress': lox,
                             'environment': {'MYLANG_OPTIONS': '--gc-stress'}, 'argv': cmd,
                             'control_argv': ca, 'expected': control, 'actual': candidate})
assert len(refusals) == 8
write('rc-native-stress-refusals.json', {'pairs': refusals, 'meaning': 'Checked refusals, not program passes'})
# Qualify the new operand boundary on the actual unaccounted VM ELFs too.
script = WORK/'validation-inputs/constant-operand-255.vm.boundary.lox'
script.write_text(''.join(f'print {i};' for i in range(256)))
expected_stdout = ''.join(f'{i}\n' for i in range(256))
boundary = []
for backend in ['llvm', 'qbe']:
    for lox in [False, True]:
        control, ca = observe(bins['control-'+backend], script, 'vm', lox, False)
        assert control['status'] == 0 and control['stdout'] == expected_stdout
        for mode in ['rc', 'ordinary', 'gc']:
            native = mode == 'gc'
            candidate, cmd = observe(bins['combined-'+mode+'-'+backend], script, 'vm', lox, native)
            assert candidate == control
            boundary.append({'backend': backend, 'lox_gc_stress': lox, 'native_gc_stress': native,
                             'arm': 'combined-'+mode+'-'+backend, 'source_sha256': sha(script),
                             'argv': cmd, 'control_argv': ca, 'expected': control, 'actual': candidate})
assert len(boundary) == 12
write('constant-255-boundary.json', {'samples': boundary})
# Over-limit argument encodings and recovery are observable Lox compile errors.
arguments = ','.join(['nil'] * 256)
nested = 'clock(),' + ','.join(['nil'] * 255)
params = ','.join('p' + str(i) for i in range(255))
valid_arguments = ','.join(['nil'] * 255)
limit_sources = [
    ('argument256-direct', 'fun f(){} f(' + arguments + ');', 65, ''),
    ('argument256-invoke', 'class C{m(){}} C().m(' + arguments + ');', 65, ''),
    ('argument256-super', 'class A{m(){}} class B<A{m(){super.m(' + arguments + ');}} B().m();', 65, ''),
    ('argument256-direct-tail', 'fun f(){} f(' + arguments + '); print ;', 65, ''),
    ('argument256-nested-tail', 'fun f(){} f(' + nested + '); print ;', 65, ''),
    ('argument256-invoke-comma', 'class C{m(){}} C().m(' + arguments + ',); print ;', 65, ''),
    ('argument256-super-tail', 'class A{m(){}} class B<A{m(){super.m(' + arguments + '); print ;}} B().m();', 65, ''),
    ('argument255-last-slot', 'fun f(' + params + '){return p254;} print f(' + valid_arguments + ');', 0, 'nil\n')
]
limit_pairs = []
for name, source, status, stdout in limit_sources:
    script = WORK/'validation-inputs'/(name + '.lox')
    script.write_text(source)
    for backend in ['llvm', 'qbe']:
        for engine in ['tree', 'vm']:
            for lox in [False, True]:
                control, ca = observe(bins['control-'+backend], script, engine, lox, False)
                assert control['status'] == status and control['stdout'] == stdout
                if status == 65: assert '255 arguments' in control['stderr']
                for mode in ['rc', 'ordinary', 'gc']:
                    candidate, cmd = observe(bins['combined-'+mode+'-'+backend], script, engine, lox, mode == 'gc')
                    assert candidate == control, (name, backend, engine, lox, mode, candidate, control)
                    limit_pairs.append({'name': name, 'backend': backend, 'engine': engine, 'lox_gc_stress': lox,
                        'native_gc_stress': mode == 'gc', 'arm': 'combined-'+mode+'-'+backend,
                        'source_sha256': sha(script), 'argv': cmd, 'control_argv': ca,
                        'expected': control, 'actual': candidate})
assert len(limit_pairs) == 192
write('argument-limits.json', {'pairs': limit_pairs, 'cases': 8, 'meaning': 'Exact Lox error recovery plus maximum legal arguments/local slot'})

focused = []
for case in json.loads(FOCUSED.read_text()):
    script = WORK/('validation-inputs/'+case['name']+'.focused.lox')
    script.write_text(case['source'])
    for engine in ['tree','vm']:
        for backend in ['llvm','qbe']:
            for lox in [False,True]:
                control,ca = observe(bins['control-'+backend],script,engine,lox,False)
                assert control['status']==case['status'] and control['stdout']==case['stdout']
                if 'stderr_prefix_by_engine' in case:
                    assert control['stderr'].startswith(case['stderr_prefix_by_engine'][engine])
                for mode in ['rc','ordinary','gc']:
                    native=mode=='gc'
                    arm='combined-'+mode+'-'+backend
                    candidate,cmd=observe(bins[arm],script,engine,lox,native)
                    row={'name':case['name'],'engine':engine,'backend':backend,'arm':arm,
                         'lox_gc_stress':lox,'native_gc_stress':native,'source_sha256':sha(script),
                         'argv':cmd,'control_argv':ca,'expected':control,'actual':candidate}
                    assert candidate==control
                    focused.append(row)
                    write('ast-focused-observations.json',{'samples':focused})
    print('PASS combined AST focused program',case['name'],flush=True)
assert len(focused)==96

after = snapshot()
assert after['candidate37'] == before['candidate37']
assert after['control37'] == before['control37']
assert after['artifacts_sha256'] == before['artifacts_sha256']
write('completed.json', {'before': before, 'after': after, 'verified_after': True,
      'finished_utc': datetime.now(timezone.utc).isoformat(), 'helper_status': run.returncode,
      'mode_counts': dict(counts), 'bounded_observations': 1192, 'boundary_observations': 12,
      'rc_native_stress_refusal_pairs': 8, 'argument_limit_pairs': 192, 'ast_focused_pairs':96, 'native_smoke_unrun': r['unrun'],
      'receipt_sha256': {name: sha(WORK/name) for name in ['binaries.json', 'command.json',
         'observations.json', 'observations.log', 'rc-native-stress-refusals.json', 'constant-255-boundary.json', 'argument-limits.json', 'ast-focused-observations.json']}})
print('1192 bounded +12 boundary +192 argument +96 AST pairs and 8 refusals pass; all37/source/artifact hashes unchanged', flush=True)

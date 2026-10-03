#!/usr/bin/env python3
"""Qualify exact unaccounted constant-read ELFs against frozen combined84 controls."""
from collections import Counter
from datetime import datetime, timezone
import hashlib, json, os, subprocess
from pathlib import Path

OWN = Path(__file__).resolve().parents[2]
WORK = OWN/'.tmp-lox-composed-20261003'
OLD = OWN/'.tmp-lox-vm-dispatch-20261003'
ROOT = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003')
STACK = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-vm-20261003')
SOURCE = ROOT/'.tmp-lox-round3/combined'
BASE = ROOT/'.tmp-lox-round3/baseline'
COMPILER = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release/bin/mylang')
HELPER = ROOT/'experiments/lox-parity-tree-20261003/validate.py'
CASES = STACK/'experiments/lox-vm-callee-20261003/regressions.json'
FOCUSED = STACK/'.tmp-lox-ast-carrier-20261003/focused-regressions-final.json'
BENCH = ROOT/'.tmp-lox-parity/reference/benchmarks/lox/bench'
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
files = lambda root: {str(p.relative_to(root)): sha(p) for p in sorted(root.rglob('*')) if p.is_file()}

def write(name, value):
    (WORK/name).write_text(json.dumps(value, indent=2)+'\n')

bins = {'control-'+b: str(ROOT/('.tmp-lox-round3/bin/baseline-'+b)) for b in ['llvm', 'qbe']}
for backend in ['llvm', 'qbe']:
    bins['constant-rc-'+backend] = str(ROOT/('.tmp-lox-round3/bin/combined-'+backend))
    for mode in ['ordinary', 'gc']:
        bins['constant-'+mode+'-'+backend] = str(WORK/('combined-gc-'+backend))
assert not (WORK/'binaries.json').exists()
write('binaries.json', {'binaries': bins})


def snapshot():
    paths = {COMPILER, COMPILER.with_name('qbe'), HELPER, CASES, FOCUSED, Path(__file__).resolve(),
             WORK/'binaries.json', WORK/'gc-builds.json', WORK/'public-qualification.json', WORK/'provider-qualification.json',
             OWN/'experiments/lox-composed-20261003/build-gc.py', OWN/'experiments/lox-composed-20261003/public.py',
             OWN/'experiments/lox-composed-20261003/provider.py', ROOT/'.tmp-lox-round3/combined-build.json',
             OWN/'experiments/lox-vm-constant-20261003/constant-readonly.patch',
             ROOT/'.tmp-lox-round3/combined.json', ROOT/'.tmp-lox-round3/combined.patch', ROOT/'.tmp-lox-parity/inputs/pinned-SPEC.md'}
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
composition = json.loads((ROOT/'.tmp-lox-round3/combined.json').read_text())
assert before['candidate37'] == composition['output_hashes']
assert before['control37'] == composition['input_hashes']['base']
prior = json.loads((ROOT/'.tmp-lox-round3/combined-build.json').read_text())
assert {k:v for k,v in before['candidate37'].items() if k.endswith('.my')} == prior['source_sha256']
gc = json.loads((WORK/'gc-builds.json').read_text())
assert before['candidate37'] == gc['source37'] and gc['verified_after']
assert sha(COMPILER) == prior['compiler_sha256'] == gc['compiler_sha256']
assert sha(COMPILER) == 'd14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040'
assert sha(COMPILER.with_name('qbe')) == gc['qbe_sha256']
assert sha(COMPILER.with_name('qbe')) == '99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
assert sha(bins['control-llvm']) == 'a0ec4ffd470b309d70d35cbab69215b778fbdbc2d71d3d8761703da18feca594'
assert sha(bins['control-qbe']) == '2c00b0b84d173010036608940e06a61206f535662284eac02eb289d9dee470d6'
assert sha(bins['constant-rc-llvm']) == '51053461d1b4c1e1196bb9be512611e98e649598ed66df1e2e69faf341b619ab'
assert sha(bins['constant-rc-qbe']) == '63194a9740d33754da6c9f7e26ee5b0badbe4f31cbdce936de262c95de6aa2ef'
for row in prior['builds']+gc['runs']:
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
assert len(r['samples']) == 1168 and len(r['unrun']) == 80 and r['verified_after']
identity = lambda row: (row['name'], row['tier'], row['engine'], row['arm'], row['lox_gc_stress'])
actual = {identity(row) for row in r['samples']}
unrun = {identity(row) for row in r['unrun']}
keys = {(row['name'], row['tier'], row['engine']) for row in r['samples']}
expected = {(n, t, e, arm, stress) for n, t, e in keys for arm in bins if not arm.startswith('control-') for stress in [False, True]}
assert len(keys) == 104 and len(actual) == 1168 and len(unrun) == 80
assert actual.isdisjoint(unrun) and actual|unrun == expected
assert all(row['actual'] == row['expected'] for row in r['samples'])
counts = Counter('native_gc_stress' if row['native_gc_stress'] else 'rc' if '-rc-' in row['arm'] else 'ordinary_gc' for row in r['samples'])
assert counts == {'rc': 416, 'ordinary_gc': 416, 'native_gc_stress': 336}


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
            candidate, cmd = observe(bins['constant-rc-'+backend], script, engine, lox, True)
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
            candidate, cmd = observe(bins['constant-'+mode+'-'+backend], script, 'vm', lox, native)
            assert candidate == control
            boundary.append({'backend': backend, 'lox_gc_stress': lox, 'native_gc_stress': native,
                             'arm': 'constant-'+mode+'-'+backend, 'source_sha256': sha(script),
                             'argv': cmd, 'control_argv': ca, 'expected': control, 'actual': candidate})
assert len(boundary) == 12
write('constant-255-boundary.json', {'samples': boundary})
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
                    arm='constant-'+mode+'-'+backend
                    candidate,cmd=observe(bins[arm],script,engine,lox,native)
                    row={'name':case['name'],'engine':engine,'backend':backend,'arm':arm,
                         'lox_gc_stress':lox,'native_gc_stress':native,'source_sha256':sha(script),
                         'argv':cmd,'control_argv':ca,'expected':control,'actual':candidate}
                    assert candidate==control
                    focused.append(row)
                    write('ast-focused-observations.json',{'samples':focused})
    print('PASS composed AST focused program',case['name'],flush=True)
assert len(focused)==96
after = snapshot()
assert after['candidate37'] == before['candidate37']
assert after['control37'] == before['control37']
assert after['artifacts_sha256'] == before['artifacts_sha256']
write('completed.json', {'before': before, 'after': after, 'verified_after': True,
      'finished_utc': datetime.now(timezone.utc).isoformat(), 'helper_status': run.returncode,
      'mode_counts': dict(counts), 'bounded_observations': 1168, 'boundary_observations': 12, 'ast_focused_observations':96,
      'rc_native_stress_refusal_pairs': 8, 'native_smoke_unrun': r['unrun'],
      'receipt_sha256': {name: sha(WORK/name) for name in ['binaries.json', 'command.json',
         'observations.json', 'observations.log', 'rc-native-stress-refusals.json', 'constant-255-boundary.json','ast-focused-observations.json']}})
print('1168 bounded +12 boundary +96 AST-focused pairs and8 refusals pass; all37/source/artifact hashes unchanged', flush=True)

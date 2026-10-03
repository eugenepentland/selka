#!/usr/bin/env python3
"""Fresh exact selected AST RC/GC matrix, with explicit native-stress scope."""
from pathlib import Path
from collections import Counter
import hashlib, json, os, subprocess

lane = Path(__file__).resolve().parents[2]
scratch = lane / '.tmp-lox-native-policy-20261003'
work = scratch / 'native-v2'
work.mkdir(exist_ok=False)
(work / 'tmp').mkdir()
root = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003')
borrow = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-borrow-assert-20261003/.tmp-lox-borrow-assert-20261003')
vm = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-vm-20261003')
source = root / '.tmp-lox-round3/ast'
compiler = scratch / 'compiler-final-v2/bin/mylang'
control_compiler = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release/bin/mylang')
qbe = control_compiler.with_name('qbe')
helper = lane / 'experiments/lox-native-policy-20261003/validate-native-v2.py'
bench = root / '.tmp-lox-parity/reference/benchmarks/lox/bench'
cases = vm / 'experiments/lox-vm-callee-20261003/regressions.json'
focused_cases = vm / 'experiments/lox-tree-ast-carrier-20261003/regressions.json'
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
files = lambda p: {str(f.relative_to(p)): sha(f) for f in sorted(p.rglob('*')) if f.is_file()}
write = lambda name, data: (work / name).write_text(json.dumps(data, indent=2) + '\n')
frozen = json.loads((scratch / 'frozen-source-v2.json').read_text())
builds = json.loads((scratch / 'builds-v2.json').read_text())
assert builds['verified_after'] and builds['source37'] == frozen['source37']
assert sha(compiler) == builds['compiler_sha256']
assert sha(control_compiler) == 'd14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040'
assert sha(qbe) == '99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
assert not (set(os.sched_getaffinity(0)) & {2, 3, 10, 11})
bins = {'control-' + backend: str(borrow / ('fixed-' + backend + '-ast')) for backend in ['llvm', 'qbe']}
assert sha(bins['control-llvm']) == '180575c3fc2e46a16ed8dd290e289963a87603b5a7c0cf8bb0e03ba7cf794361'
assert sha(bins['control-qbe']) == '246f21781fd58c7141dbe0992101c842e62d732d9ce47e209d55821d02b11b25'
for row in builds['runs']:
    assert row['status'] == 0 and all(sha(p) == h for p, h in row['artifacts_sha256'].items())
    if row['runtime'] == 'rc':
        bins['native-policy-rc-' + row['backend']] = row['binary']
    else:
        bins['native-policy-ordinary-' + row['backend']] = row['binary']
        bins['native-policy-gc-' + row['backend']] = row['binary']
write('binaries.json', {'binaries': bins})
paths = {compiler, control_compiler, qbe, helper, cases, focused_cases, Path(__file__).resolve(), work / 'binaries.json',
         scratch / 'builds-v2.json', scratch / 'frozen-source-v2.json', borrow / 'static-builds.json',
         root / '.tmp-lox-parity/inputs/pinned-SPEC.md'}
paths.update(p for p in bench.rglob('*') if p.is_file())
paths.update(root / 'docs/audits/evidence' / name for name in ['d9-lox-env-reads-runs.json.gz', 'd9-lox-class-method-runs.json.gz'])
for binary in set(bins.values()):
    manifest = Path(binary + '.qbe-manifest.json')
    paths.update([Path(binary), manifest, Path(binary + '.qbe-receipt'), Path(json.loads(manifest.read_text())['runtime_object'])])
def snapshot():
    return dict(source37=files(source), core878={p: sha(lane / p) for p in frozen['core']},
                artifacts_sha256={str(p): sha(p) for p in sorted(paths)})
from prefixes_v2 import snapshot as prefixes_snapshot
prefixes_before = prefixes_snapshot()
before = snapshot()
assert before['source37'] == frozen['source37'] and before['core878'] == frozen['core']
write('preflight.json', before)
env = {k: v for k, v in os.environ.items() if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
env['TMPDIR'] = str(work / 'tmp')
argv = ['python3', str(helper), '--work', str(work), '--bench', str(bench), '--manifest', str(work / 'binaries.json'),
        '--out', str(work / 'observations.json'), '--jobs', '2', '--cases', str(cases),
        '--native-cases', 'closures,instantiation,properties']
write('command.json', dict(argv=argv, cwd=str(lane), environment={'TMPDIR': env['TMPDIR']}, affinity=sorted(os.sched_getaffinity(0))))
with (work / 'observations.log').open('xb') as stream:
    result = subprocess.run(argv, cwd=lane, env=env, stdout=stream, stderr=subprocess.STDOUT)
assert result.returncode == 0, work / 'observations.log'
receipt = json.loads((work / 'observations.json').read_text())
samples = receipt['samples']
assert len(samples) == 1168 and len(receipt['unrun']) == 80 and receipt['verified_after']
keys = {(r['name'], r['tier'], r['engine']) for r in samples}
identity = lambda r: (r['name'], r['tier'], r['engine'], r['arm'], r['lox_gc_stress'])
actual, omitted = {identity(r) for r in samples}, {identity(r) for r in receipt['unrun']}
expected = {(n, t, e, a, s) for n, t, e in keys for a in bins if not a.startswith('control-') for s in [False, True]}
assert len(keys) == 104 and len(actual) == 1168 and len(omitted) == 80
assert actual.isdisjoint(omitted) and actual | omitted == expected
assert all(r['actual'] == r['expected'] for r in samples)
counts = Counter('native_gc_stress' if r['native_gc_stress'] else 'rc' if '-rc-' in r['arm'] else 'ordinary_gc' for r in samples)
assert counts == {'rc': 416, 'ordinary_gc': 416, 'native_gc_stress': 336}
def observe(binary, script, engine, lox, native):
    cmd = [binary, '--engine=' + engine, '--stats'] + (['--gc-stress'] if lox else []) + [str(script)]
    launch = dict(env)
    if native:
        launch['MYLANG_OPTIONS'] = '--gc-stress'
    run = subprocess.run(cmd, env=launch, capture_output=True, timeout=240)
    return dict(status=run.returncode, stdout=run.stdout.decode(), stderr=run.stderr.decode()), cmd
focused = []
for case in json.loads(focused_cases.read_text()):
    script = work / ('validation-inputs/' + case['name'] + '.focused.lox')
    script.write_text(case['source'])
    for engine in ['tree', 'vm']:
        for backend in ['llvm', 'qbe']:
            for lox in [False, True]:
                expected, control_argv = observe(bins['control-' + backend], script, engine, lox, False)
                assert expected['status'] == case['status'] and expected['stdout'] == case['stdout']
                if 'stderr_prefix_by_engine' in case:
                    assert expected['stderr'].startswith(case['stderr_prefix_by_engine'][engine])
                for mode in ['rc', 'ordinary', 'gc']:
                    arm = 'native-policy-' + mode + '-' + backend
                    actual, cmd = observe(bins[arm], script, engine, lox, mode == 'gc')
                    focused.append(dict(name=case['name'], engine=engine, backend=backend, arm=arm,
                                        lox_gc_stress=lox, native_gc_stress=mode == 'gc', source_sha256=sha(script),
                                        argv=cmd, control_argv=control_argv, environment={'MYLANG_OPTIONS': '--gc-stress'} if mode == 'gc' else {},
                                        expected=expected, actual=actual))
                    write('focused-observations.json', {'samples': focused})
                    assert actual == expected, focused[-1]
assert len(focused) == 96
refusals = []
script = work / 'validation-inputs/closures.vm.smoke.lox'
for backend in ['llvm', 'qbe']:
    for engine in ['tree', 'vm']:
        for lox in [False, True]:
            expected, control_argv = observe(bins['control-' + backend], script, engine, lox, True)
            actual, cmd = observe(bins['native-policy-rc-' + backend], script, engine, lox, True)
            refusals.append(dict(backend=backend, engine=engine, lox_gc_stress=lox, native_gc_stress=True,
                                 environment={'MYLANG_OPTIONS': '--gc-stress'}, argv=cmd, control_argv=control_argv, expected=expected, actual=actual))
            write('rc-native-stress-refusals.json', {'comparisons': refusals, 'meaning': 'Checked refusals, not program passes'})
            assert actual == expected and actual['status'] == 2 and not actual['stdout'] and '--gc-runtime' in actual['stderr']
assert len(refusals) == 8
after = snapshot()
assert prefixes_snapshot() == prefixes_before
assert after == before
write('completed.json', dict(before=before, after=after, verified_after=True, mode_counts=dict(counts),
                            bounded_pairs=1168, focused_pairs=96, rc_native_stress_refusal_pairs=8, native_smoke_unrun=receipt['unrun'],
                            receipt_sha256={name: sha(work / name) for name in ['binaries.json', 'command.json', 'observations.json',
                                           'observations.log', 'focused-observations.json', 'rc-native-stress-refusals.json']}))
print('1168 fresh bounded +96 AST exact pairs +8 refusals;80 explicit omissions; complete core/source/tool/guest hashes unchanged', flush=True)

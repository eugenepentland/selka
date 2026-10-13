"""Build the final uninstrumented application and compare complete outputs.

Run through build-slot build only after the frozen suite and scalar probes pass.
No runtime timing values are collected by this script.
"""
from pathlib import Path
import hashlib, json, os, shutil, subprocess

HERE = Path(__file__).resolve().parent
ROOT = Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012')
SCRATCH = Path('/home/epentland/ai/canopy/mylang/.tmp/lox-eda-parity/P3/c2-001')
COMPILER = ROOT / '.tmp/lox-eda-parity/coordinator/common-002/install/bin/mylang'
BASELINE = ROOT / '.tmp/lox-eda-parity/P6/native-002/eda/zero-rc'
CANDIDATE = SCRATCH / 'candidate-v2-application'

def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def tree(p):
    return {str(f.relative_to(p)): sha(f) for f in sorted(p.rglob('*')) if f.is_file()}

def save(p, value):
    p.write_text(json.dumps(value, indent=2) + '\n')

assert os.environ.get('MYLANG_ADMISSION_KIND') == 'build'
assert sha(COMPILER) == '9bedb835438615d79ed8f2985352877a8c844eebeb74cd95a1d276332b6b0c6a'
suite = json.loads((HERE / 'suite-v2-tests.json').read_text())
assert suite['passed'] == 330 and all(suite[k] == 0 for k in ['failed', 'skipped', 'cached', 'unsupported'])
probes = json.loads((HERE / 'probe-results.json').read_text())
assert len(probes['boundaries']) == 9
sources = {str(p): sha(p) for p in sorted((SCRATCH / 'candidate-v2/eda').glob('*.my'))}
assert all(sha(p) == v for p, v in probes['source_sha256'].items())
receipt = {'compiler': str(COMPILER), 'compiler_sha256': sha(COMPILER),
           'sources': sources, 'suite_sha256': sha(HERE / 'suite-v2-tests.json'),
           'probe_receipt_sha256': sha(HERE / 'probe-results.json'), 'cases': {}}
command = [str(COMPILER), 'build', str(SCRATCH / 'candidate-v2/eda/main.my'),
           '--release', '--experimental-zero-rc', '--verify-facts', '--cache-dir',
           str(SCRATCH / 'cache-application-v2'), '--emit-llvm',
           str(SCRATCH / 'candidate-v2-application.ll'), '-o', str(CANDIDATE)]
env = dict(os.environ)
env.pop('MYLANG_COUNTERS', None)
env.pop('MYL_CORE_LEAKCHECK', None)
with (HERE / 'application-build.log').open('w') as log:
    result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT)
receipt['build'] = {'command': command, 'returncode': result.returncode}
save(HERE / 'application-results.json', receipt)
assert result.returncode == 0
receipt['binaries'] = {arm: {'path': str(binary), 'sha256': sha(binary)}
                      for arm, binary in [('baseline', BASELINE), ('candidate', CANDIDATE)]}
for case in ['rds3+flat', 'cyclops-digital-pcb']:
    spec_path = ROOT / f'experiments/lox-eda-parity-20261013/attempts/runtime-001/specs/eda-{case}.json'
    spec = json.loads(spec_path.read_text())
    pins = {str(Path(spec['arms']['zig-fast'][0])): sha(spec['arms']['zig-fast'][0])}
    pins.update({str(p): sha(p) for d in spec['identity_dirs'] for p in sorted(Path(d).rglob('*')) if p.is_file()})
    model = spec['arms']['zig-fast'][2]
    pins[model] = sha(model)
    values = {}
    for arm, binary in [('zig', Path(spec['arms']['zig-fast'][0])), ('baseline', BASELINE), ('candidate', CANDIDATE)]:
        output = SCRATCH / 'qualification-outputs' / case / arm
        shutil.rmtree(output, ignore_errors=True)
        argv = [str(binary), *spec['arms']['zig-fast'][1:]]
        argv[argv.index('--out-dir') + 1] = str(output)
        p = subprocess.run(argv, cwd=spec['cwd'], env=env, capture_output=True, timeout=120)
        (HERE / f'{case}-{arm}.stdout').write_bytes(p.stdout)
        (HERE / f'{case}-{arm}.stderr').write_bytes(p.stderr)
        values[arm] = {'argv': argv, 'returncode': p.returncode,
                       'stdout_sha256': hashlib.sha256(p.stdout).hexdigest(),
                       'stderr_sha256': hashlib.sha256(p.stderr).hexdigest(), 'outputs': tree(output)}
        assert p.returncode == 0, (case, arm, p.stderr)
    comparable = lambda value: {k: value[k] for k in ['returncode', 'stdout_sha256', 'stderr_sha256', 'outputs']}
    assert comparable(values['baseline']) == comparable(values['candidate']), case
    assert values['candidate']['outputs'] == values['zig']['outputs'] == tree(Path(spec['golden_dir'])), case
    assert all(sha(p) == value for p, value in pins.items())
    receipt['cases'][case] = {'spec': str(spec_path), 'spec_sha256': sha(spec_path), 'identities': pins, 'arms': values}
    save(HERE / 'application-results.json', receipt)
assert all(sha(p) == value for p, value in sources.items())
receipt['status'] = 'passed'
save(HERE / 'application-results.json', receipt)
print('both full application outputs match frozen C2, Zig, and complete golden trees')

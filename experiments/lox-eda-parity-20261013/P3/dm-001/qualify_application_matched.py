"""Matched full RDS3-flat counters/output and native copy calls; no timing."""
from pathlib import Path
import hashlib, json, os, re, shutil, subprocess

HERE = Path(__file__).resolve().parent
ROOT = Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012')
SCRATCH = Path('/home/epentland/ai/canopy/mylang/.tmp/lox-eda-parity/P3/dm-001')
reuse = json.loads((HERE / 'baseline-reuse.json').read_text())
COMPILER = Path(reuse['compiler'])
def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(p, d):
    p.write_text(json.dumps(d, indent=2) + '\n')
def tree(p):
    return {str(f.relative_to(p)): sha(f) for f in sorted(p.rglob('*')) if f.is_file()}
assert os.environ.get('MYLANG_ADMISSION_KIND') == 'build'
assert sha(COMPILER) == reuse['compiler_sha256']
assert all(sha(Path(reuse['installation']) / p) == v for p, v in reuse['installation_files'].items())
assert all(sha(p) == v for p, v in reuse['receipts'].items())
for name, expected in [('candidate-suite.json', 328), ('focused-candidate.json', 3), ('focused-baseline-suite.json', 3)]:
    d = json.loads((HERE / name).read_text())
    assert d['passed'] == expected and all(d[k] == 0 for k in ['failed', 'cached', 'skipped', 'unsupported'])
pins = json.loads((HERE / 'source-pins.json').read_text())
HERE = HERE / 'matched'
HERE.mkdir(exist_ok=False)
def unchanged():
    for arm, files in pins.items():
        assert {p.name: sha(p) for p in (SCRATCH / arm / 'eda').glob('*.my')} == files
env = dict(os.environ)
env.pop('MYLANG_COUNTERS', None)
env.pop('MYL_CORE_LEAKCHECK', None)
commands = []
receipt = {'compiler': str(COMPILER), 'compiler_sha256': sha(COMPILER), 'baseline_reuse_sha256': sha(HERE.parent / 'baseline-reuse.json'), 'sources': pins, 'arms': {}, 'comparison_flags': ['--release', '--experimental-zero-rc'], 'counted_extra_flag': '--counters'}
for counted in [False, True]:
    unchanged()
    label = 'candidate-matched-counted' if counted else 'candidate-matched'
    binary = SCRATCH / label
    command = [str(COMPILER), 'build', str(SCRATCH / 'candidate/eda/main.my'), '--release', '--experimental-zero-rc', '--cache-dir', str(SCRATCH / 'cache-application'), '-o', str(binary)]
    if counted:
        command.append('--counters')
    else:
        command.extend(['--emit-llvm', str(SCRATCH / 'candidate-matched.ll')])
    with (HERE / (label + '-build.log')).open('w') as log:
        result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT)
    commands.append({'command': command, 'returncode': result.returncode})
    save(HERE / 'application-commands.json', commands)
    assert result.returncode == 0
    unchanged()
spec_path = ROOT / 'experiments/lox-eda-parity-20261013/attempts/runtime-001/specs/eda-rds3+flat.json'
spec = json.loads(spec_path.read_text())
input_pins = {str(p): sha(p) for d in spec['identity_dirs'] for p in sorted(Path(d).rglob('*')) if p.is_file()}
input_pins[spec['arms']['zig-fast'][2]] = sha(spec['arms']['zig-fast'][2])
receipt['input_pins'] = input_pins
for arm, binary in [('baseline', Path(reuse['binaries']['zero-rc-counted']['path'])), ('candidate', SCRATCH / 'candidate-matched-counted')]:
    unchanged()
    if arm == 'baseline':
        assert sha(binary) == reuse['binaries']['zero-rc-counted']['sha256']
    output = SCRATCH / 'outputs' / arm
    shutil.rmtree(output, ignore_errors=True)
    argv = [str(binary), *spec['arms']['zig-fast'][1:]]
    argv[argv.index('--out-dir') + 1] = str(output)
    raw = HERE / (arm + '-counters.json')
    result = subprocess.run(argv, cwd=spec['cwd'], capture_output=True, env={**env, 'MYLANG_COUNTERS': str(raw), 'MYL_CORE_LEAKCHECK': '1'}, timeout=120)
    (HERE / (arm + '.stdout')).write_bytes(result.stdout)
    (HERE / (arm + '.stderr')).write_bytes(result.stderr)
    commands.append({'command': argv, 'counter_path': str(raw), 'returncode': result.returncode})
    save(HERE / 'application-commands.json', commands)
    assert result.returncode == 0
    counters = json.loads(raw.read_text())
    totals = counters['totals']
    assert totals['live_bytes_at_exit'] == 0
    assert all(totals[k] == 0 for k in ['runtime_retains', 'runtime_releases', 'shared_retains', 'shared_releases', 'share_marks'])
    assert all(counters['kinds'][k]['count'] == 0 for k in ['retain', 'release', 'unique_test'])
    receipt['arms'][arm] = {'binary': str(binary), 'binary_sha256': sha(binary), 'counter_sha256': sha(raw), 'stdout_sha256': hashlib.sha256(result.stdout).hexdigest(), 'stderr_sha256': hashlib.sha256(result.stderr).hexdigest(), 'outputs': tree(output), 'totals': totals, 'attachment_function': next(x for x in counters['functions'] if x['name'] == 'diagram_membership::compute_sub_block_attachments')}
    save(HERE / 'application-results.json', receipt)
a, b = receipt['arms']['baseline'], receipt['arms']['candidate']
for key in ['stdout_sha256', 'stderr_sha256', 'outputs']:
    assert a[key] == b[key]
assert b['outputs'] == tree(Path(spec['golden_dir']))
assert all(sha(p) == v for p, v in input_pins.items())
unchanged()
symbol = 'my.diagram_membership::compute_sub_block_attachments'
native = {}
for arm, binary in [('baseline', Path(reuse['binaries']['zero-rc']['path'])), ('candidate', SCRATCH / 'candidate-matched')]:
    asm = subprocess.check_output(['objdump', '--no-show-raw-insn', '--disassemble=' + symbol, str(binary)], text=True)
    (HERE / (arm + '-attachments.asm')).write_text(asm)
    copies = [line.strip() for line in asm.splitlines() if re.search(r'\bcall\b', line) and re.search(r'copy|clone', line)]
    native[arm] = {'binary_sha256': sha(binary), 'copy_call_sites': copies}
receipt['native_copy_calls'] = native
receipt['status'] = 'passed'
save(HERE / 'application-results.json', receipt)
print('full RDS3-flat outputs match, counters have zero RC/exit-live, native copy callsites retained')

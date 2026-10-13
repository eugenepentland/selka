"""Normalize one output path for matched counters and qualify the second case."""
from pathlib import Path
import hashlib, json, os, shutil, subprocess

HERE = Path(__file__).resolve().parent
ROOT = Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012')
SCRATCH = Path('/home/epentland/ai/canopy/mylang/.tmp/lox-eda-parity/P3/dm-001')
reuse = json.loads((HERE / 'baseline-reuse.json').read_text())
matched = json.loads((HERE / 'matched/application-results.json').read_text())
DEST = HERE / 'matched-final'
DEST.mkdir(exist_ok=False)
assert os.environ.get('MYLANG_ADMISSION_KIND') == 'build'
def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def tree(p):
    return {str(f.relative_to(p)): sha(f) for f in sorted(p.rglob('*')) if f.is_file()}
receipt = {'flags': ['--release', '--experimental-zero-rc'], 'counted_extra': '--counters',
           'matched_native_receipt_sha256': sha(HERE / 'matched/application-results.json'),
           'note': 'Same output path and parent filesystem state for both arms; no timing collected', 'cases': {}}
env = dict(os.environ)
env.pop('MYLANG_COUNTERS', None)
env.pop('MYL_CORE_LEAKCHECK', None)
for case in ['rds3+flat', 'cyclops-digital-pcb']:
    spec_path = ROOT / f'experiments/lox-eda-parity-20261013/attempts/runtime-001/specs/eda-{case}.json'
    spec = json.loads(spec_path.read_text())
    output = SCRATCH / ('qualified-' + case)
    arms = [('baseline', Path(reuse['binaries']['zero-rc-counted' if case == 'rds3+flat' else 'zero-rc']['path'])),
            ('candidate', SCRATCH / ('candidate-matched-counted' if case == 'rds3+flat' else 'candidate-matched'))]
    if case != 'rds3+flat':
        arms.insert(0, ('zig', Path(spec['arms']['zig-fast'][0])))
    values = {}
    for arm, binary in arms:
        shutil.rmtree(output, ignore_errors=True)
        argv = [str(binary), *spec['arms']['zig-fast'][1:]]
        argv[argv.index('--out-dir') + 1] = str(output)
        raw = DEST / (arm + '-counters.json')
        run_env = {**env, 'MYLANG_COUNTERS': str(raw), 'MYL_CORE_LEAKCHECK': '1'} if case == 'rds3+flat' else env
        result = subprocess.run(argv, cwd=spec['cwd'], env=run_env, capture_output=True, timeout=120)
        (DEST / f'{case}-{arm}.stdout').write_bytes(result.stdout)
        (DEST / f'{case}-{arm}.stderr').write_bytes(result.stderr)
        assert result.returncode == 0
        value = {'argv': argv, 'binary_sha256': sha(binary), 'returncode': result.returncode,
                 'stdout_sha256': hashlib.sha256(result.stdout).hexdigest(),
                 'stderr_sha256': hashlib.sha256(result.stderr).hexdigest(), 'outputs': tree(output)}
        if case == 'rds3+flat':
            doc = json.loads(raw.read_text())
            assert doc['totals']['live_bytes_at_exit'] == 0
            assert all(doc['totals'][k] == 0 for k in ['runtime_retains', 'runtime_releases', 'shared_retains', 'shared_releases', 'share_marks'])
            assert all(doc['kinds'][k]['count'] == 0 for k in ['retain', 'release', 'unique_test'])
            value['totals'] = doc['totals']
            value['counter_sha256'] = sha(raw)
        values[arm] = value
    comparable = lambda v: {k: v[k] for k in ['returncode', 'stdout_sha256', 'stderr_sha256', 'outputs']}
    assert comparable(values['baseline']) == comparable(values['candidate'])
    assert values['candidate']['outputs'] == tree(Path(spec['golden_dir']))
    if 'zig' in values:
        assert values['zig']['outputs'] == values['candidate']['outputs']
    receipt['cases'][case] = {'spec': str(spec_path), 'spec_sha256': sha(spec_path), 'arms': values}
    (DEST / 'output-results.json').write_text(json.dumps(receipt, indent=2) + '\n')
receipt['status'] = 'passed'
(DEST / 'output-results.json').write_text(json.dumps(receipt, indent=2) + '\n')
print('matched flags and one output path: RDS3-flat counters/output and Cyclops full output pass')

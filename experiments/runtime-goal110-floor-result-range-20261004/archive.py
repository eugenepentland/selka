#!/usr/bin/env python3
"""Archive pinned annotation checks, failed harness history and timings."""
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BASE = ROOT / '.mylang-cache/goal110-floor-result-range'
DEBUG = ROOT / '.mylang-cache/goal110-floor-result-range-debug'
DIAG = ROOT / '.mylang-cache/goal110-floor-result-range-diagnostic'
G4 = Path('/home/epentland/ai/canopy/mylang-worktrees/goal110-g4-rf-20261004/.mylang-cache/goal110-g4-rf')
PIN = '0311796e84e192e3ac1e4fd0bb9d5824b55be1e2'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def pack(name, source):
    raw = source.read_bytes()
    packed = gzip.compress(raw, mtime=0)
    target = HERE / (name + '.gz')
    if target.exists():
        assert target.read_bytes() == packed, target
    else:
        target.write_bytes(packed)
    assert gzip.decompress(target.read_bytes()) == raw
    return {'source_path': str(source.resolve()), 'raw_sha256': digest(raw), 'raw_bytes': len(raw),
            'archive': target.name, 'gzip_sha256': digest(packed), 'gzip_bytes': len(packed)}


subprocess.run(['git', 'diff', '--exit-code', PIN, '--', 'src', 'vendor/qbe', 'docs',
                'build.zig', 'build.zig.zon', '.zigversion', '.qbeversion', 'SPEC.md'], cwd=ROOT, check=True)
screen = json.loads((DEBUG / 'annotation-screen.json').read_text())
assert screen['status'] == 'subset' and len(screen['samples']) == 360 and len(screen['qualification']) == 720
assert screen['identity'] == screen['identity_after'] and screen['binary_hashes'] == screen['binary_hashes_after']
holdouts = json.loads((DEBUG / 'holdouts.json').read_text())
assert holdouts['status'] == 'correctness_complete' and len(holdouts['checks']) == 516
native = json.loads((DIAG / 'native-matrix/native-differential.json').read_text())
assert native['status'] == 'passed' and native['comparison_count'] == 2763 and native['execution_count'] == 5526
text = json.loads((DIAG / 'text/text-checks.json').read_text())
assert text['status'] == 'passed' and len(text['records']) == 200
analysis = json.loads((DEBUG / 'paired-analysis.json').read_text())
assert analysis['status'] == 'replayed' and analysis['outcomes'] == 432
search = json.loads((DIAG / 'search-proof/search-proof.json').read_text())
assert all(row['normalized_equal'] for row in search['comparisons'].values())
sources = {p.name: p for p in BASE.iterdir() if p.is_file() and p.suffix in ('.log', '.json', '.py')}
for path in sorted(DEBUG.iterdir()):
    if path.is_file() and path.suffix in ('.log', '.json', '.md'):
        assert path.name not in sources, path.name
        sources[path.name] = path
sources['runner-manifest.json'] = DEBUG / 'runner/manifest.json'
sources['baseline-g4-manifest.json'] = G4 / 'runner/manifest.json'
sources['baseline-g4-compiler-receipt.json'] = G4 / 'compiler-receipt.json'
for group in ('legacy', 'compute', 'collections', 'text'):
    for backend in ('llvm', 'qbe'):
        name = group + '-my-' + backend + '.qbe-manifest.json'
        sources[name] = DEBUG / 'runner/bin' / name
for directory in ('code-proof', 'search-proof', 'text-static', 'native-static', 'emission-final-bound'):
    for path in sorted((DIAG / directory).iterdir()):
        if path.is_file():
            sources[directory + '-' + path.name] = path
sources['code-proof.json'] = DIAG / 'code-proof/code-proof.json'
sources['search-proof.json'] = DIAG / 'search-proof/search-proof.json'
sources['native-differential.json'] = DIAG / 'native-matrix/native-differential.json'
sources['text-checks.json'] = DIAG / 'text/text-checks.json'
sources['text-build-command.json'] = DIAG / 'text/build-command.json'
sources['text-build-result.json'] = DIAG / 'text/build-result.json'
sources['diagnostic-text.qbe-manifest.json'] = DIAG / 'text/text-my-llvm.qbe-manifest.json'
for build in native['builds']:
    sources['native-' + build['config'] + '-' + build['arm'] + '-manifest.json'] = Path(build['manifest']['path'])
proof = json.loads((DIAG / 'code-proof/code-proof.json').read_text())


def proof_files(value, names):
    if isinstance(value, dict):
        for key, item in value.items():
            if key in ('il', 'ir') and isinstance(item, dict) and 'path' in item:
                sources['proof-' + '-'.join(names) + '.' + key] = Path(item['path'])
            else:
                proof_files(item, names + [key])


proof_files(proof, [])
diff = BASE / 'production-diff.patch'
diff.write_bytes(subprocess.check_output(['git', 'diff', '6cf7bdce11bc205862bf75b9d9ce72e46caad0a2', PIN], cwd=ROOT))
sources['production-diff.patch'] = diff
bindings = [pack(name, path) for name, path in sorted(sources.items())]
evidence = {'status': 'exploratory_complete_unintegrated_search_regression',
            'source_revision': PIN, 'baseline_revision': '6cf7bdce11bc205862bf75b9d9ce72e46caad0a2',
            'created_utc': datetime.now(timezone.utc).isoformat(), 'raw_bindings': bindings,
            'script_bindings': {path.name: digest(path.read_bytes()) for path in sorted(HERE.iterdir())
                                if path.suffix == '.py' or path.name in ('README.md', 'native-fixture.my')},
            'correctness': {'focused_units': 18, 'guardian_checks': 88, 'native_pairs': 2763,
                            'native_executions': 5526, 'ordinary_text_records': 200, 'fresh_holdouts': 516,
                            'six_arm_qualifications': 720, 'six_arm_samples': 360, 'paired_outcomes': 432},
            'outcome': 'Repeat LLVM small equality ratio0.900423 does not close target; repeated large search ratio1.154867 blocks integration. Instruction-identical search caller/helpers have changed placement; causal alignment diagnostic is only proposed.',
            'limitations': ['Debug compiler host; no officialRF host or normal confirmation for031.',
                           'Full process streams retained by native/text/paired checks, not the six-arm runner.',
                           'Pointwise paired bootstrap excludes multiplicity/systematic host noise.',
                           'Static placement identity is not causal performance evidence.',
                           'Live immutable ELFs bound by receipts/manifests; ELF executables are not stored in Git.']}
(HERE / 'evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
print('PASS', len(bindings), 'raw archive bindings;', len(evidence['script_bindings']), 'script bindings')
print('evidence_sha256', digest((HERE / 'evidence.json').read_bytes()))

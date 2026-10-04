#!/usr/bin/env python3
"""Bind immutable native/guest exploratory evidence without goal analysis."""
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
NATIVE = ROOT / '.mylang-cache/goal110-equality-bounded'
RF = ROOT / '.mylang-cache/goal110-equality-bounded-rf'
G4 = Path('/home/epentland/ai/canopy/mylang-worktrees/goal110-g4-rf-20261004/.mylang-cache/goal110-g4-rf')
PIN = '3dcbe723da4036fb7d69046e77e9f8cd16d7512f'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def archive(name, source):
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


validation = RF / 'artifacts-before-archive.json'
subprocess.run(['python3', str(HERE / 'validate-live.py'),
                str(validation if not validation.exists() else RF / 'artifacts-archive-recheck.json')], check=True)
subprocess.run(['git', 'diff', '--exit-code', PIN, '--', 'src', 'vendor/qbe', 'docs',
                'build.zig', 'build.zig.zon', '.zigversion', '.qbeversion'], cwd=ROOT, check=True)
native = json.loads((NATIVE / 'native-distributions.json').read_text())
repeat = json.loads((RF / 'native-controls-repeat.json').read_text())
pair = json.loads((RF / 'bounded-g4-before-after.json').read_text())
screen = json.loads((RF / 'bounded-screen.json').read_text())
assert native['status'] == repeat['status'] == pair['status'] == 'complete'
assert screen['status'] == 'subset' and len(screen['samples']) == 360 and len(screen['qualification']) == 720
assert screen['identity'] == screen['identity_after']
assert screen['binary_hashes'] == screen['binary_hashes_after']
assert len(native['rows']) == 80 and len(repeat['rows']) == 8 and len(pair['rows']) == 12
assert len(json.loads((RF / 'text-checks.json').read_text())['checks']) == 200
holdouts = json.loads((RF / 'holdouts.json').read_text())
assert holdouts['status'] == 'correctness_complete' and len(holdouts['checks']) == 516
sources = {name: NATIVE / name for name in ('native-distributions.json', 'native-distributions.log', 'native-analysis.json')}
sources |= {name: RF / name for name in ('compiler-receipt.json', 'compiler-build.log', 'host-driver.log',
            'guest-build.log', 'text-checks.json', 'text-checks.log', 'holdouts.json', 'holdouts.log',
            'native-controls-repeat.json', 'native-controls-repeat.log', 'bounded-screen.json', 'bounded-screen.log',
            'bounded-g4-before-after.json', 'bounded-g4-before-after.log', 'batch-analysis.json',
            'guest-static.json', 'residual-equality-audit.json', 'artifacts-qualified.json', 'artifacts-ready.json',
            'artifacts-pre-timing.json', 'artifacts-pre-screen.json', 'artifacts-pre-pair.json',
            'artifacts-after-batch.json', 'artifacts-before-archive.json')}
sources['runner-manifest.json'] = RF / 'runner/manifest.json'
sources['baseline-g4-manifest.json'] = G4 / 'runner/manifest.json'
sources['source-commit.log'] = NATIVE / 'source-commit.log'
sources['guardian-archive.log'] = RF / 'guardian-archive.log'
for group in ('legacy', 'compute', 'collections', 'text'):
    for backend in ('llvm', 'qbe'):
        name = f'{group}-my-{backend}.qbe-manifest.json'
        sources[name] = RF / 'runner/bin' / name
for path in sorted((RF / 'static').iterdir()):
    sources['static-' + path.name] = path
bindings = [archive(name, source) for name, source in sources.items()]
evidence = {'status': 'exploratory_complete_unintegrated_independent_guest_repeat_prepared',
            'source_revision': PIN, 'baseline_revision': '6cf7bdce11bc205862bf75b9d9ce72e46caad0a2',
            'created_utc': datetime.now(timezone.utc).isoformat(), 'raw_bindings': bindings,
            'script_bindings': {path.name: digest(path.read_bytes()) for path in sorted(HERE.iterdir())
                                if path.suffix == '.py' or path.name in ('README.md', 'rf-commands.json',
                                    'native-checks-receipt.json', 'helper-builds.json', 'helper-static.json',
                                    'prior-scalar-context.json', 'native-screen-evidence.json')},
            'sessions': {'native80': native['session_id'], 'native8_repeat': repeat['session_id'],
                         'six_arm': screen['measurement_session_id'], 'matched_G4': pair['session_id']},
            'correctness': {'native_sanitizer_suites': 5, 'unicode_outcomes': 90048,
                            'new_RF_text_records': 200, 'new_holdouts': 516,
                            'six_arm_qualifications': 720, 'paired_guest_outcomes': 288,
                            'native80_measured_calls': 800, 'native_repeat_measured_calls': 240},
            'outcome': 'LLVM small equality3.7%paired improvement remains above1.10x target; LLVM large search5.64%point-estimate regression keeps candidate unintegrated. Native128-middle repeat costs4.68%owned,2.43%view.',
            'limitations': ['Exploratory5r1w guest screen and native helpers do not establish normal goal confirmation.',
                           'Native10M calibration cap leaves some approximately20ms calls below nominal30ms.',
                           'Pointwise paired intervals do not cover between-session/systematic noise or multiplicity.',
                           'Native raw pilot/warmup/timed process streams are complete; guest text records and paired runner do not retain complete process streams.',
                           'Historical scalar GCC/noLTO context is not a matched comparator for LLVM/defaultnative/fullLTO.',
                           'Shared kernel instructions/frame/layout change; no scanner-only causal claim.',
                           'No MyLangELFs stored in Git; live immutable binaries are bound by manifests/receipts/hashes.']}
(HERE / 'evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
print('PASS', len(bindings), 'raw gzip bindings;', len(evidence['script_bindings']), 'metadata/script bindings')
print('evidence_sha256', digest((HERE / 'evidence.json').read_bytes()))

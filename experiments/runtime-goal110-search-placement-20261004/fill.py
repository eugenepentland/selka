#!/usr/bin/env python3
"""Build the approved32-byte assembly placement counterfactual once."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BASE = ROOT / '.mylang-cache/goal110-search-placement'
WORK = BASE / 'fill32'
WORK.mkdir(parents=True, exist_ok=True)


def binding(path):
    return {'path': str(path.resolve()), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'bytes': path.stat().st_size}


subprocess.run(['git', 'diff', '--exit-code', '0311796e84e192e3ac1e4fd0bb9d5824b55be1e2',
                '--', 'src', 'vendor/qbe', 'docs', 'build.zig', 'build.zig.zon', 'SPEC.md'], cwd=ROOT, check=True)
capture_path = BASE / 'capture/capture-build.json'
capture = json.loads(capture_path.read_text())
assert capture['exact_guest_reproduction'] and capture['exit_status'] == 0
assert binding(Path(capture['guest']['path'])) == capture['guest']
wrapper = HERE / 'zig-wrapper.py'
assert binding(wrapper) == capture['wrapper']
proof_path = BASE / 'mapping/label-proof.json'
proof = json.loads(proof_path.read_text())
assert proof['status'] == 'mapped' and proof['loop_offset'] == 0xd60
assert proof['original_guest'] == capture['guest']
raw = proof['original_raw_assembly']
assert binding(Path(raw['path'])) == raw
config = json.loads((BASE / 'capture/wrapper-config.json').read_text())
config |= {'mode': 'fill32', 'capture_directory': str(WORK / 'tool-calls'),
           'raw_assembly_sha256': raw['sha256'], 'loop_label': proof['loop_label'],
           'loop_normalized_sha256': '436895a0e3086377338bc359fad8b4c9cdbfb107314a1440d31823f05754b088'}
config_path = WORK / 'wrapper-config.json'
config_path.write_text(json.dumps(config, indent=2) + '\n')
argv = capture['command'].copy()
output = WORK / 'text-my-llvm'
assert not output.exists(), 'Never overwrite a prepared diagnostic guest'
argv[argv.index('-o') + 1] = str(output)
argv[argv.index('--cache-dir') + 1] = str(WORK / 'mycache')
environment = {'TMPDIR': str(WORK / 'tmp'), 'ZIG_LOCAL_CACHE_DIR': str(WORK / 'zig-local'),
               'ZIG_GLOBAL_CACHE_DIR': str(WORK / 'zig-global'),
               'MYLANG_LLVM_DUMP': str(WORK / 'dump'), 'MYL_PLACEMENT_CONFIG': str(config_path)}
for key in ('TMPDIR', 'ZIG_LOCAL_CACHE_DIR', 'ZIG_GLOBAL_CACHE_DIR', 'MYLANG_LLVM_DUMP'):
    Path(environment[key]).mkdir(parents=True, exist_ok=True)
report = {'kind': 'diagnostic-placement-fill32', 'pid': os.getpid(), 'source_revision': capture['source_revision'],
          'started_utc': datetime.now(timezone.utc).isoformat(), 'command': argv, 'environment': environment,
          'capture_build': binding(capture_path), 'label_proof': binding(proof_path), 'config': binding(config_path),
          'driver': binding(Path(__file__)), 'wrapper': binding(wrapper), 'compiler': capture['compiler'],
          'compiler_receipt': capture['compiler_receipt'], 'status': 'building'}
path = WORK / 'fill-build.json'
path.write_text(json.dumps(report, indent=2) + '\n')
print('START fill32 PID', os.getpid(), report['started_utc'], flush=True)
result = subprocess.run(argv, cwd=ROOT, env=os.environ | environment, capture_output=True, text=True)
report |= {'exit_status': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr,
           'finished_utc': datetime.now(timezone.utc).isoformat()}
if result.returncode == 0:
    report['guest'] = binding(output)
    report['guest_manifest'] = binding(Path(str(output) + '.qbe-manifest.json'))
    report['status'] = 'built_diagnostic_only'
path.write_text(json.dumps(report, indent=2) + '\n')
assert result.returncode == 0, result.stderr
print('PASS fill32 guest', report['guest']['sha256'], report['finished_utc'], flush=True)

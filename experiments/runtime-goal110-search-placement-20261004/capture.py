#!/usr/bin/env python3
"""Build one diagnostic passthrough guest, refusing nonidentical code."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
WORK = ROOT / '.mylang-cache/goal110-search-placement/capture'
WORK.mkdir(parents=True, exist_ok=True)
template = ROOT / '.mylang-cache/goal110-floor-result-range-diagnostic/text/build-command.json'
receipt = ROOT / '.mylang-cache/goal110-floor-result-range-debug/compiler-receipt.json'
expected = '892b089c25a316f80d8ad000d93125f59ffa871893d3d15526e7b05bb29319a0'


def binding(path):
    return {'path': str(path.resolve()), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'bytes': path.stat().st_size}


subprocess.run(['git', 'diff', '--exit-code', '0311796e84e192e3ac1e4fd0bb9d5824b55be1e2',
                '--', 'src', 'vendor/qbe', 'docs', 'build.zig', 'build.zig.zon', 'SPEC.md'], cwd=ROOT, check=True)
argv = json.loads(template.read_text())['command']
real = Path(argv[argv.index('--zig') + 1]).resolve()
wrapper = HERE / 'zig-wrapper.py'
wrapper.chmod(0o755)
config = WORK / 'wrapper-config.json'
config.write_text(json.dumps({'mode': 'capture', 'real_zig': str(real),
                              'real_zig_sha256': binding(real)['sha256'],
                              'capture_directory': str(WORK / 'tool-calls')}, indent=2) + '\n')
output = WORK / 'text-my-llvm'
assert not output.exists(), 'Never overwrite a prepared diagnostic guest'
argv[argv.index('-o') + 1] = str(output)
argv[argv.index('--cache-dir') + 1] = str(WORK / 'mycache')
argv[argv.index('--zig') + 1] = str(wrapper)
environment = {'TMPDIR': str(WORK / 'tmp'), 'ZIG_LOCAL_CACHE_DIR': str(WORK / 'zig-local'),
               'ZIG_GLOBAL_CACHE_DIR': str(WORK / 'zig-global'),
               'MYLANG_LLVM_DUMP': str(WORK / 'dump'), 'MYL_PLACEMENT_CONFIG': str(config)}
for key in ('TMPDIR', 'ZIG_LOCAL_CACHE_DIR', 'ZIG_GLOBAL_CACHE_DIR', 'MYLANG_LLVM_DUMP'):
    Path(environment[key]).mkdir(parents=True, exist_ok=True)
report = {'kind': 'diagnostic-placement-passthrough', 'pid': os.getpid(),
          'source_revision': '0311796e84e192e3ac1e4fd0bb9d5824b55be1e2',
          'started_utc': datetime.now(timezone.utc).isoformat(), 'command': argv,
          'environment': environment, 'template': binding(template), 'compiler_receipt': binding(receipt),
          'compiler': binding(Path(argv[2])), 'wrapper': binding(wrapper), 'config': binding(config),
          'driver': binding(Path(__file__)), 'expected_guest_sha256': expected}
path = WORK / 'capture-build.json'
path.write_text(json.dumps(report, indent=2) + '\n')
print('START capture PID', os.getpid(), report['started_utc'], flush=True)
result = subprocess.run(argv, cwd=ROOT, env=os.environ | environment, capture_output=True, text=True)
report |= {'exit_status': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr,
           'finished_utc': datetime.now(timezone.utc).isoformat()}
if result.returncode == 0:
    report['guest'] = binding(output)
    report['guest_manifest'] = binding(Path(str(output) + '.qbe-manifest.json'))
    report['exact_guest_reproduction'] = report['guest']['sha256'] == expected
path.write_text(json.dumps(report, indent=2) + '\n')
assert result.returncode == 0, result.stderr
assert report['exact_guest_reproduction'], report['guest']
print('PASS exact passthrough guest', expected, report['finished_utc'], flush=True)

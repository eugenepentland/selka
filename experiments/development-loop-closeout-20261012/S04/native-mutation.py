#!/usr/bin/env python3
"""Operational native boundary failure/revert evidence; no latency claim."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

root = Path(__file__).resolve().parents[3]
out = Path(__file__).resolve().parent
zig = Path('/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig')
env = dict(os.environ, ZIG_LOCAL_CACHE_DIR=str(root / '.zig-cache-S04'),
           ZIG_GLOBAL_CACHE_DIR='/home/epentland/ai/canopy/.zig-global-cache',
           TMPDIR=str(root / '.mylang-cache/S04-tmp'))
command = [str(root / 'scripts/build-slot.sh'), 'build', str(zig), 'build',
           'test-tooling-units', '-Dtest-filter=a fix round', '--summary', 'all']
source = root / 'src/fix_plan.zig'
original = source.read_bytes()
rows = []
try:
    for phase in ('baseline', 'semantic-mutation', 'revert'):
        if phase == 'semantic-mutation':
            changed = original.replace(b'if (collides(fix, taken.items)) continue;',
                                       b'if (!collides(fix, taken.items)) continue;')
            assert changed != original
            source.write_bytes(changed)
        elif phase == 'revert':
            source.write_bytes(original)
        started = time.monotonic()
        result = subprocess.run(command, cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (out / (phase + '.log')).write_bytes(result.stdout)
        rows.append({'phase': phase, 'status': result.returncode,
                     'operational_elapsed_seconds': time.monotonic() - started,
                     'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest()})
        if phase == 'semantic-mutation':
            assert result.returncode != 0, result.stdout.decode()
            assert b'TestExpectedEqual' in result.stdout, result.stdout.decode()
        else:
            assert result.returncode == 0, result.stdout.decode()
finally:
    source.write_bytes(original)
    (out / 'native-mutation.json').write_text(json.dumps({
        'command': command, 'environment': {key: env[key] for key in ('ZIG_LOCAL_CACHE_DIR', 'ZIG_GLOBAL_CACHE_DIR', 'TMPDIR')},
        'mode': 'Debug', 'zig_sha256': hashlib.sha256(zig.read_bytes()).hexdigest(),
        'results': rows, 'isolated_latency_qualification': False}, indent=2) + '\n')
print(json.dumps(rows))

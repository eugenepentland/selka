#!/usr/bin/env python3
"""Invoke the complete verification coordinator with unchanged qualified inputs."""
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def main():
    inputs = json.loads((HERE / 'component-route.json').read_text())['qualified_inputs']
    pin = next(x['path'] for x in inputs if x['path'].endswith('.json'))
    archive = next(x['path'] for x in inputs if x['path'].endswith('.tar'))
    assert os.environ.get('MYLANG_SLOT_DIR')
    command = ['python3', '-B', 'scripts/verify_cache.py', '--zig', os.environ['ZIG'], '--',
               '-j' + os.environ['MYLANG_DEV_JOBS'], '--maxrss', os.environ['MYLANG_DEV_MAXRSS'],
               '-Dcomponent-owned-compiler-pin=' + pin, '-Dcomponent-seed-source=' + archive,
               '--summary', 'all', '--seed=0']
    attempt = 1
    while (HERE / ('gate-%02d' % attempt)).exists():
        attempt += 1
    output = HERE / ('gate-%02d' % attempt)
    output.mkdir()
    identity = {'command': command, 'source_commit': subprocess.check_output(
        ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()}
    (output / 'request.json').write_text(json.dumps(identity, indent=2) + '\n')
    with (output / 'stdout.log').open('w') as stdout, (output / 'stderr.log').open('w') as stderr:
        result = subprocess.run(command, cwd=ROOT, stdout=stdout, stderr=stderr)
    shutil.copy2(ROOT / '.mylang-cache/verification-v2/last-run.json', output / 'last-run.json')
    print('Verification returncode', result.returncode, 'evidence', output, flush=True)
    raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()

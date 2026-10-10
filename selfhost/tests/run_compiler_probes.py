#!/usr/bin/env python3
"""Standalone qualification; invoke through scripts/build-slot.sh build."""
import argparse
import hashlib
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--builder', type=Path, default=ROOT / 'zig-out/tools/selka-components')
    parser.add_argument('--zig', default='zig')
    args = parser.parse_args()
    # The coordinator verifies the qualified receipt; accepting an arbitrary
    # --compiler would weaken this driver to development-compiler smoke tests.
    result = subprocess.run([str(args.builder.resolve()), '--root', str(ROOT),
                             '--zig', args.zig, '--seed-only'], cwd=ROOT,
                            check=True, text=True, stdout=subprocess.PIPE)
    seed = Path(result.stdout.strip())
    print('verified seed:', seed, flush=True)
    print('seed sha256:', hashlib.sha256(seed.read_bytes()).hexdigest(), flush=True)
    for release in (False, True):
        env = os.environ.copy()
        command = [str(seed), 'test', 'selfhost/probes/compiler/tests.my', '--force', '--no-cache']
        if release:
            command += ['--release', '--verify-facts']
            env['MYL_CORE_LEAKCHECK'] = '1'
        print('command:', ' '.join(command), flush=True)
        subprocess.run(command, cwd=ROOT, env=env, check=True)
    print('two qualification modes passed; no timing measurements performed')


if __name__ == '__main__':
    main()

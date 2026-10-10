#!/usr/bin/env python3
"""Compile controlled hash probes; invoke this driver through build-slot.sh."""
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
WORK = ROOT / '.mylang-cache/zig017-toolchain-20261009'
TOOLS = {
    'pinned': Path('/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig'),
    'custom': Path('/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b-eda-286f77f2-8f4af965/zig'),
    'release': Path('/home/epentland/zig-toolchains/0.17.0-download/zig-x86_64-linux-0.17.0/zig'),
}

def main():
    rows = []
    for label, tool in TOOLS.items():
        for mode in ['Debug', 'ReleaseSafe', 'ReleaseFast']:
            for cpu in ['native', 'baseline']:
                name = f'{label}-{mode}-{cpu}'
                out = WORK / 'hash' / name
                out.parent.mkdir(parents=True, exist_ok=True)
                cmd = [str(tool), 'build-exe', str(HERE / 'hash_probe.zig'), '-O' + mode,
                       '-mcpu=' + cpu, '-femit-bin=' + str(out),
                       '--cache-dir', str(WORK / 'hash-cache' / label),
                       '--global-cache-dir', '/home/epentland/ai/canopy/.zig-global-cache']
                with (out.parent / (name + '.build.log')).open('w') as log:
                    done = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT,
                                          env={**os.environ, 'TMPDIR': str(WORK / 'tmp')})
                rows.append({'name': name, 'command': cmd, 'exit': done.returncode})
                print(name, done.returncode, flush=True)
                (HERE / 'hash-builds.json').write_text(json.dumps(rows, indent=2) + '\n')

if __name__ == '__main__':
    main()

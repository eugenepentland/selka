#!/usr/bin/env python3
"""Build the normal and bounded LLVM O3 SVG guests, retaining build reports."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
WORK = ROOT / '.tmp/full-svg-benchmark-20260921'
FLAGS = {'mylang-o3': [], 'mylang-o3-lto': ['--lto'],
         'mylang-o3-bounded': ['--step-accounting']}


def commands():
    for name, extra in FLAGS.items():
        yield name, [str(ROOT / 'zig-out/bin/mylang'), 'build',
                     'src/schematic/guest/main.my', '--project', '--provider',
                     'src/schematic/native_schematic.c', '--backend', 'llvm',
                     '--llvm-opt', '3', *extra, '--keep-symbols', '--cache-dir',
                     str(WORK / (name + '-cache')), '--report', '-o', str(WORK / name)]


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    records = []
    for name, command in commands():
        with (OUT / (name + '-build.json')).open('w') as stdout, \
                (OUT / (name + '-build.stderr')).open('w') as stderr:
            subprocess.run(command, cwd=ROOT, stdout=stdout, stderr=stderr, check=True)
        records.append({'name': name, 'argv': command,
                        'sha256': hashlib.sha256((WORK / name).read_bytes()).hexdigest()})
    (OUT / 'mylang-build-commands.json').write_text(json.dumps(records, indent=2) + '\n')


if __name__ == '__main__':
    main()

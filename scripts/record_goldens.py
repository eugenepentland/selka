#!/usr/bin/env python3
"""Re-record the checked-in reference outcomes every native corpus driver compares against.

Run this only when a corpus gains cases or the language's observable behavior
changes on purpose; the recorded outcomes under ``tests/goldens`` are the
reference the native backend is held to.
"""
import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DRIVERS = ('qbe_parity', 'qbe_arena', 'qbe_bytes', 'qbe_io', 'qbe_managed',
           'qbe_text', 'qbe_files', 'qbe_native_cases', 'qbe_docs')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--qbe', default='qbe')
    parser.add_argument('--zig', default='zig')
    parser.add_argument('--only', action='append', default=[])
    arguments = parser.parse_args()
    failures = []
    for name in (arguments.only or DRIVERS):
        command = [sys.executable, str(ROOT / 'tests' / (name + '.py')), '--record',
                   '--compiler', str(arguments.compiler.resolve()),
                   '--qbe', str(arguments.qbe), '--zig', str(arguments.zig)]
        print('recording', name, flush=True)
        result = subprocess.run(command, cwd=ROOT)
        if result.returncode != 0:
            failures.append(name)
    if failures:
        print('failed to record:', ', '.join(failures), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())

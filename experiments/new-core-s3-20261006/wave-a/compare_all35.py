#!/usr/bin/env python3
"""Capture/compare every S0/S1/S2 row's full emitted definitions against 92590700.

No timing claim: exact function definitions prove the existing benchmark work
unchanged. Declarations are excluded. Run compilation through a build slot.
"""
import argparse
import difflib
import importlib.util
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capture', action='store_true')
    parser.add_argument('--core', type=Path, default=ROOT / 'zig-out/bin/mylang-core')
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('rows', ROOT / 'experiments/new-core-s2-20261005/wave-b/integration/measure_all35.py')
    rows = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(rows)
    area = ROOT / '.mylang-cache/s3' / ('baseline' if args.capture else 'identity')
    area.mkdir(parents=True, exist_ok=True)
    different = []
    for row in rows.UNITS:
        stem = rows.stem(row)
        llvm = area / f'{stem}.ll'
        command = [str(args.core.resolve()), 'build', str(ROOT / f'test/core/{stem}.my'),
                   '-o', str(area / stem), '--release', '--emit-llvm', str(llvm),
                   '--cache-dir', str(area / 'runtime'), '--link', str(ROOT / 'benchmarks/runtime/ports/native_clock.c')]
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode:
            raise SystemExit(f'{row}: build status {result.returncode}: {result.stdout}{result.stderr}')
        if args.capture:
            print(f'{row}: captured 92590700 definitions', flush=True)
            continue
        before = (ROOT / '.mylang-cache/s3/baseline' / llvm.name).read_text()
        after = llvm.read_text()
        before = '\n'.join(re.findall(r'^define .*?^\}', before, re.M | re.S))
        after = '\n'.join(re.findall(r'^define .*?^\}', after, re.M | re.S))
        if before != after:
            different.append(row)
            (area / f'{stem}.diff').write_text(''.join(difflib.unified_diff(before.splitlines(True), after.splitlines(True), fromfile='92590700', tofile='S3-Wave-A')))
        print(f'{row}: {"changed" if before != after else "identical definitions"}', flush=True)
    print(f'35 rows; {len(different)} changed definitions', flush=True)
    return int(bool(different))


if __name__ == '__main__':
    raise SystemExit(main())

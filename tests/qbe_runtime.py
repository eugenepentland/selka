#!/usr/bin/env python3
"""Check QBE scalar runtime boundary behavior and failures under UBSan."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FAILURES = {
    'overflow': 'R_OVERFLOW',
    'unsigned-overflow': 'R_OVERFLOW',
    'division': 'R_DIVISION_BY_ZERO',
    'division-overflow': 'R_OVERFLOW',
    'cast': 'R_OVERFLOW',
    'shift': 'R_INVALID_SHIFT',
    'float-cast': 'R_FLOAT_CONVERSION',
    'frames': 'R_FRAME_LIMIT',
    'steps': 'R_STEP_LIMIT',
}


def run(command):
    return subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=120)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--zig', default='zig')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='mylang-qbe-runtime-') as directory:
        executable = Path(directory) / 'runtime'
        for optimization in ('-O0', '-O2'):
            compiled = run([args.zig, 'cc', '-std=c11', '-Wall', '-Wextra', '-Werror',
                            optimization, '-fsanitize=undefined', '-fno-sanitize-recover=all',
                            '-I', ROOT / 'src', ROOT / 'src/qbe_runtime.c', ROOT / 'src/qbe_stack.c', ROOT / 'src/native_heap.c',
                            ROOT / 'tests/qbe_runtime.c', '-lm', '-o', executable])
            assert compiled.returncode == 0, compiled.stderr
            regions = Path(directory) / 'regions'
            checked = run([args.zig, 'cc', '-std=c11', '-Wall', '-Wextra', '-Werror',
                           optimization, '-fsanitize=undefined', '-fno-sanitize-recover=all',
                           '-I', ROOT / 'src',
                           *[ROOT / 'src' / name for name in ('qbe_runtime.c', 'qbe_stack.c', 'qbe_regions.c', 'native_heap.c',
                             'native_collections.c', 'native_owned.c', 'native_pool.c')],
                           ROOT / 'tests/qbe_regions.c', '-lm', '-o', regions])
            assert checked.returncode == 0, checked.stderr
            checked = run([regions])
            assert checked.returncode == 0 and not checked.stderr, checked
            providers = Path(directory) / 'providers'
            checked = run([args.zig, 'cc', '-std=c11', '-Wall', '-Wextra', '-Werror',
                           optimization, '-fsanitize=undefined', '-fno-sanitize-recover=all',
                           '-I', ROOT / 'src',
                           *[ROOT / 'src' / name for name in ('qbe_runtime.c', 'qbe_stack.c', 'qbe_providers.c',
                             'qbe_resources.c', 'native_heap.c')],
                           ROOT / 'tests/qbe_providers.c', '-lm', '-o', providers])
            assert checked.returncode == 0, checked.stderr
            checked = run([providers])
            assert checked.returncode == 0 and not checked.stderr, checked
            succeeded = run([executable])
            assert succeeded.returncode == 0 and not succeeded.stderr, succeeded
            for argument, code in FAILURES.items():
                failed = run([executable, argument])
                assert failed.returncode == 1 and failed.stderr == f'{code}: QBE runtime failure\n', (argument, failed)
    print(f'QBE runtime boundary checks and {len(FAILURES)} trap cases passed (O0/O2, UBSan)')


if __name__ == '__main__':
    main()

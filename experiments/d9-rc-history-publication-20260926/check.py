#!/usr/bin/env python3
"""Exercise semantic publication and the existing physical runtime contracts."""
import concurrent.futures
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import test_native_memory


def main():
    directory = ROOT / '.tmp-rc' / 'history-publication-check'
    directory.mkdir(parents=True, exist_ok=True)
    flags = ['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-fsanitize=address',
             '-fsanitize=undefined', '-ffunction-sections', '-fdata-sections', '-Wl,--gc-sections']
    selected = {'native_rc_contract', 'native_rc_collections', 'native_rc_arena',
                'native_rc_hold', 'native_rc_loan', 'native_rc_history'}
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        jobs = [pool.submit(test_native_memory.run_suite, ROOT, flags, directory, name, list(sources))
                for name, sources in test_native_memory.SUITES if name in selected]
        for job in jobs:
            job.result()
    test_native_memory.run_suite(ROOT, flags + ['-DMYL_NATIVE_RC=1'], directory, 'qbe_runtime_rc',
                                ['native_heap.c', 'native_regions.c', 'qbe_runtime_rc.c'])


if __name__ == '__main__':
    main()

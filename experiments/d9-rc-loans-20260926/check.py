#!/usr/bin/env python3
"""Run private-loan and production frame cleanup under ASan and UBSan."""
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import test_native_memory


def main():
    directory = ROOT / '.tmp-rc' / 'loan-check'
    directory.mkdir(parents=True, exist_ok=True)
    flags = ['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-fsanitize=address',
             '-fsanitize=undefined', '-ffunction-sections', '-fdata-sections', '-Wl,--gc-sections']
    runs = []
    original = subprocess.run

    def recorded(command, **kwargs):
        result = original(command, **kwargs)
        runs.append({'command': command, 'status': result.returncode})
        return result

    subprocess.run = recorded
    test_native_memory.run_suite(ROOT, flags, directory, 'native_rc_loan', ['native_heap.c', 'native_regions.c'])
    test_native_memory.run_suite(ROOT, flags + ['-DMYL_NATIVE_RC=1'], directory, 'qbe_runtime_rc',
                                ['native_heap.c', 'native_regions.c', 'qbe_runtime_rc.c'])
    (directory / 'commands.json').write_text(json.dumps(runs, indent=2))


if __name__ == '__main__':
    main()

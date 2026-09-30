#!/usr/bin/env python3
"""Replay the scoped registered release and adjacent native UBSan suites."""
import argparse
import importlib.util
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[4]
    spec = importlib.util.spec_from_file_location('native_tests', root / 'scripts/test_native_memory.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    args.out.mkdir(parents=True, exist_ok=True)
    flags = ['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-fsanitize=undefined',
             '-ffunction-sections', '-fdata-sections', '-Wl,--gc-sections']
    selected = ('native_rc_registered_release', 'native_rc_collections', 'native_rc_image', 'native_rc_contract')
    for suite, sources in module.SUITES:
        if suite in selected:
            module.run_suite(root, flags, args.out.resolve(), suite, list(sources))


if __name__ == '__main__':
    main()

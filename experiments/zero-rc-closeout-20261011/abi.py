#!/usr/bin/env python3
"""Repeat the ABI proof without changing the frozen Stage 6 evidence."""
import importlib.util
from pathlib import Path
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('previous_abi', HERE.parent / 'zero-rc-final-20261011/abi.py')
previous = importlib.util.module_from_spec(spec)
spec.loader.exec_module(previous)
previous.HERE = HERE

if __name__ == '__main__':
    previous.main()

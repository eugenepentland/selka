#!/usr/bin/env python3
"""Run focused text/join C suites with exact-payload ASan/UBSan checks."""
import concurrent.futures
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts import test_native_memory

flags = ['cc', '-std=c11', '-O3', '-Wall', '-Wextra', '-Werror',
         '-fsanitize=address,undefined', '-ffunction-sections', '-fdata-sections',
         '-Wl,--gc-sections']
chosen = {'native_text_methods', 'native_text_views', 'native_text_index',
          'native_text_dictionary', 'native_rc_collections'}
with tempfile.TemporaryDirectory() as directory:
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        tasks = [pool.submit(test_native_memory.run_suite, ROOT, flags,
                             Path(directory), name, list(sources))
                 for name, sources in test_native_memory.SUITES if name in chosen]
        for task in tasks:
            task.result()
print('Five native join/text suites passed under ASan + UBSan at -O3.')

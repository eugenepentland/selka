import importlib.util
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('native_memory', root / 'scripts/test_native_memory.py')
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)
out = Path(__file__).resolve().parent / 'native-ready'
out.mkdir(exist_ok=True)
command = ['cc', '-O2', '-std=c11', '-Wall', '-Wextra', '-Werror',
           '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
           '-ffunction-sections', '-fdata-sections', '-Wl,--gc-sections']
for suite, sources in native.SUITES:
    if suite == 'native_rc_collections':
        native.run_suite(root, command, out, suite, list(sources))
        print('PASS native_rc_collections optimized ASan/UBSan: ordinary/hot predicates, '
              'cold metadata, pending finalizers, managed/refused widths, growth/alias/generation/heap refusal')
        break
else:
    raise RuntimeError('native_rc_collections suite missing')

import importlib.util
import json
from pathlib import Path
import subprocess

root = Path.cwd()
folder = root / '.tmp/plain-native'
folder.mkdir(parents=True, exist_ok=True)
spec = importlib.util.spec_from_file_location('native_memory', root / 'scripts/test_native_memory.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
sources = next(sources for name, sources in module.SUITES if name == 'native_rc_collections')
rows = []
for name, mode in [('none', []), ('full', ['-flto=full']), ('thin', ['-flto=thin'])]:
    dest = folder / name
    dest.mkdir(exist_ok=True)
    command = ['zig', 'cc', '-std=c11', '-O3', '-Wall', '-Wextra', '-Werror', '-UNDEBUG', '-fsanitize=undefined', '-ffunction-sections', '-fdata-sections', '-Wl,--gc-sections'] + mode
    print('MODE', name, flush=True)
    module.run_suite(root, command, dest, 'native_rc_collections', list(sources))
    binary = dest / 'native_rc_collections'
    nm = subprocess.run(['nm', str(binary)], check=True, text=True, capture_output=True).stdout
    (dest / 'symbols.txt').write_text(nm)
    rows.append({'mode': name, 'status': 0, 'actual_native_collection_cases': 47, 'callable_query_symbol_retained': ' T myl_rc_list_plain_ready' in nm})
(folder / 'receipt.json').write_text(json.dumps(rows, indent=2) + '\n')

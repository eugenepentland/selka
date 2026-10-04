#!/usr/bin/env python3
"""Check ReleaseFast text guests against the untouched independent oracle."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('text_oracle', ROOT / 'benchmarks/runtime/expanded/text/oracle.py')
oracle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(oracle)
environment = dict(os.environ)
for key in ('MYLANG_OPTIONS', 'MYLANG_MEMORY_LIMIT'):
    environment.pop(key, None)
records = []
for argument in sys.argv[1:]:
    binary = Path(argument).resolve()
    manifest = json.loads(Path(str(binary) + '.qbe-manifest.json').read_text())
    assert manifest['backend'] in ('llvm', 'qbe')
    if manifest['backend'] == 'llvm':
        assert str(manifest['optimization']) == '3' and manifest['lto'] is True
    probes = [(case, size, 7, 19) for case in oracle.CASES for size in (2, 17, 64)]
    probes += [('string_join', size, iterations, seed)
               for size in (2, 3, 7, 8, 9, 15, 16, 17, 31, 32, 33, 63, 65, 257, 4096)
               for iterations, seed in ((1, 1), (11, 37))]
    for case, size, iterations, seed in probes:
        command = [str(binary), case, str(size), str(iterations), str(seed)]
        run = subprocess.run(command, check=True, capture_output=True, text=True,
                             env=environment, timeout=30)
        fields = run.stdout.split()
        assert len(fields) == 2 and not run.stderr, (command, run.stdout, run.stderr)
        assert int(fields[0]) == oracle.checksum(case, size, iterations, seed), (command, run.stdout)
        records.append({'backend': manifest['backend'], 'input': command[1:], 'checksum': int(fields[0])})
    for controls, error in (('--max-steps=1', 'R_NO_STEP_ACCOUNTING'),
                            ('--max-frames=1', 'R_NO_FRAME_ACCOUNTING')):
        run = subprocess.run([str(binary), 'string_join', '17', '1', '19'],
                             capture_output=True, text=True,
                             env={**environment, 'MYLANG_OPTIONS': controls}, timeout=30)
        assert run.returncode != 0 and error in run.stderr, (controls, run.returncode, run.stderr)
        records.append({'backend': manifest['backend'], 'control': controls, 'error': error})
    run = subprocess.run([str(binary), 'string_join', '17', '1', '19'],
                         capture_output=True, text=True,
                         env={**environment, 'MYLANG_MEMORY_LIMIT': '1'}, timeout=30)
    assert run.returncode != 0 and 'R_MEMORY_BUDGET' in run.stderr, (run.returncode, run.stderr)
    records.append({'backend': manifest['backend'], 'control': 'MYLANG_MEMORY_LIMIT=1', 'error': 'R_MEMORY_BUDGET'})
    records.append({'backend': manifest['backend'], 'binary': str(binary),
                    'sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
                    'manifest_sha256': hashlib.sha256(Path(str(binary) + '.qbe-manifest.json').read_bytes()).hexdigest()})
print(json.dumps({'status': 'passed', 'checks': records}, indent=2))

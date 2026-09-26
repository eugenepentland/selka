#!/usr/bin/env python3
"""Replay file goldens and targeted trapping/Result opens with actual RC backends."""
import base64
import concurrent.futures
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('goldens', ROOT / 'experiments/d9-rc-golden-replay-20260926/run.py')
goldens = importlib.util.module_from_spec(spec)
spec.loader.exec_module(goldens)
compiler = Path(sys.argv[1]).resolve()
work = Path(sys.argv[2]).resolve()
(work / 'tmp').mkdir(parents=True, exist_ok=True)
cases = [] if any(flag in sys.argv[3:] for flag in ('--targets-only', '--gc-only', '--result-only')) else [case for case in goldens.cases()[0] if case['id'].startswith('qbe_files/')]
results = {'compiler': str(compiler), 'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(), 'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(), 'goldens': {}, 'targeted': {}}
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    pending = [pool.submit(goldens.execute, compiler, work, backend, case) for backend in ('qbe', 'llvm') for case in cases]
    for future in concurrent.futures.as_completed(pending):
        key, outcome = future.result()
        # Admission diagnostics may precede the CLI's leading mylang: error.
        # Preserve raw stderr; only remove harness scheduling noise for matching.
        normalized = b"\n".join(line.encode() for line in outcome['stderr'].splitlines() if not line.startswith('build-slot:'))
        actual = goldens.signature(outcome['actual']['status'], base64.b64decode(outcome['actual']['stdout_b64']), normalized)
        expected = outcome['expected']
        field = 'code' if expected['failed'] or actual['failed'] else 'stdout_b64'
        outcome['actual'] = actual
        outcome['matched'] = expected['status'] == actual['status'] and expected['failed'] == actual['failed'] and expected[field] == actual[field]
        results['goldens'][key] = outcome
        print(key, outcome['matched'], outcome['balanced'], flush=True)

sources = {'heap': 'def main(fs: Filesystem) -> int:\n    with open(fs, "absent.txt", "r") as file:\n        return len(file.read())\n', 'arena': 'def main(fs: Filesystem) -> int:\n    with arena():\n        with open(fs, "absent.txt", "r") as file:\n            return len(file.read())\n', 'result': 'def first(fs: Filesystem) -> Result[int, str]:\n    with open(fs, "absent.txt", "r")? as file:\n        return Ok(len(file.read()))\ndef main(fs: Filesystem) -> int:\n    match first(fs):\n        case Ok(value):\n            return 10\n        case Err(message):\n            if message == "open \'absent.txt\': failed: the path does not exist or could not be used":\n                return 0\n            return 11\n'}
if '--result-only' in sys.argv[3:]:
    sources = {'result': sources['result']}
for name, source in sources.items():
    path = work / (name + '.my')
    path.write_text(source)
    for backend in ('qbe', 'llvm'):
        for runtime in (('gc-v1',) if '--gc-only' in sys.argv[3:] else ('rc-v2-counting', 'gc-v1')):
            cmd = [str(ROOT / 'scripts/build-slot.sh'), 'build', str(compiler), 'run', str(path), '--print-result', '--cache-dir=' + str(work / ('target-cache-' + backend))]
            if backend == 'llvm':
                cmd.append('--release')
            run = subprocess.run(cmd, cwd=work, env=dict(os.environ, MYLANG_RUNTIME=runtime, TMPDIR=str(work / 'tmp')), capture_output=True, text=True, timeout=600)
            counts = [json.loads(line.split(' ', 1)[1]) for line in run.stderr.splitlines() if line.startswith('MYLANG_RC_COUNTS ')]
            correct = run.returncode == (0 if name == 'result' else 1) and ('R_FILE' in run.stderr if name != 'result' else run.stdout == '0\n')
            balanced = all(c['heap_allocate'] == c['retire'] and c['owner_release'] == c['heap_allocate'] + c['owner_acquire'] and c['hold_acquire'] == c['hold_release'] and not c['saturated'] for c in counts)
            key = '/'.join((name, backend, runtime))
            results['targeted'][key] = {'command': cmd, 'status': run.returncode, 'stdout': run.stdout, 'stderr': run.stderr, 'counts': counts, 'correct': correct, 'balanced': balanced}
            print(key, correct, balanced, flush=True)
with gzip.open(work / 'results.json.gz', 'wt') as file:
    json.dump(results, file, indent=2)
assert all(r['matched'] and r['balanced'] and (r['counters'] or r['expected']['status'] == 2) for r in results['goldens'].values())
assert all(r['correct'] and r['balanced'] for r in results['targeted'].values())
assert all(r['counts'] for k, r in results['targeted'].items() if k.endswith('rc-v2-counting'))

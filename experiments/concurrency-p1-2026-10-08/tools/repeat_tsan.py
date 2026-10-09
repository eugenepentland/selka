#!/usr/bin/env python3
"""Run P1's exported native and emitted-IR TSan programs 100 times at eight threads.

Build/export the tests through build-slot with MYLANG_P1_FIXTURE_OUTPUT first.
This runner never builds or changes samples. Every outcome, including failures,
is retained; a failed repetition terminates the gate without automatic retries.
"""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binaries', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    args = parser.parse_args()
    root = Path.cwd()
    args.evidence.mkdir(parents=True, exist_ok=False)
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    dirty = subprocess.check_output(['git', 'diff', 'HEAD', '--', 'src/core'], text=True)
    if dirty:
        raise RuntimeError('commit the tested implementation before the repetition gate')
    allowed = sorted(os.sched_getaffinity(0) - {2, 3, 10, 11})
    os.sched_setaffinity(0, allowed)
    environment = dict(os.environ, MYLANG_THREADS='8', MYLANG_CORE_SANITIZE='thread',
                       MYL_CORE_LEAKCHECK='1', TSAN_OPTIONS='halt_on_error=1', TMPDIR=str(root / '.tmp'))
    expected = {'captures': '4\n' + '3 keyé 60\n' * 8,
                'ranges': ''.join(f'{i}\n' for i in range(100, 132)),
                'native-tasks': 'tasks: 1010000 submits, binary depth 12, chain 2048, threads 8, live 0\n'}
    binaries = {name: (args.binaries / name).resolve() for name in expected}
    metadata = {'source': source, 'threads': 8, 'repetitions': 100, 'cpus': allowed,
                'tsan_options': environment['TSAN_OPTIONS'], 'binaries': {}, 'complete': False}
    for name, binary in binaries.items():
        symbols = subprocess.check_output(['nm', str(binary)], text=True)
        if '__tsan_func_entry' not in symbols:
            raise RuntimeError(f'{name}: instrumentation symbols missing')
        metadata['binaries'][name] = {'path': str(binary), 'sha256': hashlib.sha256(binary.read_bytes()).hexdigest()}
    manifest = args.evidence / 'summary.json'
    manifest.write_text(json.dumps(metadata, indent=2) + '\n')
    started = time.monotonic()
    completed = 0
    with gzip.open(args.evidence / 'repetitions.jsonl.gz', 'wt', encoding='utf-8') as log:
        for repetition in range(1, 101):
            for name, binary in binaries.items():
                argv = [str(binary)] + (['stress'] if name == 'native-tasks' else [])
                start = time.monotonic()
                try:
                    run = subprocess.run(argv, env=environment, capture_output=True, timeout=120)
                    result = {'name': name, 'repetition': repetition, 'seconds': time.monotonic() - start,
                              'status': run.returncode, 'stdout': run.stdout.decode(errors='replace'),
                              'stderr': run.stderr.decode(errors='replace')}
                except subprocess.TimeoutExpired as error:
                    result = {'name': name, 'repetition': repetition, 'seconds': time.monotonic() - start,
                              'status': 'timeout', 'stdout': (error.stdout or b'').decode(errors='replace'),
                              'stderr': (error.stderr or b'').decode(errors='replace')}
                result['pass'] = result['status'] == 0 and result['stdout'] == expected[name] and not result['stderr']
                log.write(json.dumps(result) + '\n');log.flush()
                if not result['pass']:
                    metadata['failure'] = result;metadata['completed_processes'] = completed
                    manifest.write_text(json.dumps(metadata, indent=2) + '\n')
                    raise RuntimeError(f'{name} repetition {repetition} failed; see {manifest}')
                completed += 1
            if repetition % 10 == 0:
                print(f'{repetition}/100 repetitions: all three programs green', flush=True)
    metadata.update(complete=True, completed_processes=completed, seconds=time.monotonic() - started)
    manifest.write_text(json.dumps(metadata, indent=2) + '\n')


if __name__ == '__main__':
    main()

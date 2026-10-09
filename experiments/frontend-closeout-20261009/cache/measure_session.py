#!/usr/bin/env python3
"""Capture cold and relocated session work, with exact compiler/source identities."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('compiler', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
compiler = args.compiler.resolve()
source_path = Path(__file__).resolve().parent / 'baseline_nominal.my'
source = source_path.read_text().removeprefix('# relocated\n')
process = subprocess.Popen([str(compiler), 'check-session', str(source_path)],
                           stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, text=True)
requests = []
try:
    for text in (source, '# relocated\n' + source):
        source_path.write_text(text)
        start = time.monotonic()
        process.stdin.write('check\n')
        process.stdin.flush()
        line = process.stdout.readline()
        if not line:
            raise RuntimeError(process.stderr.read())
        requests.append({'elapsed_seconds': time.monotonic() - start,
                         'source_sha256': hashlib.sha256(text.encode()).hexdigest(),
                         'response': json.loads(line)})
    process.stdin.write('quit\n')
    process.stdin.flush()
    stdout, stderr = process.communicate(timeout=30)
    if process.returncode:
        raise RuntimeError(f'{process.returncode}: {stderr}')
    args.output.write_text(json.dumps({
        'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
        'contention': 'Shared machine; wall time is observational, no speedup claim.',
        'requests': requests, 'quit_stdout': stdout, 'stderr': stderr}, indent=2) + '\n')
finally:
    source_path.write_text('# relocated\n' + source)
    if process.poll() is None:
        process.kill()
        process.wait()

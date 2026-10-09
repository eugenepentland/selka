#!/usr/bin/env python3
"""Preserve command results, timing context and exact inputs; never overwrite."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def capture(command, destination, *, cwd, inputs=(), environment=None, timeout=300):
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    receipt = destination.with_suffix('.json')
    if receipt.exists():
        raise FileExistsError(receipt)
    paths = [Path(path).resolve() for path in inputs]
    hashes = {str(path): digest(path) for path in paths}
    processes = subprocess.run(['ps', '-eo', 'pid,etimes,args'], capture_output=True,
                               text=True, check=True).stdout
    heavy = [line for line in processes.splitlines()
             if any(term in line for term in ('zig build', 'zig cc', 'fuzz_matrix.py', 'bench-newcore'))]
    started = datetime.now(timezone.utc).isoformat()
    start = time.monotonic()
    try:
        result = subprocess.run(command, cwd=cwd, env=environment, capture_output=True, timeout=timeout)
        status, stdout, stderr = result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired as error:
        status = 124
        stdout, stderr = error.stdout or b'', (error.stderr or b'') + b'\ncloseout timeout\n'
    elapsed = time.monotonic() - start
    destination.with_suffix('.stdout').write_bytes(stdout)
    destination.with_suffix('.stderr').write_bytes(stderr)
    after = {str(path): digest(path) for path in paths}
    record = {'argv': [str(arg) for arg in command], 'cwd': str(cwd), 'started_at': started,
              'elapsed_seconds': elapsed, 'returncode': status,
              'cpu_affinity': sorted(os.sched_getaffinity(0)), 'other_heavy_processes': heavy,
              'inputs_sha256': hashes, 'inputs_unchanged': hashes == after,
              'stdout_sha256': hashlib.sha256(stdout).hexdigest(),
              'stderr_sha256': hashlib.sha256(stderr).hexdigest(),
              'timing_claim': 'Shared-machine observation; not an uncontended speed measurement.'}
    receipt.write_text(json.dumps(record, indent=2) + '\n')
    if hashes != after:
        raise RuntimeError('inputs changed during capture')
    return record, stdout, stderr

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--input', type=Path, action='append', default=[])
    parser.add_argument('--cwd', type=Path, default=Path.cwd())
    parser.add_argument('--timeout', type=int, default=300)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('command required')
    record, stdout, stderr = capture(command, args.output, cwd=args.cwd,
                                     inputs=args.input, timeout=args.timeout)
    print(json.dumps(record, indent=2))
    raise SystemExit(record['returncode'])

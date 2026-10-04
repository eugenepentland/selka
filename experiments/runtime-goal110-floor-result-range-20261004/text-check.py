#!/usr/bin/env python3
"""Untimed frozen text oracles; preserve complete streams and elapsed clock values."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/expanded'))
from registry import checksum, inventory

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--before', type=Path, required=True)
parser.add_argument('--after', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
report = {'kind': 'untimed-frozen-text-floor-range-checks', 'status': 'running', 'records': [],
          'runner_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
          'binaries': {label: {'path': str(path.resolve()), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
                       for label, path in (('before', args.before), ('after', args.after))},
          'clock_note': 'Each process invokes the frozen clock, but these executions are correctness qualification, not timing evidence.'}
try:
    for case, meta in inventory().items():
        if meta['group'] != 'text':
            continue
        dimensions = [(2, 1, 1), (3, 42, 7), (17, 999983, 31)]
        dimensions += [(size, 42, 7) for size in meta['sizes']]
        dimensions += [(5, 2, 2), (16, 31, 9), (65, 42, 17), (128, 999999, 3), (257, 1000000, 1)]
        for size, seed, iterations in dimensions:
            expected = checksum(case, size, iterations, seed)
            for label, binary in (('before', args.before), ('after', args.after)):
                command = [str(binary.resolve()), case, str(size), str(iterations), str(seed)]
                env = {key: value for key, value in os.environ.items()
                       if key not in ('MYLANG_OPTIONS', 'MYLANG_MEMORY_LIMIT', 'MYLANG_RUNTIME')}
                done = subprocess.run(command, env=env, cwd=ROOT, capture_output=True, text=True, timeout=60)
                record = {'arm': label, 'case': case, 'size': size, 'seed': seed, 'iterations': iterations,
                          'oracle': expected, 'command': command, 'status': done.returncode,
                          'stdout': done.stdout, 'stderr': done.stderr}
                report['records'].append(record)
                assert done.returncode == 0 and done.stderr == '', record
                match = re.fullmatch(r'([0-9]+) ([0-9]+)\n', done.stdout)
                assert match and int(match[1]) == expected and int(match[2]) > 0, record
    report['status'] = 'passed'
finally:
    args.output.parent.mkdir(parents=True, exist_ok=True)
    report['execution_count'] = len(report['records'])
    args.output.write_text(json.dumps(report, indent=2) + '\n')
print(f"PASS {report['execution_count']} frozen text records")

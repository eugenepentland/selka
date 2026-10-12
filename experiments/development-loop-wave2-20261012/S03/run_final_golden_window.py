#!/usr/bin/env python3
"""One bounded, order-balanced final-compiler golden comparison window."""
from pathlib import Path
import hashlib
import signal
import subprocess
import sys

root = Path(__file__).resolve().parent
harness = root / 'measure_final_goldens.py'
assert hashlib.sha256(harness.read_bytes()).hexdigest() == 'bd0a640eef76263f47b82497759cc49c76c1d5a8820b07a2d8bb7bd571b1aea7'
child = None

def interrupted(signum, frame):
    if child is not None and child.poll() is None:
        child.terminate()
        try:
            child.wait(timeout=10)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()
    raise SystemExit(128 + signum)

signal.signal(signal.SIGTERM, interrupted)
for sample, labels in ((0, ('C0', 'B0')), (1, ('B0', 'C0'))):
    for label in labels:
        command = [sys.executable, str(harness), 'timing', '--label', label,
                   '--sample', str(sample), '--tier', 'warm', '--timeout', '60']
        print(command, flush=True)
        child = subprocess.Popen(command)
        status = child.wait()
        assert status == 0, (sample, label, status)
print('Two complete matched golden pairs; descriptive only, no p95.', flush=True)

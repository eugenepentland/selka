#!/usr/bin/env python3
"""Measure a prebuilt S06 fixture inside an existing exclusive admission window."""
import hashlib
import json
from pathlib import Path
import statistics
import re
import subprocess
import sys
import time

binary = Path(sys.argv[1]).resolve()
expected = sys.argv[2]
output = Path(sys.argv[3]).resolve()
if hashlib.file_digest(binary.open('rb'), 'sha256').hexdigest() != expected:
    raise SystemExit('fixture hash differs before measurement')
output.mkdir(parents=True, exist_ok=True)
records = []
for index in range(20):
    started = time.monotonic_ns()
    result = subprocess.run([str(binary)], capture_output=True, timeout=10)
    elapsed = time.monotonic_ns() - started
    raw = result.stdout + result.stderr
    (output / ('sample-%02d.log' % index)).write_bytes(raw)
    good = result.returncode == 0 and b'All 1 tests passed.' in raw and raw.count(b'S06') >= 4
    rows = [{name: int(value) for name, value in re.findall(r'([a-z_]+)=(\d+)', line)}
            for line in raw.decode('utf-8', 'replace').splitlines() if 'S06 ' in line and 'old_ns=' in line]
    records.append({'index': index, 'status': result.returncode, 'elapsed_ns': elapsed, 'checks_pass': good, 'rows': rows})
    if not good:
        break
if hashlib.file_digest(binary.open('rb'), 'sha256').hexdigest() != expected:
    raise SystemExit('fixture changed during measurement')
values = sorted(record['elapsed_ns'] for record in records)
report = {'binary': str(binary), 'sha256': expected, 'samples': records,
          'median_ns': statistics.median(values), 'empirical_p95_ns': values[(95*len(values)+99)//100-1],
          'qualification': '20 operational fixture repeats; empirical p95 only, no stable p95 or whole guest-loop claim',
          'complete': len(records)==20 and all(record['checks_pass'] for record in records)}
(output / 'report.json').write_text(json.dumps(report, indent=2)+'\n')
raise SystemExit(0 if report['complete'] else 1)

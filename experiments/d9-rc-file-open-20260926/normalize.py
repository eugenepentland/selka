#!/usr/bin/env python3
"""Preserve rejected harness evidence and join the corrected GC-only rerun."""
import base64
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('goldens', root / 'experiments/d9-rc-golden-replay-20260926/run.py')
goldens = importlib.util.module_from_spec(spec)
spec.loader.exec_module(goldens)
with gzip.open(sys.argv[1], 'rt') as file:
    result = json.load(file)
with gzip.open(sys.argv[2], 'rt') as file:
    corrected = json.load(file)
with gzip.open(sys.argv[3], 'rt') as file:
    result_source_fixed = json.load(file)
assert result['compiler_sha256'] == corrected['compiler_sha256'] == result_source_fixed['compiler_sha256']
changes = []
for key, outcome in result['goldens'].items():
    normalized = b'\n'.join(line.encode() for line in outcome['stderr'].splitlines() if not line.startswith('build-slot:'))
    actual = goldens.signature(outcome['actual']['status'], base64.b64decode(outcome['actual']['stdout_b64']), normalized)
    if actual != outcome['actual']:
        outcome['unfiltered_classification'] = outcome['actual']
        changes.append(key)
    outcome['actual'] = actual
    expected = outcome['expected']
    field = 'code' if expected['failed'] or actual['failed'] else 'stdout_b64'
    outcome['matched'] = expected['status'] == actual['status'] and expected['failed'] == actual['failed'] and expected[field] == actual[field]
rejected = [key for key in result['targeted'] if key.endswith('/gc')]
assert len(rejected) == 6
result['targeted'] = {key: value for key, value in result['targeted'].items() if key not in rejected}
result['targeted'].update(corrected['targeted'])
result['targeted'].update(result_source_fixed['targeted'])
result['evidence_correction'] = {'scheduling_prefix_classifications': changes, 'invalid_gc_selector_attempts_retained_in_raw': rejected, 'gc_rerun': str(sys.argv[2]), 'result_source_rerun': str(sys.argv[3]), 'invalid_result_source': 'initial fixture used unsupported int(bool); preserved in raw attempts, corrected to an if before execution', 'production_source_sha256': hashlib.sha256((root / 'src/qbe_files.zig').read_bytes()).hexdigest()}
assert len(result['goldens']) == 56 and len(result['targeted']) == 12
assert all(r['matched'] and r['balanced'] and (r['counters'] or r['expected']['status'] == 2) for r in result['goldens'].values())
assert all(r['correct'] and r['balanced'] for r in result['targeted'].values())
assert all(r['counts'] for k, r in result['targeted'].items() if k.endswith('rc-v2-counting'))
with gzip.open(sys.argv[4], 'wt') as file:
    json.dump(result, file, indent=2)
print('56 golden outcomes and 12 targeted outcomes verified; all executed RC cases balanced')

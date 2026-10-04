#!/usr/bin/env python3
"""Verify immutable G4 archive bytes and their retained original files."""
import gzip
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[2]
archive = root / 'experiments/runtime-goal110-g4-rf-20261004'
receipt = archive / 'evidence.json'
data = json.loads(receipt.read_text())
sha = lambda value: hashlib.sha256(value).hexdigest()
assert len(data['archive_bindings']) == 47
assert len(data['script_bindings']) == 3
for item in data['archive_bindings']:
    stored = (archive / item['archive']).read_bytes()
    assert sha(stored) == item['archive_sha256']
    raw = gzip.decompress(stored) if item['archive'].endswith('.gz') else stored
    assert len(raw) == item['bytes'] and sha(raw) == item['raw_sha256']
    assert raw == Path(item['raw']).read_bytes()
for name, digest in data['script_bindings'].items():
    assert sha((archive / name).read_bytes()) == digest
result = dict(status='passed', archive_bindings=47, script_bindings=3,
              evidence_sha256=sha(receipt.read_bytes()), script_sha256=sha(Path(__file__).read_bytes()),
              limit='Read-only byte verification; no guest executions or new timings.')
output = root / 'benchmarks/runtime/candidates/goal110-g4-6cf7bdce-rf-20261004-archive-review.json'
assert not output.exists()
output.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result))

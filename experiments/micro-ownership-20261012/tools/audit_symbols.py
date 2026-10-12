#!/usr/bin/env python3
"""Inventory known legacy core RC symbols without classifying every drop as RC."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]
EVIDENCE = ROOT / 'experiments/micro-ownership-20261012'
entries = json.loads((EVIDENCE / 'parity/handoff.json').read_text())
entries += json.loads((EVIDENCE / 'expanded/manifest.json').read_text())['entries']
pattern = re.compile(r'\bmyl_core_(?:retain|release)(?:\w*)\b')
rows = []
for entry in entries:
    if not entry['arm'].startswith('mylang-') or not entry.get('binary'):
        continue
    binary = Path(entry['binary'])
    assert hashlib.sha256(binary.read_bytes()).hexdigest() == entry['sha256']
    result = subprocess.run(['nm', '--defined-only', str(binary)], capture_output=True, text=True, check=True)
    symbols = result.stdout.splitlines()
    matches = sorted({m[0] for m in pattern.finditer(result.stdout)})
    rows.append({'case_or_group': entry.get('case', entry.get('group')), 'arm': entry['arm'],
                 'kind': entry['kind'], 'binary': str(binary), 'sha256': entry['sha256'],
                 'defined_symbol_count': len(symbols), 'known_core_rc_symbols': matches,
                 'stderr': result.stderr})
    if entry['arm'] == 'mylang-zero-rc':
        assert symbols, 'stripped/empty symbol table cannot establish absence'
        assert not matches, (binary, matches)
output = EVIDENCE / 'coordinator/symbol-audit.json'
assert not output.exists()
output.write_text(json.dumps({'scope': 'Known legacy myl_core_retain*/myl_core_release* defined native symbols; this is not a complete runtime-layout audit. Direct destruction is not RC.',
                              'command': ['nm', '--defined-only', 'BINARY'], 'entries': rows}, indent=2) + '\n')
print('PASS', len(rows), 'native symbol inventories;', sum(r['arm'] == 'mylang-zero-rc' for r in rows), 'checked binaries have no known core RC symbols')

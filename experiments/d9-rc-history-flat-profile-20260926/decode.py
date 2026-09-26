#!/usr/bin/env python3
"""Decode recorded leaf PCs using the text-identical symbol twin's exact extents."""
import bisect
import collections
import gzip
import json
from pathlib import Path

root = Path(__file__).resolve().parent
symbols = []
for line in (root / 'symbols.nm').read_text().splitlines():
    fields = line.split()
    if len(fields) == 4 and fields[2] in ('t', 'T'):
        symbols.append((int(fields[0], 16), int(fields[1], 16), fields[3]))
symbols.sort()
addresses = [row[0] for row in symbols]
counts = collections.Counter()
period = None
for line in gzip.decompress((root / 'nbody-19e-qbe.samples.txt.gz').read_bytes()).decode().splitlines():
    fields = line.split()
    if len(fields) == 2 and 'instructions' in fields[1]:
        period = int(fields[0])
    elif period is not None and len(fields) == 1:
        address = int(fields[0], 16)
        index = bisect.bisect_right(addresses, address) - 1
        symbol = 'external/unresolved'
        if index >= 0:
            start, size, name = symbols[index]
            if address < start + size:
                symbol = name
        counts[symbol] += period
        period = None
manifest = json.loads(gzip.decompress((root / 'nbody-19e-qbe-symbols.qbe-manifest.json.gz').read_bytes()))
names = {row['symbol']: row['name'] for row in manifest['functions']}
total = sum(counts.values())
assert total == 501600000
result = {'weighted_period': total, 'method': 'One leaf PC per instruction sample, exact nm function extents; no inclusive call-chain sum.',
          'functions': [{'symbol': symbol, 'name': names.get(symbol, symbol), 'period': period,
                         'percent': period * 100 / total} for symbol, period in counts.most_common()]}
(root / 'profile-decoded.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result['functions'][:12], indent=2))

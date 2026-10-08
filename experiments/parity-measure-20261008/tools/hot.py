#!/usr/bin/env python3
"""Print the hot region of one symbol in a perf annotate --stdio file.
usage: hot.py ANNOTATE.txt [SYMBOL_INDEX=0] [MIN_PCT=0.3] [--all]"""
import re, sys
txt = open(sys.argv[1]).read()
idx = int(sys.argv[2]) if len(sys.argv) > 2 else 0
minp = float(sys.argv[3]) if len(sys.argv) > 3 else 0.3
sec = txt.split('==== ')[1 + idx]
print('symbol:', sec.split('\n', 1)[0])
rows = []
for l in sec.split('\n'):
    m = re.match(r'\s+([0-9.]+) :\s+([0-9a-f]+):\s+(.*)', l)
    if m: rows.append((float(m.group(1)), m.group(2), m.group(3)))
hot = [i for i, r in enumerate(rows) if r[0] >= minp]
if '--all' in sys.argv:
    for i in hot: print(f"{rows[i][0]:6.2f} {rows[i][1]} {rows[i][2][:100]}")
else:
    lo, hi = min(hot), max(hot)
    for r in rows[lo:hi + 1]: print(f"{r[0]:6.2f} {r[1]} {r[2][:100]}")

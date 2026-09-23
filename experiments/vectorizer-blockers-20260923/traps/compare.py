#!/usr/bin/env python3
"""compare.py BIN... — run every case of reductions.my through each binary and require identical
stdout, stderr and exit status (stderr paths normalized to the program name)."""
import re
import subprocess
import sys

TOP = 2**63 - 1
cases = []
for kind in ("sum", "indexed", "scaled", "difference", "count"):
    cases += [
        (kind, 0, 0, 0, 0),
        (kind, 1000, 5, 7, 0),
        (kind, 1000, 109, 109, 0),
        (kind, 50, 2**40, 3, TOP - 2**40 * 49),
        (kind, 50, 2**40, 3, TOP - 2**40 * 51),
        (kind, 50, 2**40, 3, -TOP),
        (kind, 3, TOP, 1, 0),
        (kind, 3, -TOP, -1, 0),
        (kind, 3, -TOP, -2, 0),
        (kind, 100, 109, 1, TOP - 99),
        (kind, 100, 109, 1, TOP - 100),
        (kind, 100, 109, 109, TOP - 100),
        (kind, 100, 109, 109, -2**63),
        (kind, 7, 3074457345618258602, 1, 0),
        (kind, 7, 3074457345618258603, 1, 0),
        (kind, 2000, -(2**50), 2**62, 0),
        (kind, 2000, 2**50, -(2**62), -(2**61)),
        (kind, 5, 2**61, 2**61, 2**62),
        (kind, 5, -(2**61), -(2**61), -(2**62)),
    ]
cases += [("octets", n, 0, 0, s) for n, s in ((0, 0), (1000, 0), (1000, TOP - 999),
                                               (1000, TOP - 1000), (1000, TOP), (1000, -2**63))]

bins = sys.argv[1:]
bad = 0
for case in cases:
    args = [str(x) for x in case]
    outs = []
    for b in bins:
        r = subprocess.run([b] + args, capture_output=True, text=True)
        stderr = re.sub(r"/\S*reductions\.my", "reductions.my", r.stderr)
        outs.append((r.returncode, r.stdout, stderr))
    if any(o != outs[0] for o in outs):
        bad += 1
        print("MISMATCH", args)
        for b, o in zip(bins, outs):
            print("  ", b, o)
traps = sum(1 for case in cases
            if subprocess.run([bins[0]] + [str(x) for x in case], capture_output=True).returncode == 1)
print(f"{bad} mismatches in {len(cases)} cases x {len(bins)} binaries; {traps} cases trap")

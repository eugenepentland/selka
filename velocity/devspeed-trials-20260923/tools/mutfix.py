#!/usr/bin/env python3
"""Insert call-site `mut` markers project-wide, applying each diagnostic to the file it names."""
import json, subprocess, sys
from pathlib import Path
binary, root = sys.argv[1], Path(sys.argv[2]).resolve()
entries = sys.argv[3:]
total = 0
for rnd in range(40):
    edits = {}
    for entry in entries:
        r = subprocess.run([binary, "check", entry, "--diagnostics=json"], cwd=root, capture_output=True, text=True)
        for line in r.stderr.splitlines():
            if not line.startswith("{"): continue
            d = json.loads(line).get("diagnostic")
            if not d or d["code"] != "E_MUTATION_MARKER" or "; write `(" not in d["message"]: continue
            p = (root / d["location"]["path"]).resolve()
            edits.setdefault(p, set()).add(d["location"]["bytes"]["start"])
    if not edits: break
    for p, starts in edits.items():
        b = p.read_bytes()
        for s in sorted(starts, reverse=True):
            b = b[:s] + b"mut " + b[s:]
        p.write_bytes(b); total += len(starts)
print(f"inserted {total} markers in {rnd} rounds")

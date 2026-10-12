#!/usr/bin/env python3
"""Bounded allocation probes only; no runtime measurement or full workload."""
import json
import os
from pathlib import Path
import subprocess
import sys

binary = Path(sys.argv[1]).resolve()
evidence = Path(__file__).resolve().parent
rows = []
for width, first in [(1, "small"), (1024, "large")]:
    for arm in ["query", "snapshot"]:
        counts = evidence / f"{arm}-{width}-counters.json"
        env = dict(os.environ, MYLANG_COUNTERS=str(counts))
        args = [str(binary), first] + (["snapshot"] if arm == "snapshot" else [])
        result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=30)
        (evidence / f"{arm}-{width}.stdout").write_text(result.stdout)
        (evidence / f"{arm}-{width}.stderr").write_text(result.stderr)
        if result.returncode:
            raise SystemExit(f"{arm}-{width} returned {result.returncode}")
        doc = json.loads(counts.read_text())
        totals = doc["totals"]
        functions = doc["functions"]
        if isinstance(functions, dict):
            selected = {k: v for k, v in functions.items() if "reads" in k}
        else:
            selected = [x for x in functions if "reads" in str(x)]
        rows.append(dict(width=width, arm=arm, stdout=result.stdout.strip(), totals=totals, read_functions=selected))
(evidence / "counter-summary.json").write_text(json.dumps(rows, indent=2) + "\n")
print(json.dumps(rows, indent=2))

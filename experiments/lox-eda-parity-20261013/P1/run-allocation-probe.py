#!/usr/bin/env python3
"""Reduced owned-construction counters, without runtime timing claims."""
import json
import os
from pathlib import Path
import subprocess
import sys

binary = Path(sys.argv[1]).resolve()
evidence = Path(__file__).resolve().parent
summary = []
for arm in ("fresh", "snapshot"):
    counts = evidence / f"allocation-{arm}-counters.json"
    env = dict(os.environ, MYLANG_COUNTERS=str(counts))
    result = subprocess.run([str(binary)] + (["snapshot"] if arm == "snapshot" else []), env=env, capture_output=True, text=True, timeout=30)
    (evidence / f"allocation-{arm}.stdout").write_text(result.stdout)
    (evidence / f"allocation-{arm}.stderr").write_text(result.stderr)
    if result.returncode:
        raise SystemExit(f"{arm} returned {result.returncode}")
    doc = json.loads(counts.read_text())
    selected = [row for row in doc["functions"] if row["name"] in ("heap::allocate", "heap::allocate_env", "object::new_env")]
    summary.append(dict(arm=arm, stdout=result.stdout.strip(), totals=doc["totals"], constructors=selected))
(evidence / "allocation-summary.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))

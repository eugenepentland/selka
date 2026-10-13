#!/usr/bin/env python3
"""Reduced mutation counters and pre-extraction validation subprocess checks."""
import json
import os
from pathlib import Path
import subprocess
import sys

binary = Path(sys.argv[1]).resolve()
failure_binary = Path(sys.argv[2]).resolve()
evidence = Path(__file__).resolve().parent
summary = []
for arm in ("owned", "snapshot"):
    counts = evidence / f"mutation-{arm}-counters.json"
    env = dict(os.environ, MYLANG_COUNTERS=str(counts))
    result = subprocess.run([str(binary)] + (["snapshot"] if arm == "snapshot" else []), env=env, capture_output=True, text=True, timeout=30)
    (evidence / f"mutation-{arm}.stdout").write_text(result.stdout)
    (evidence / f"mutation-{arm}.stderr").write_text(result.stderr)
    if result.returncode or result.stdout.strip() != "True True True":
        raise SystemExit(f"{arm} failed: status{result.returncode}, stdout{result.stdout!r}")
    doc = json.loads(counts.read_text())
    selected = [row for row in doc["functions"] if any(name in row["name"] for name in ("set_instance_field", "set_class_method", "set_env_slot", "snapshot_set", "instance_snapshot", "class_obj", "env_obj"))]
    summary.append(dict(arm=arm, stdout=result.stdout.strip(), totals=doc["totals"], setters=selected))
(evidence / "mutation-summary.json").write_text(json.dumps(summary, indent=2) + "\n")
failures = []
for mode, message in (("negative_handle", "invalid object handle"), ("high_handle", "invalid object handle"), ("instance_kind", "object is not an instance"), ("class_kind", "object is not a class"), ("env_kind", "object is not an env"), ("high_slot", "environment slot index out of bounds"), ("negative_slot", "environment slot index out of bounds"), ("inherit_parent", "object is not a class"), ("inherit_child", "object is not a class")):
    counts = evidence / f"failure-{mode}-counters.json"
    env = dict(os.environ, MYLANG_COUNTERS=str(counts))
    result = subprocess.run([str(failure_binary), mode], env=env, capture_output=True, text=True, timeout=30)
    (evidence / f"failure-{mode}.stdout").write_text(result.stdout)
    (evidence / f"failure-{mode}.stderr").write_text(result.stderr)
    if result.returncode in (0, 98, 99) or message not in result.stderr or result.stdout:
        raise SystemExit(f"{mode} failed validation check: status{result.returncode}, stdout{result.stdout!r}, stderr{result.stderr!r}")
    totals = json.loads(counts.read_text())["totals"] if counts.exists() else None
    failures.append(dict(mode=mode, status=result.returncode, message=message, totals=totals))
(evidence / "mutation-failure-summary.json").write_text(json.dumps(failures, indent=2) + "\n")
print(json.dumps(dict(mutation=summary, failures=failures), indent=2))

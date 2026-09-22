#!/usr/bin/env python3
"""Recompute a run record's derived fields from what it left behind.

A record's identity (arm, task, run, work dir, launch) is immutable; its session
signals and its diff are derived, and the decoder that derives them improves
while a sweep is running. This rewrites the derived half of every record so the
whole set is measured by one version of the instrument.

    python3 experiments/cascade/dev/normalize_runs.py [--dry-run]
"""

from __future__ import annotations

import argparse
from datetime import datetime
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
CASCADE = HERE.parent
sys.path.insert(0, str(CASCADE))
import run as runlib  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    changed = 0
    for path in sorted(runlib.RUNS.glob("*/*/*.json")):
        if not path.stem.isdigit() and not path.stem.startswith("chain-"):
            continue
        record = json.loads(path.read_text())
        work = Path(record["work_dir"])
        if not work.is_dir():
            print(f"skip {path}: working copy is gone")
            continue
        updated = dict(record)
        launched = record.get("session_launch") or {}
        if launched.get("started_utc"):
            updated["session"] = runlib.read_session_logs(work.resolve(), datetime.fromisoformat(launched["started_utc"]))
        reference = runlib.arm_dir(record["arm"])
        if record.get("chain_parent"):
            reference = Path(record["chain_parent"])
        updated["diff"] = runlib.diff_against_arm(work, reference)
        if updated != record:
            changed += 1
            print(f"{record['arm']}/{record['task']}/{record.get('run')}: refreshed")
            if not args.dry_run:
                path.write_text(json.dumps(updated, indent=2) + "\n")
    print(f"{changed} record(s) refreshed")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Run a frozen cohort exactly as scheduled, one participant at a time by default.

The schedule comes from the manifest, not from a directory listing: blocks are
`(case, repetition)` with a randomized arm order, and every cell is run once. A
cell that already has evidence is skipped rather than overwritten; a retry is a
new attempt, run by hand with `run.py --attempt N --reason …`.

    python3 experiments/diagnostic-feedback/sweep.py --cohort m1-pilot --dry-run
    python3 experiments/diagnostic-feedback/sweep.py --cohort m1-pilot
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
COHORTS = HERE / "cohorts"
sys.path.insert(0, str(HERE))
import cohort  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cohort", required=True)
    parser.add_argument("--jobs", type=int, default=1, help="participants at a time (default 1)")
    parser.add_argument("--dry-run", action="store_true", help="print the schedule and the session count; launch nothing")
    parser.add_argument("--force", action="store_true", help="re-run cells that already have evidence (new attempts)")
    args = parser.parse_args()
    root = COHORTS / args.cohort
    manifest_path = root / "manifest.json"
    if not manifest_path.is_file():
        raise SystemExit(f"no manifest at {manifest_path}; freeze one with cohort.new_manifest")
    manifest = cohort.load(manifest_path)
    schedule = manifest["schedule"]
    pending = []
    for row in schedule:
        destination = cohort.attempt_dir(root, row["arm"], row["case"], row["repetition"], 1)
        if destination.exists() and not args.force:
            continue
        pending.append(row)
    print(f"cohort {args.cohort}: {len(schedule)} scheduled cells, {len(schedule) - len(pending)} already recorded, "
          f"{len(pending)} to run, {args.jobs} at a time")
    if args.dry_run:
        for row in schedule:
            state = "recorded" if cohort.attempt_dir(root, row["arm"], row["case"], row["repetition"], 1).exists() else "pending"
            print(f"  {row['arm']:<10} {row['case']:<16} repetition {row['repetition']}  {state}")
        print(f"maximum sessions this run would launch: {len(pending)}")
        return 0
    started = datetime.now(timezone.utc).isoformat()
    with (root / "sweep.log").open("a") as handle:
        handle.write(f"# sweep {started} pending={len(pending)} jobs={args.jobs}\n")
    from concurrent.futures import ThreadPoolExecutor

    def run(row: dict) -> str:
        completed = subprocess.run(
            [sys.executable, str(HERE / "run.py"), "--cohort", args.cohort, "--arm", row["arm"],
             "--case", row["case"], "--repeat", str(row["repetition"])],
            capture_output=True, text=True,
        )
        line = (completed.stdout.strip().splitlines() or ["no output"])[-1]
        with (root / "sweep.log").open("a") as handle:
            handle.write(f"{datetime.now(timezone.utc).isoformat()} {row['arm']}/{row['case']}/{row['repetition']}: {line}\n")
        print(f"  {line}", flush=True)
        return line

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        list(pool.map(run, pending))
    (root / "sweep.json").write_text(json.dumps(
        {"cohort": args.cohort, "started_utc": started, "finished_utc": datetime.now(timezone.utc).isoformat(),
         "cells": len(schedule), "launched": len(pending), "jobs": args.jobs}, indent=2) + "\n")
    print(f"done: {len(pending)} cells launched")
    return 0


if __name__ == "__main__":
    sys.exit(main())

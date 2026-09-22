#!/usr/bin/env python3
"""Execution integrity for a running cohort — no treatment comparisons.

Answers only the questions that decide whether the cohort can be read at all:
which scheduled cells have completed, whether each attempt left a sealed snapshot
whose hash matches its record, whether the event log is complete, whether the
identity matches the frozen manifest, and what infrastructure went wrong.

    python3 experiments/diagnostic-feedback/monitor.py --cohort m1b
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import cohort  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cohort", required=True)
    args = parser.parse_args()
    root = HERE / "cohorts" / args.cohort
    manifest = cohort.load(root / "manifest.json")
    identity = manifest["identity"]
    counts = {"scheduled": len(manifest["schedule"]), "completed": 0, "missing": 0, "snapshot_ok": 0,
              "snapshot_missing": 0, "snapshot_mismatch": 0, "events_missing": 0, "events_truncated": 0,
              "events_duplicated": 0, "infrastructure": 0, "timeouts": 0, "grader_incidents": 0,
              "retries": 0, "identity_mismatch": 0, "hidden_ok": 0, "public_only": 0}
    problems: list[str] = []
    for row in manifest["schedule"]:
        directory = cohort.attempt_dir(root, row["arm"], row["case"], row["repetition"], 1).parent
        attempts = sorted(directory.iterdir(), key=lambda path: int(path.name)) if directory.is_dir() else []
        if not attempts:
            counts["missing"] += 1
            continue
        counts["completed"] += 1
        counts["retries"] += max(0, len(attempts) - 1)
        latest = attempts[-1]
        record_path = latest / "record.json"
        if not record_path.is_file():
            problems.append(f"{row['arm']}/{row['case']}/{row['repetition']}: no record in {latest.name}")
            counts["missing"] += 1
            continue
        record = json.loads(record_path.read_text())
        snapshot = latest / "sealed"
        if not snapshot.is_dir():
            counts["snapshot_missing"] += 1
            problems.append(f"{row['arm']}/{row['case']}/{row['repetition']}: sealed snapshot missing")
        elif record.get("sealed_source_sha256") != cohort.seal(snapshot, latest / ".monitor-reseal"):
            counts["snapshot_mismatch"] += 1
            problems.append(f"{row['arm']}/{row['case']}/{row['repetition']}: snapshot hash mismatch")
        else:
            counts["snapshot_ok"] += 1
        import shutil
        shutil.rmtree(latest / ".monitor-reseal", ignore_errors=True)
        events_file = latest / "events.jsonl"
        if not events_file.is_file():
            counts["events_missing"] += 1
        else:
            coverage = (record.get("events") or {}).get("coverage") or {}
            counts["events_truncated"] += coverage.get("truncated", 0)
            counts["events_duplicated"] += coverage.get("duplicates", 0)
            counts["infrastructure"] += ((record.get("events") or {}).get("metrics") or {}).get("infrastructure_failures", 0)
        counts["timeouts"] += 1 if record.get("termination") == "timeout" else 0
        counts["grader_incidents"] += 0 if (record.get("grading") or {}).get("grader_ok", True) else 1
        counts["hidden_ok"] += 1 if record.get("hidden_acceptance") else 0
        counts["public_only"] += 1 if record.get("public_acceptance") and not record.get("hidden_acceptance") else 0
        observed = ((record.get("session") or {}).get("models") or {})
        if observed and set(observed) != {identity["model"]}:
            counts["identity_mismatch"] += 1
            problems.append(f"{row['arm']}/{row['case']}/{row['repetition']}: model {sorted(observed)}")
        toolchain = (record.get("toolchain") or {}).get("compiler_sha256")
        if toolchain and toolchain != identity["compiler_sha256"]:
            counts["identity_mismatch"] += 1
            problems.append(f"{row['arm']}/{row['case']}/{row['repetition']}: compiler {str(toolchain)[:12]}")
    print(f"cohort {args.cohort}: {counts['completed']}/{counts['scheduled']} cells completed, "
          f"{counts['missing']} outstanding")
    print(f"  sealed snapshots verified {counts['snapshot_ok']}, missing {counts['snapshot_missing']}, "
          f"mismatched {counts['snapshot_mismatch']}")
    print(f"  event coverage: logs missing {counts['events_missing']}, truncated events {counts['events_truncated']}, "
          f"duplicate deliveries {counts['events_duplicated']}")
    print(f"  incidents: infrastructure {counts['infrastructure']}, timeouts {counts['timeouts']}, "
          f"grader {counts['grader_incidents']}, identity mismatches {counts['identity_mismatch']}, "
          f"retries {counts['retries']}")
    print(f"  outcomes so far: hidden-OK {counts['hidden_ok']}, public-only {counts['public_only']}")
    for problem in problems[:10]:
        print(f"  ! {problem}")
    print("treatment comparisons are deliberately absent here; they belong to the frozen readout")
    return 0


if __name__ == "__main__":
    sys.exit(main())

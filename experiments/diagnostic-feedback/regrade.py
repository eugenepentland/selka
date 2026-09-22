#!/usr/bin/env python3
"""Re-grade sealed snapshots after an instrument fix, without new sessions.

Grading is coordinator-side and deterministic, and the sealed snapshot is the
immutable evidence: when the grader itself was wrong, re-running it is the honest
repair, not re-running the participants. Session data, events and metrics are left
exactly as recorded.

    python3 experiments/diagnostic-feedback/regrade.py --cohort m1-pilot [--reference]
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import importlib.util  # noqa: E402

_spec = importlib.util.spec_from_file_location("dfrun", HERE / "run.py")
dfrun = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(dfrun)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cohort", required=True)
    parser.add_argument("--reference", action="store_true",
                        help="also grade each case's reference repair (a grader sanity check)")
    args = parser.parse_args()
    root = HERE / "cohorts" / args.cohort
    graded = 0
    for record_path in sorted(root.glob("runs/*/*/*/*/record.json")):
        record = json.loads(record_path.read_text())
        staging = record_path.parent / "_regrade"
        if staging.exists():
            shutil.rmtree(staging)
        staging.mkdir()
        snapshot = record_path.parent / "sealed"
        if not snapshot.is_dir():
            print(f"  no sealed snapshot for {record_path}")
            continue
        grading = dfrun.grade(staging, record["case"], snapshot)
        record["grading"] = grading
        record["hidden_acceptance"] = grading["hidden_acceptance"]
        record["public_acceptance"] = grading["public_acceptance"]
        record["regraded_utc"] = __import__("datetime").datetime.now(
            __import__("datetime").timezone.utc).isoformat()
        record_path.write_text(json.dumps(record, indent=2) + "\n")
        graded += 1
        print(f"  {record['arm']}/{record['case']}/{record['repetition']}: hidden={grading['hidden_acceptance']} "
              f"public={grading['public_acceptance']}")
    print(f"re-graded {graded} attempts")
    return 0


if __name__ == "__main__":
    sys.exit(main())

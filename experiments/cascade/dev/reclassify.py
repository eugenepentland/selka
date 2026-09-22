#!/usr/bin/env python3
"""Reclassify run records whose verification died in the toolchain.

A command that fails with `mylang: host failure`, `NativeToolFailed` or a failed
sub-compilation says nothing about the change under test: the session is
discarded and the cell is rerun. This script finds those records, rewrites their
verdict (preserving the record under its old verdict beside the new one) and
prints the cells that now need a rerun.

    python3 experiments/cascade/dev/reclassify.py [--dry-run]
"""

from __future__ import annotations

import argparse
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
    rerun = []
    for path in sorted(runlib.RUNS.glob("*/*/*.json")):
        if not path.stem.isdigit() and not path.stem.startswith("chain-"):
            continue
        record = json.loads(path.read_text())
        if record.get("verdict") != "failed":
            continue
        report_path = Path((record.get("verify") or {}).get("report") or "")
        hits = runlib.infrastructure_failures(report_path)
        if not hits:
            continue
        label = f"{record['arm']}/{record['task']}/{record.get('run')}"
        rerun.append(f"{record['arm']} {record['task']} {record['run']}")
        print(f"{label}: host failure in {hits} -> discarded-infrastructure")
        if args.dry_run:
            continue
        record["verdict"] = "discarded-infrastructure"
        record["verify"]["infrastructure_failures"] = hits
        archive = path.parent / f"{path.stem}.failed.json"
        if not archive.exists():
            archive.write_text(json.dumps({**record, "verdict": "failed"}, indent=2) + "\n")
        path.write_text(json.dumps(record, indent=2) + "\n")
    if rerun:
        print("\ncells to rerun:")
        print("\n".join(rerun))
    else:
        print("no infrastructure failures found")
    return 0


if __name__ == "__main__":
    sys.exit(main())

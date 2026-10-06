#!/usr/bin/env python3
"""Profile already built CSV/JSON guests, preserving exact native outcomes.

Run under a build slot and the shared CPU10 flock. No compiler is invoked.
Each profiled native checksum must equal the explicit old guest at identical
arguments. Native status/stdout, perf diagnostics and report status are retained.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


def run(command):
    result = subprocess.run(list(map(str, command)), capture_output=True, text=True)
    record = {"command": list(map(str, command)), "status": result.returncode,
              "stdout": result.stdout, "stderr": result.stderr}
    return result, record


def checksum(result):
    if result.returncode != 0 or not re.fullmatch(r"-?[0-9]+ [0-9]+\n", result.stdout):
        raise RuntimeError("invalid profile native status/stdout")
    return int(result.stdout.split()[0])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bins", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--data", type=Path, required=True)
    args = parser.parse_args()
    if args.evidence.exists() or args.data.exists():
        parser.error("profile evidence/data paths must be fresh")
    args.evidence.mkdir(parents=True)
    args.data.mkdir(parents=True)
    report = {}
    for row, iterations in (("csv_aggregate", 1600), ("json_transform", 600)):
        old, new = [args.bins.resolve() / f"row_{row}_{role}" for role in ("old", "new")]
        data = args.data.resolve() / f"{row}.data"
        before, old_record = run(["taskset", "-c", "10", old, "4096", str(iterations), "7"])
        after, new_record = run(["taskset", "-c", "10", "perf", "record", "-F", "997", "-e", "cpu_core/cycles/u",
                                 "-g", "-o", data, "--", new, "4096", str(iterations), "7"])
        listing, list_record = run(["perf", "report", "--stdio", "--no-children", "--sort", "comm,dso,symbol", "-i", data])
        report[row] = {"old": old_record, "profiled_new": new_record, "report": list_record,
                       "old_sha256": hashlib.sha256(old.read_bytes()).hexdigest(),
                       "new_sha256": hashlib.sha256(new.read_bytes()).hexdigest()}
        (args.evidence / "commands.json").write_text(json.dumps(report, indent=2) + "\n")
        (args.evidence / f"{row}.txt").write_text(listing.stdout)
        if before.stderr or checksum(before) != checksum(after) or listing.returncode != 0:
            raise RuntimeError(f"{row} profile failed status/checksum/report validation")
    print("CSV/JSON profile native statuses and checksums agree")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

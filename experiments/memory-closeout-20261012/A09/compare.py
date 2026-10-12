#!/usr/bin/env python3
"""Run one prepared runtime case per exclusive lease, yielding to ordinary work."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

import measure


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument("--after", type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument("--output", type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument("--cases", nargs="+")
    args = parser.parse_args()
    before, after = (json.loads(p.read_text()) for p in (args.before, args.after))
    for record in (before, after):
        if measure.digest(record["compiler"]) != record["compiler_sha256"]:
            parser.error("prepared compiler identity changed")
        for case in record["cases"]:
            if not case.get("build_status", 0) and measure.digest(case["binary"]) != case["binary_sha256"]:
                parser.error(f"prepared binary changed: {case['id']}")
    before_ids = [case["id"] for case in before["cases"]]
    if before_ids != [case["id"] for case in after["cases"]]:
        parser.error("prepared arms must have identical ordered case IDs")
    selected = args.cases or before_ids
    if set(selected) - set(before_ids):
        parser.error("unknown case selection")
    args.output.mkdir(parents=True, exist_ok=True)
    result = args.output / "results.json"
    completed = {}
    if result.exists():
        previous = json.loads(result.read_text())
        if previous["builds"] != {"before": before, "after": after}:
            parser.error("existing results refer to different artifacts")
        completed = previous["cases"]
    slot = str(measure.ROOT / "scripts/build-slot.sh")
    harness = str(Path(__file__).with_name("measure.py"))
    for name in selected:
        if name in completed:
            print("preserved", name, flush=True)
            continue
        # Admission wait is outside the measurement harness. The ordinary ticket
        # gives earlier queued builds a turn before each new exclusive window.
        subprocess.run([slot, "build", "true"], cwd=measure.ROOT, check=True)
        command = [slot, "timing", sys.executable, "-B", harness, "run",
                   "--before", str(args.before), "--after", str(args.after),
                   "--output", str(result), "--cases", name]
        with (args.output / f"{name}.log").open("x") as log:
            subprocess.run(command, cwd=measure.ROOT, stdout=log,
                           stderr=subprocess.STDOUT, check=True)
        print("completed", name, flush=True)


if __name__ == "__main__":
    main()

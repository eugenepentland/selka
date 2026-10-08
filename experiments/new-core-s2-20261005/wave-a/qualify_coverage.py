#!/usr/bin/env python3
"""Run the inherited coverage sweep and retain complete, checked child reports."""
import argparse
from collections import Counter
import importlib.util
import json
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    args.evidence.mkdir(parents=True, exist_ok=True)
    spec = importlib.util.spec_from_file_location(
        "coverage_sweep", ROOT / "experiments/new-core-s0-20261005/coverage.py")
    sweep = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(sweep)
    original_run = subprocess.run
    children = []
    outcomes = Counter()

    def run(argv, **options):
        options["timeout"] = 300
        result = original_run(argv, **options)
        index = len(children) + 1
        (args.evidence / f"corpus-{index}.txt").write_text(result.stdout)
        (args.evidence / f"corpus-{index}.err").write_text(result.stderr)
        children.append({"command": argv, "exit": result.returncode})
        if result.returncode:
            raise RuntimeError(f"coverage child {index} exited {result.returncode}")
        for line in result.stdout.splitlines():
            kind, _, rest = line.partition(" ")
            if kind == "refused":
                outcomes[rest.partition("\t")[0]] += 1
        return result

    sys.argv = [str(ROOT / "experiments/new-core-s0-20261005/coverage.py")]
    subprocess.run = run
    error = None
    try:
        sweep.main()
        if len(children) != 4:
            raise RuntimeError(f"expected four coverage corpora, got {len(children)}")
    except Exception as failure:
        error = f"{type(failure).__name__}: {failure}"
        print(error, file=sys.stderr)
    finally:
        subprocess.run = original_run
    summary = {"qualified": error is None, "error": error, "children": children,
               "all_refusal_occurrences": dict(outcomes.most_common()),
               "note": "Raw occurrences include repeated imported functions; the inherited table deduplicates names."}
    (args.evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    return 0 if error is None else 1


if __name__ == "__main__":
    raise SystemExit(main())

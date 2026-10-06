#!/usr/bin/env python3
"""Compare actual Core and old property verdicts, evidence and complete reasons.

Receipt/compiler metadata are outside the Core report contract. Every reported
property count and counterexample field is compared; unsupported never qualifies.
"""
import argparse
import json
from pathlib import Path


def report(path):
    rows = [line for line in Path(path).read_text().splitlines() if line.startswith("{")]
    if not rows:
        raise ValueError(f"{path}: no native report")
    return json.loads(rows[-1])


def project(test):
    result = {key: test[key] for key in ("name", "status", "reason")}
    if "property" in test:
        result["property"] = test["property"]
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pair", nargs=2, action="append", required=True, metavar=("OLD", "CORE"))
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    rows = []
    for old_path, core_path in args.pair:
        old, core = report(old_path), report(core_path)
        expected = {test["name"]: project(test) for test in old["tests"]}
        actual = {test["name"]: project(test) for test in core["tests"]}
        problems = []
        for name in sorted(expected.keys() | actual.keys()):
            if expected.get(name) != actual.get(name):
                problems.append({"name": name, "old": expected.get(name), "core": actual.get(name)})
        if core.get("unsupported", 0):
            problems.append({"unsupported": core["unsupported"]})
        rows.append({"old": old_path, "core": core_path, "tests": len(expected), "matching": len(expected) - len(problems), "mismatches": problems})
    summary = {"tests": sum(row["tests"] for row in rows), "mismatches": sum(len(row["mismatches"]) for row in rows), "pairs": rows}
    Path(args.output).write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps({key: summary[key] for key in ("tests", "mismatches")}))
    return int(summary["mismatches"] != 0)


if __name__ == "__main__":
    raise SystemExit(main())

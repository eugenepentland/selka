#!/usr/bin/env python3
"""Acceptance check: one fresh checked compilation per selected provider graph.

Reads native-probe.json and asserts that each successful native-test sample ran
at most one compiler child that performed or reused checked bodies (the folded
`command:"test"` record is the parent aggregate and is excluded), and that no
`emit-project-qbe` child re-checked a project after facts were produced.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def stage(child, name):
    return ((child.get("stages") or {}).get(name)) or {}


def checking_children(sample):
    out = []
    for child in sample.get("child_reports") or []:
        if child.get("command") == "test":
            continue  # folded parent aggregate, not a child pass
        checked = stage(child, "checked_bodies")
        if (checked.get("performed") or 0) + (checked.get("reused") or 0) > 0:
            out.append(child.get("command"))
    return out


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "native-probe.json"
    document = json.loads(path.read_text())
    failures = []
    samples = 0
    for workload in document["workloads"]:
        for state in workload["states"]:
            for index, sample in enumerate(state["samples"]):
                if not sample.get("success"):
                    continue
                samples += 1
                checkers = checking_children(sample)
                commands = sample.get("child_commands") or []
                where = f"{workload['label']}/{state['state']}#{index}"
                if len(checkers) > 1:
                    failures.append(f"{where}: {len(checkers)} checking children {checkers}")
                if "emit-project-qbe" in commands:
                    failures.append(f"{where}: linking path spawned emit-project-qbe")
    if failures:
        print("FAIL")
        for failure in failures:
            print("  " + failure)
        return 1
    print(f"PASS: {samples} successful samples, at most one checked compilation each")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

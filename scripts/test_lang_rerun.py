#!/usr/bin/env python3
"""Run each language suite twice in one fresh work directory, the second time with `--force`, and fail on any test
whose verdict differs between the two runs or that is `unsupported` in either (lane FX10, 14 November 2026).

A stored record that is served to a program it does not fit shows only on a run that is not the first in its work
directory: the gate's forced run is a single run in a private cache, and an ordinary run replays its results. Here the
second run is forced, so every test runs again with the first run's checked bodies, stage records and unit objects on hand.
This is `zig build test-lang-rerun`, which the complete gate does not run (about 93 s for `tests/lang` on the
14 November machine); it runs in the debug mode the language gate uses, with the leak check and `--verify-facts`.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SUITES = ("tests/lang", "tests/value_semantics", "tests/ported")


def verdicts(stdout: str) -> dict[str, tuple[str, str]] | None:
    """The `native-tests-v1` report's tests by name, as (status, reason); None when the run printed no report."""
    for line in reversed(stdout.splitlines()):
        if line.startswith("{") and '"tests"' in line:
            try:
                report = json.loads(line)
            except json.JSONDecodeError:
                continue
            return {test["name"]: (test["status"], test.get("reason", "")) for test in report.get("tests", [])}
    return None


def passing(status: str) -> bool:
    return status in ("passed", "cached")


def compare(suite: str, first: dict, second: dict) -> list[str]:
    """One line per test that is unsupported in either run or whose verdict differs between them."""
    problems = []
    for name in sorted(set(first) | set(second)):
        before = first.get(name, ("absent", ""))
        after = second.get(name, ("absent", ""))
        if before[0] == "unsupported" or after[0] == "unsupported":
            problems.append(f"{suite}: {name} is unsupported: {before[0]} then {after[0]} ({(after[1] or before[1])[:200]})")
        elif passing(before[0]) != passing(after[0]) or "absent" in (before[0], after[0]):
            problems.append(f"{suite}: {name} changed its verdict: {before[0]} then {after[0]} ({(after[1] or before[1])[:200]})")
    return problems


def run_suite(compiler: str, suite: str, work: Path, run=subprocess.run) -> list[str]:
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    environment = dict(os.environ, SELKA_CORE_LEAKCHECK="1")
    tables = []
    for extra in ([], ["--force"]):
        argv = [compiler, "test", suite, "--json", "--verify-facts", "--cache-dir", str(work), *extra]
        completed = run(argv, cwd=ROOT, env=environment, capture_output=True, text=True, errors="replace")
        table = verdicts(completed.stdout)
        if table is None:
            sys.stderr.write(completed.stderr[-4000:])
            return [f"{suite}: `{' '.join(argv[1:])}` printed no report (exit {completed.returncode})"]
        tables.append(table)
    return compare(suite, tables[0], tables[1])


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--work", type=Path, default=ROOT / ".selka-cache/lang-rerun")
    parser.add_argument("suites", nargs="*", default=list(SUITES))
    args = parser.parse_args(argv)
    problems = []
    for suite in args.suites:
        found = run_suite(args.compiler, suite, args.work / suite.replace("/", "_"))
        print(f"test-lang-rerun: {suite}: {'ok' if not found else str(len(found)) + ' problems'}", flush=True)
        problems.extend(found)
    for problem in problems:
        print(f"test-lang-rerun: {problem}", file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

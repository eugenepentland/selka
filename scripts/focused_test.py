#!/usr/bin/env python3
"""Supported focused-test wrapper for the Zig suites.

Run from anywhere inside the repository:

    python3 scripts/focused_test.py units arena
    python3 scripts/focused_test.py cli "CLI managed constants"
    python3 scripts/focused_test.py full

``units``, ``cli`` and ``golden`` require a non-empty substring and compile only
the tests whose names match it, so an ordinary edit cycle never selects the whole
suite by accident. ``full`` is the explicit full-suite request and refuses a
filter, which keeps "I meant one area" and "I meant everything" distinguishable.

The wrapper:

* rejects an empty or whitespace-only filter before invoking Zig;
* forwards ``-Dtest-filter`` exactly as the build targets expect;
* prints the selected-test count and the runner's PASS/FAIL verdict;
* saves the complete build output and reports the log path;
* reports wall time; and
* exits with the wrapped command's status, even when the output is trimmed.

It only ever invokes the supported ``zig build`` targets. Do not copy the
``--listen=-`` command line the build runner prints for an internal test step.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
LOG_DIR = ROOT / ".mylang-cache" / "focused-tests"
# Targets that honour `-Dtest-filter`. `full` is the whole gate, which does not.
FOCUSED = {"units": "test-units", "cli": "test-cli", "golden": "test-golden"}
FULL = "full"
SELECTED = re.compile(r"(\d+)\s+test\(s\) selected")
RESULT = re.compile(r"guardian/test: RESULT (\{.*\})")


class FilterError(ValueError):
    """The requested test selection was empty or contradictory."""


def validate(root: str, filt: str | None) -> str | None:
    """Return the filter to pass, or raise :class:`FilterError` on a bad request."""
    if root == FULL:
        if filt is not None and filt.strip():
            raise FilterError("full runs the whole suite; drop the test filter")
        return None
    if root not in FOCUSED:
        raise FilterError("unknown target {!r}; choose {}".format(root, ", ".join(sorted([*FOCUSED, FULL]))))
    if filt is None or not filt.strip():
        raise FilterError("{} needs a non-empty test filter; use `full` for the whole suite".format(root))
    if "\x00" in filt:
        raise FilterError("test filter must not contain a NUL byte")
    return filt


def command(root: str, filt: str | None) -> list[str]:
    """The supported ``zig build`` command line for one request."""
    target = "test" if root == FULL else FOCUSED[root]
    argv = ["zig", "build", target, "--summary", "all"]
    if filt is not None:
        argv.append("-Dtest-filter=" + filt)
    return argv


def parse_selected(text: str) -> int | None:
    """The number of tests the runners reported selecting before they ran them.

    Summed, not last-wins: ``full`` runs several test binaries, and its two slow
    roots run as several shards each, so one line is one process's share. The
    shards partition their root, so the sum is the whole run.
    """
    matches = SELECTED.findall(text)
    return sum(int(match) for match in matches) if matches else None


def parse_result(text: str) -> dict | None:
    """The runners' machine-readable closing verdicts, summed into one.

    Same reason as ``parse_selected``: every test process prints its own RESULT
    line, and the run is green only when all of them are.
    """
    matches = RESULT.findall(text)
    if not matches:
        return None
    total = {"passed": 0, "failed": 0, "skipped": 0, "aborted": False, "processes": 0}
    for match in matches:
        try:
            parsed = json.loads(match)
        except json.JSONDecodeError:
            continue
        if not isinstance(parsed, dict):
            continue
        total["processes"] += 1
        for key in ("passed", "failed", "skipped"):
            total[key] += int(parsed.get(key, 0) or 0)
        total["aborted"] = total["aborted"] or bool(parsed.get("aborted"))
    return total if total["processes"] else None


def describe(root: str, filt: str | None, selected: int | None, result: dict | None, returncode: int = 0) -> list[str]:
    """Concise human summary lines for the completed run."""
    label = FULL if root == FULL else "{} filter={!r}".format(root, filt)
    lines = ["focused tests: {}".format(label)]
    if selected is not None:
        lines.append("selected: {} test(s)".format(selected))
    if result is not None:
        passed, failed = result.get("passed", 0), result.get("failed", 0)
        skipped = result.get("skipped", 0)
        # A run can abort before failing any test (a filter that named nothing);
        # never report PASS for a nonzero exit or an aborted selection.
        verdict = "PASS" if failed == 0 and not result.get("aborted") and returncode == 0 else "FAIL"
        processes = result.get("processes", 1)
        across = " across {} test process(es)".format(processes) if processes > 1 else ""
        lines.append("result: {} - {} passed, {} failed, {} skipped{}".format(verdict, passed, failed, skipped, across))
    elif returncode != 0:
        lines.append("result: FAIL - the build or test runner exited {}".format(returncode))
    return lines


def log_path(root: str, filt: str | None) -> Path:
    """A stable, ignored path for the complete output of this run."""
    stamp = time.strftime("%Y%m%d-%H%M%S")
    slug = (filt or "full").replace("/", "_").replace(" ", "_")[:48]
    return LOG_DIR / "{}-{}-{}.log".format(root, slug, stamp)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("target", help="units, cli, golden, or full")
    parser.add_argument("filter", nargs="?", help="non-empty substring for a focused target")
    parser.add_argument("--tail", type=int, default=60, help="log lines to show after a failure (default 60)")
    args = parser.parse_args(argv)

    try:
        filt = validate(args.target, args.filter)
    except FilterError as error:
        print("focused test: {}".format(error), file=sys.stderr)
        return 2

    argv = command(args.target, filt)
    started = time.time()
    completed = subprocess.run(argv, cwd=str(ROOT), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    elapsed = time.time() - started
    output = completed.stdout or ""

    LOG_DIR.mkdir(parents=True, exist_ok=True)
    path = log_path(args.target, filt)
    path.write_text(output, encoding="utf-8")

    selected = parse_selected(output)
    result = parse_result(output)
    for line in describe(args.target, filt, selected, result, completed.returncode):
        print(line)
    print("elapsed: {:.1f}s".format(elapsed))
    print("log: {}".format(path))

    if completed.returncode != 0:
        lines = output.splitlines()
        tail = lines[-args.tail:] if args.tail > 0 else lines
        if tail:
            print("--- last {} log line(s) ---".format(len(tail)))
            for line in tail:
                print(line)
    return completed.returncode


if __name__ == "__main__":
    sys.exit(main())

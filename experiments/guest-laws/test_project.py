#!/usr/bin/env python3
"""Run exported `test_` guest functions natively and report their typed outcomes.

`mylang test` is the compiler's own native guest-test runner: it discovers the
exported `test_` functions, builds them, and runs each as a fresh process with
the arguments and expected value one JSON case file supplies. This wraps that
command so callers get one `guest-tests-v1` document, translating the native
`native-tests-v1` report and hashing the project sources for a run identity.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile


def command(compiler, entry, pattern, cases_path, cache):
    argv = [str(compiler), "test", str(entry), "--filter", pattern, "--json", "--cache-dir", str(cache)]
    if cases_path is not None:
        argv += ["--cases", str(cases_path)]
    return subprocess.run(argv, capture_output=True, text=True, timeout=180)


def snapshot(project):
    """A stable digest of every guest source under the project directory."""
    digest = hashlib.sha256()
    for path in sorted(project.rglob("*.my")):
        digest.update(path.relative_to(project).as_posix().encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def translate(report):
    """One `guest-tests-v1` row per native result; a reused pass reads as passed."""
    rows = []
    for test in report["tests"]:
        status = "passed" if test["status"] == "cached" else test["status"]
        rows.append({
            "name": test["name"],
            "status": status,
            "actual": test.get("actual"),
            "expected": test.get("expected"),
            "reason": test.get("reason", ""),
        })
    return rows


def run(compiler, entry, pattern="*", cases=None):
    compiler, entry = Path(compiler).resolve(), Path(entry).resolve()
    with tempfile.TemporaryDirectory(prefix="mylang-tests-") as temporary:
        cache = Path(temporary) / "cache"
        cases_path = None
        if cases:
            cases_path = Path(temporary) / "cases.json"
            cases_path.write_text(json.dumps(cases))
        result = command(compiler, entry, pattern, cases_path, cache)
        line = next((row for row in reversed(result.stdout.splitlines()) if row.startswith("{")), None)
        if line is None:
            raise ValueError(result.stderr or result.stdout or "no native test report")
        report = json.loads(line)
    rows = translate(report)
    status = ("empty" if not rows else
              "failed" if any(row["status"] not in ("passed", "skipped") for row in rows) else
              "skipped" if all(row["status"] == "skipped" for row in rows) else "passed")
    return {"version": "guest-tests-v1", "status": status, "snapshot_sha256": snapshot(entry.parent), "tests": rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("entry", type=Path)
    parser.add_argument("--compiler", type=Path, default=Path(__file__).resolve().parents[2] / "zig-out/bin/mylang")
    parser.add_argument("--filter", default="*")
    parser.add_argument("--cases", type=Path, help="JSON object mapping qualified tests to arguments/expected/skip")
    args = parser.parse_args()
    try:
        cases = json.loads(args.cases.read_text()) if args.cases else None
        report = run(args.compiler, args.entry, args.filter, cases)
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        print(json.dumps({"version": "guest-tests-v1", "status": "infrastructure-failure", "message": str(error)}))
        return 2
    print(json.dumps(report, ensure_ascii=False))
    return {"passed": 0, "failed": 1, "empty": 3, "skipped": 3}[report["status"]]


if __name__ == "__main__":
    sys.exit(main())

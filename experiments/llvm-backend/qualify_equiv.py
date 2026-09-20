#!/usr/bin/env python3
"""Differential guest-suite verification: every suite, both backend arms.

    qualify_equiv.py [--work DIR] [--jobs N] [--json OUT] [--only NAME]

Runs each suite twice — once through the default QBE tool, once through
`qbe_llvm.py` — in *separate* cache directories, so no result can be reused
across arms, and compares the per-test verdicts by name (not just the totals),
the summary counts, the exit status and the full output.  A test that fails to
*build* in the LLVM arm shows up as a build diagnostic in that arm's stderr; the
comparison records exactly which names lost their verdict.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

from qualify_identity import identity

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
ADAPTER = HERE / "qbe_llvm.py"

#: suite -> (entry path, extra arguments).  The inner fan-out is filled in from
#: `--inner-jobs`: concurrent test children contend for the same cache objects,
#: and the driver's cache staging loses that race (see the report's limitations),
#: so a comparison run that must not lose tests uses one child at a time.
SUITES = {
    "lang": ("tests/lang", []),
    "lang-stress": ("tests/lang", ["--gc-stress"]),
    "guest": ("tests/guest", []),
    "sexpr-port": ("experiments/sexpr-port", []),
}

SUMMARY = re.compile(r"(\d+) passed, (\d+) cached, (\d+) failed, (\d+) skipped")
VERDICT = re.compile(r"^(passed|failed|skipped|error|timeout|panicked) (\S+)$")


def parse(text):
    """The summary counts and the per-name verdicts in one run's stdout."""
    counts = None
    verdicts = {}
    for line in text.splitlines():
        found = SUMMARY.search(line)
        if found:
            counts = {"passed": int(found.group(1)), "cached": int(found.group(2)),
                      "failed": int(found.group(3)), "skipped": int(found.group(4))}
            continue
        found = VERDICT.match(line.strip())
        if found:
            verdicts[found.group(2)] = found.group(1)
    return counts, verdicts


def run_suite(name, options):
    """Run one suite in both arms and compare."""
    entry, extra = SUITES[name]
    arguments = [*extra, "--jobs", str(options.inner_jobs)]
    outcome = {"entry": entry, "arguments": arguments, "arms": {}}
    for arm, tool in (("qbe", None), ("llvm", str(ADAPTER))):
        cache = options.work / f"cache-{name}-{arm}"
        command = [str(options.mylang), "test", entry, f"--cache-dir={cache}", *arguments]
        if tool is not None:
            command.append(f"--qbe={tool}")
        done = subprocess.run(command, capture_output=True, text=True, timeout=7200,
                              cwd=REPO)
        counts, verdicts = parse(done.stdout)
        outcome["arms"][arm] = {
            "command": " ".join(command), "status": done.returncode,
            "counts": counts, "verdicts": verdicts,
            "stdout": done.stdout[-6000:], "stderr": done.stderr[-6000:],
        }
    left, right = outcome["arms"]["qbe"], outcome["arms"]["llvm"]
    failures = []
    if left["counts"] != right["counts"]:
        failures.append({"counts": True, "qbe": left["counts"], "llvm": right["counts"]})
    for key in sorted(set(left["verdicts"]) | set(right["verdicts"])):
        if left["verdicts"].get(key) != right["verdicts"].get(key):
            failures.append({"test": key, "qbe": left["verdicts"].get(key),
                             "llvm": right["verdicts"].get(key)})
    if left["status"] != right["status"]:
        failures.append({"status": True, "qbe": left["status"], "llvm": right["status"]})
    outcome["failures"] = failures
    outcome["passed"] = not failures
    return name, outcome


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mylang", default=str(REPO / "zig-out" / "bin" / "mylang"))
    parser.add_argument("--work", default="/tmp/llvm-qual-equiv")
    parser.add_argument("--json", dest="out")
    parser.add_argument("--only")
    parser.add_argument("--jobs", type=int, default=3, help="suites compared at once")
    parser.add_argument("--inner-jobs", type=int, default=2,
                        help="test children per suite; 1 is the race-free setting")
    options = parser.parse_args()
    options.mylang = Path(options.mylang)
    options.work = Path(options.work)
    options.work.mkdir(parents=True, exist_ok=True)

    names = [options.only] if options.only else sorted(SUITES)
    report = {"tool": "qualify_equiv.py", "work": str(options.work), "suites": {},
              "identity_start": identity(options.mylang),
              "compiler_sha256": hashlib.sha256(options.mylang.read_bytes()).hexdigest(),
              "adapter_sources": {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                                  for path in sorted(HERE.glob("*.py"))}}
    total = failures = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=options.jobs) as pool:
        futures = [pool.submit(run_suite, name, options) for name in names]
        for future in concurrent.futures.as_completed(futures):
            name, outcome = future.result()
            report["suites"][name] = outcome
            total += 1
            failures += 0 if outcome["passed"] else 1
            qbe, llvm = outcome["arms"]["qbe"], outcome["arms"]["llvm"]
            print(f"{name:14s} qbe={qbe['counts']} status={qbe['status']}   "
                  f"llvm={llvm['counts']} status={llvm['status']}", flush=True)
            for failure in outcome["failures"][:20]:
                print(f"    {json.dumps(failure)[:300]}", flush=True)
    report.update({"suites_run": total, "suites_with_differences": failures,
                   "identity_end": identity(options.mylang)})
    print(f"\n{total} suite comparisons, {failures} with differences")
    if options.out:
        Path(options.out).write_text(json.dumps(report, indent=1) + "\n")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

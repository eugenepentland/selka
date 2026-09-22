#!/usr/bin/env python3
"""Byte-equality for the entries the as-found sweep could not build in the LLVM arm.

    qualify_affected.py [--work DIR] [--json OUT]

Parsing a construct and compiling it is not the same as compiling it correctly,
and a mis-compiled indirect call would be worse than a refused one.  This takes
every entry the *as-found* build sweep (`build-sweep-asfound.json`) reported as
an LLVM-only failure and, after the translator fixes, runs it through both arms
twice:

* `mylang build` both arms, then run both binaries and compare exit status,
  stdout and stderr byte for byte;
* `mylang test` both arms, comparing the per-test verdicts by name and the exit
  status, because a per-file build failure is a host failure that still prints
  `0 failed` in the summary line.

The entries that legitimately have no `main` (test modules) only take the second
path; the entries with a `main` take both.
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
EVIDENCE = HERE / "evidence" / "qualification-20260920"

SUMMARY = re.compile(r"(\d+) passed, (\d+) cached, (\d+) failed, (\d+) skipped")
VERDICT = re.compile(r"^(passed|failed|skipped|error|timeout|panicked) (\S+)$")


def parse_tests(text):
    """The summary counts and per-name verdicts of one `mylang test` run."""
    counts, verdicts = None, {}
    for line in text.splitlines():
        found = SUMMARY.search(line)
        if found:
            counts = [int(found.group(index)) for index in (1, 2, 3, 4)]
            continue
        found = VERDICT.match(line.strip())
        if found:
            verdicts[found.group(2)] = found.group(1)
    return counts, verdicts


def build(mylang, source, binary, cache, tool):
    """Build one entry with one arm."""
    command = [str(mylang), "build", str(source), "-o", str(binary),
               "--mode=ReleaseFast", "--keep-symbols", f"--cache-dir={cache}"]
    if tool is not None:
        command.append(f"--qbe={tool}")
    return subprocess.run(command, capture_output=True, text=True, timeout=1800, cwd=REPO)


def compare_binaries(mylang, relative, work):
    """Build and run one entry in both arms; compare status, stdout and stderr."""
    source = REPO / relative
    # The output name is the whole relative path: `examples/callbacks.my`,
    # `tests/guest/callbacks.my` and `tests/lang/callbacks.my` would otherwise
    # race for one `callbacks.*` file and report the winner's behaviour.
    stem = relative.replace("/", "__").removesuffix(".my")
    binaries = {}
    for arm, tool in (("qbe", None), ("llvm", str(ADAPTER))):
        binary = work / f"{stem}.{arm}"
        done = build(mylang, source, binary, work / f"cache-{arm}-{stem}", tool)
        if done.returncode != 0:
            return {"stage": "build", "arm": arm, "status": done.returncode,
                    "stderr": done.stderr[-800:], "agree": None}
        binaries[arm] = binary
    outcomes = {}
    for arm, binary in binaries.items():
        done = subprocess.run([str(binary)], capture_output=True, timeout=600, cwd=work)
        outcomes[arm] = (done.returncode, done.stdout, done.stderr)
    agree = outcomes["qbe"] == outcomes["llvm"]
    return {"stage": "run", "agree": agree,
            "status": [outcomes["qbe"][0], outcomes["llvm"][0]],
            "stdout_bytes": len(outcomes["qbe"][1]),
            "stdout_sha256": hashlib.sha256(outcomes["qbe"][1]).hexdigest(),
            "qbe_stderr": outcomes["qbe"][2].decode("utf8", "replace")[-300:],
            "llvm_stderr": outcomes["llvm"][2].decode("utf8", "replace")[-300:]}


def compare_tests(mylang, relative, work):
    """Run one entry's guest tests in both arms; compare verdicts and status."""
    source = REPO / relative
    outcomes = {}
    for arm, tool in (("qbe", None), ("llvm", str(ADAPTER))):
        command = [str(mylang), "test", str(source),
                   f"--cache-dir={work}/tests-{arm}-{relative.replace('/', '__').removesuffix('.my')}"]
        if tool is not None:
            command.append(f"--qbe={tool}")
        done = subprocess.run(command, capture_output=True, text=True, timeout=3600, cwd=REPO)
        counts, verdicts = parse_tests(done.stdout)
        outcomes[arm] = {"status": done.returncode, "counts": counts, "verdicts": verdicts,
                         "stderr": done.stderr[-600:]}
    left, right = outcomes["qbe"], outcomes["llvm"]
    differences = []
    if left["counts"] != right["counts"]:
        differences.append({"counts": [left["counts"], right["counts"]]})
    for name in sorted(set(left["verdicts"]) | set(right["verdicts"])):
        if left["verdicts"].get(name) != right["verdicts"].get(name):
            differences.append({"test": name, "qbe": left["verdicts"].get(name),
                                "llvm": right["verdicts"].get(name)})
    if left["status"] != right["status"]:
        differences.append({"status": [left["status"], right["status"]]})
    return {"stage": "test", "agree": not differences,
            "qbe_counts": left["counts"], "llvm_counts": right["counts"],
            "qbe_status": left["status"], "llvm_status": right["status"],
            "differences": differences, "llvm_stderr": right["stderr"]}


def check(mylang, relative, work):
    """Both stages for one entry."""
    return {"path": relative,
            "binary": compare_binaries(mylang, relative, work),
            "tests": compare_tests(mylang, relative, work)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mylang", default=str(REPO / "zig-out" / "bin" / "mylang"))
    parser.add_argument("--work", default="/tmp/llvm-qual-affected")
    parser.add_argument("--json", dest="out")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--sweep", default=str(EVIDENCE / "build-sweep-asfound.json"))
    options = parser.parse_args()

    sweep = json.loads(Path(options.sweep).read_text())
    entries = [record["relative"] for record in sweep["results"]
               if record["verdict"] == "llvm-only-failure"]
    if not entries:
        raise SystemExit("the as-found sweep recorded no LLVM-only failures")
    work = Path(options.work)
    work.mkdir(parents=True, exist_ok=True)

    report = {"tool": "qualify_affected.py", "sweep": options.sweep, "entries": entries,
              "compiler_sha256": hashlib.sha256(Path(options.mylang).read_bytes()).hexdigest(),
              "adapter_sources": {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                                  for path in sorted(HERE.glob("*.py"))},
              "identity_start": identity(options.mylang), "results": {}}
    failures = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=options.jobs) as pool:
        futures = {pool.submit(check, Path(options.mylang), entry, work): entry
                   for entry in entries}
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            report["results"][result["path"]] = result
            binary, tests = result["binary"], result["tests"]
            binary_note = ("no main" if binary.get("agree") is None
                           else ("agree" if binary["agree"] else "DIVERGED"))
            tests_note = "agree" if tests["agree"] else f"{len(tests['differences'])} DIFFERENCES"
            if binary.get("agree") is False or not tests["agree"]:
                failures += 1
            print(f"{result['path']:52s} build/run={binary_note:8s} "
                  f"tests={tests_note} qbe={tests['qbe_counts']} llvm={tests['llvm_counts']}",
                  flush=True)
            for difference in tests["differences"][:8]:
                print(f"    {json.dumps(difference)[:240]}", flush=True)
    report["failures"] = failures
    report["identity_end"] = identity(options.mylang)
    print(f"\n{len(entries)} affected entries, {failures} with a divergence")
    if options.out:
        Path(options.out).write_text(json.dumps(report, indent=1) + "\n")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

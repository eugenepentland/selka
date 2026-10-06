#!/usr/bin/env python3
"""Run S2-X's four old-core gates once on the coordinator's frozen source.

Each command holds both gate and build locks. Logs retain the exact command,
source commit, exit status, Build Summary, shard RSS and command/admission time.
This full old-core gate does not have test-core's five-minute stop threshold.
Only invoke after the coordinator confirms that integration source is frozen.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time


STEPS = ("test", "test-qbe", "test-qbe-build", "fmt-check")
SHARD_RSS_LIMIT = 2560 * 1024 * 1024
GLOBAL_CACHE = "/home/epentland/ai/canopy/.zig-global-cache"
RETAIN_GATE = '"$@"; result=$?; exit "$result"'


def git(root, *arguments):
    return subprocess.check_output(["git", "-C", str(root), *arguments], text=True).strip()


def source_unchanged(root, commit):
    # Evidence may be committed during qualification, but gate inputs stay fixed.
    paths = ["--", ".", ":!experiments"]
    changed = git(root, "diff", "--name-only", commit, *paths)
    added = git(root, "ls-files", "--others", "--exclude-standard", *paths)
    if changed or added:
        raise RuntimeError("gate inputs differ from the frozen source commit:\n" + changed + "\n" + added)


def bytes_of(display):
    match = re.fullmatch(r"(\d+(?:\.\d+)?)\s*([KMGT]?)(?:i?B)?", display, re.IGNORECASE)
    if not match:
        raise ValueError("unrecognized MaxRSS: " + display)
    return float(match[1]) * 1024 ** ("KMGT".index(match[2].upper()) + 1 if match[2] else 0)


def inspect(report):
    summaries = re.findall(r"^Build Summary: (\d+)/(\d+) steps succeeded([^\n]*)", report, re.MULTILINE)
    rss = []
    for line in report.splitlines():
        match = re.search(r"MaxRSS:\s*(\d+(?:\.\d+)?\s*[KMGT]?(?:i?B)?)", line)
        if match:
            rss.append({"line": line, "display": match[1], "bytes": bytes_of(match[1]),
                        "test_run": "run test" in line})
    errors = []
    if len(summaries) != 1 or summaries[0][0] != summaries[0][1]:
        errors.append("missing or unsuccessful Build Summary")
    # Zig can keep a step green after reporting an RSS overrun. Preserve all
    # samples and reject both oversized test steps and explicit overrun notices.
    if any(sample["test_run"] and sample["bytes"] > SHARD_RSS_LIMIT for sample in rss):
        errors.append("test-run MaxRSS exceeds the 2.5 GiB unit-shard ceiling")
    overruns = [line for line in report.splitlines()
                if re.match(r"error: memory usage peaked at .*\(\d+ bytes\), exceeding the declared upper bound", line)]
    if overruns:
        errors.append("build runner reported an RSS or memory overrun")
    admission = {kind: sum(int(value) for value in re.findall(
        rf"build-slot: {kind} slot \d+ after (\d+)s", report)) for kind in ("gate", "build")}
    return {"build_summaries": [f"{a}/{b} steps succeeded{tail}" for a, b, tail in summaries],
            "maxrss": rss, "rss_overrun_notices": overruns,
            "reported_admission_seconds": admission, "errors": errors}


def execute(root, evidence, env, step, commit):
    source_unchanged(root, commit)
    log = evidence / f"{step}.log"
    duration = evidence / f"{step}-seconds.txt"
    command = ["zig", "build", step, "--summary", "all"]
    timed = ["scripts/build-slot.sh", "build", "--", "/usr/bin/time", "-f", "%e", "-o", str(duration), *command]
    wrapped = ["scripts/build-slot.sh", "gate", "--", "bash", "-c", RETAIN_GATE, "--", *timed]
    started = time.monotonic()
    print(f"S2-X {step}: waiting/running; source={commit}; log={log}", flush=True)
    with log.open("x") as output:
        output.write(f"source_commit={commit}\nroot={root}\n$ {shlex.join(wrapped)}\n")
        for name in ("TMPDIR", "ZIG_LOCAL_CACHE_DIR", "ZIG_GLOBAL_CACHE_DIR"):
            output.write(f"{name}={env[name]}\n")
        output.flush()
        with subprocess.Popen(wrapped, cwd=root, env=env, stdout=output, stderr=subprocess.STDOUT) as process:
            while True:
                try:
                    status = process.wait(timeout=60)
                    break
                except subprocess.TimeoutExpired:
                    print(f"S2-X {step}: elapsed including admission={time.monotonic() - started:.0f}s", flush=True)
        wall = time.monotonic() - started
        measured = float(duration.read_text().splitlines()[-1]) if duration.exists() else None
        output.write(f"\nexit={status} command_seconds={measured} wall_including_admission_seconds={wall:.3f}\n")
    result = inspect(log.read_text())
    result.update(step=step, source_commit=commit, command=command, wrapped_command=wrapped,
                  exit=status, command_seconds=measured, wall_including_admission_seconds=wall,
                  admission_and_wrapper_seconds=None if measured is None else max(0, wall - measured), log=str(log))
    if status:
        result["errors"].append(f"command exited {status}")
    if measured is None:
        result["errors"].append("command timer missing; build admission may have failed")
    try:
        source_unchanged(root, commit)
    except RuntimeError as failure:
        result["errors"].append(str(failure))
    result["qualified"] = not result["errors"]
    print(f"S2-X {step}: exit={status}, command={measured}s, wall={wall:.2f}s, qualified={result['qualified']}", flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, required=True, help="frozen integration worktree")
    parser.add_argument("--evidence", type=Path, required=True, help="new output directory in integration's experiments")
    args = parser.parse_args()
    root, evidence = args.root.resolve(), args.evidence.resolve()
    if not (root / "scripts/build-slot.sh").is_file():
        parser.error("--root must name a mylang worktree")
    if not evidence.is_relative_to(root / "experiments"):
        parser.error("--evidence must be inside integration's experiments directory")
    if evidence.exists() and any(evidence.iterdir()):
        parser.error("evidence directory is not empty; retain the existing run without overwriting it")
    commit = git(root, "rev-parse", "HEAD")
    source_unchanged(root, commit)
    evidence.mkdir(parents=True, exist_ok=True)
    # NATIVE-ZIG-CACHE-4 requires test subprocess scratch outside .zig-cache.
    cache = root / ".mylang-cache/s2-x/full-gates" / evidence.name
    (cache / "tmp").mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(TMPDIR=str(cache / "tmp"), ZIG_LOCAL_CACHE_DIR=str(root / ".zig-cache"),
               ZIG_GLOBAL_CACHE_DIR=GLOBAL_CACHE)
    summary = {"source_commit": commit, "root": str(root), "expected_steps": list(STEPS),
               "unit_shard_rss_limit_bytes": SHARD_RSS_LIMIT, "results": [],
               "complete": False, "qualified": False, "error": None}
    try:
        for step in STEPS:
            result = execute(root, evidence, env, step, commit)
            summary["results"].append(result)
            if not result["qualified"]:
                raise RuntimeError(f"{step} did not qualify: " + "; ".join(result["errors"]))
        summary["complete"] = True
        summary["qualified"] = True
    except (RuntimeError, ValueError, OSError, subprocess.SubprocessError) as failure:
        summary["error"] = f"{type(failure).__name__}: {failure}"
        print(summary["error"], file=sys.stderr, flush=True)
    finally:
        (evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    return 0 if summary["qualified"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

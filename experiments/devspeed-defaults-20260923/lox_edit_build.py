#!/usr/bin/env python3
"""Time the Lox port's cold, no-op and edit -> build loop for each build arm.

usage: lox_edit_build.py MYLANG PORT_DIR WORK_DIR OUT_JSON [--rounds N] [--arms qbe,debug,release]

Arms: `qbe` is the plain `mylang build` (the new default: ReleaseFast on QBE),
`debug` adds `--mode Debug`, `release` adds `--release` (LLVM -O3 + LTO, the old
default). Each arm has its own object cache. The edits are bench.json's four
(`hub_comment`, `leaf_body`, `hub_body`, `hub_interface`): apply, build, revert,
build; the applied build is the edit -> build sample. Timings are wall seconds of
the whole `mylang build` process plus its `--report` phase split.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path

ARMS = {"qbe": [], "debug": ["--mode", "Debug"], "release": ["--release"]}


def build(mylang, port, work, arm):
    output = work / f"out-{arm}" / "lox"
    output.parent.mkdir(parents=True, exist_ok=True)
    argv = [mylang, "build", "main.my", "--project", "-o", str(output), "--cache-dir", str(work / f"cache-{arm}"), "--report", *ARMS[arm]]
    start = time.perf_counter()
    done = subprocess.run(argv, cwd=port, capture_output=True, text=True)
    wall = time.perf_counter() - start
    if done.returncode != 0:
        raise SystemExit(f"{arm}: build failed ({done.returncode})\n{done.stderr[-3000:]}")
    report = {}
    for line in done.stdout.splitlines():
        if line.startswith("{") and "qbe-build-v1" in line:
            report = json.loads(line)
    phases = {key: round(report.get(key, 0.0), 3) for key in ("frontend_seconds", "codegen_seconds", "link_seconds")}
    return {"wall": round(wall, 3), **phases, "compiled": report.get("compiled_functions"), "backend": report.get("backend"), "lto": report.get("lto")}


def unique(spec, tag):
    """The same edit with its new names (or its new comment) made unique to `tag`,
    so every round compiles a function no earlier round left in the cache."""
    replace = spec["replace"]
    for name in ("same", "seconds", "values_not_equal"):
        replace = re.sub(rf"\b{name}\b", f"{name}_{tag}", replace)
    replace = replace.replace("(Lox has no other falsey values.)", f"(Lox has no other falsey values; {tag}.)")
    return {**spec, "replace": replace}


def edit(port, spec, apply):
    path = port / spec["file"]
    text = path.read_text()
    old, new = (spec["find"], spec["replace"]) if apply else (spec["replace"], spec["find"])
    if text.count(old) != 1:
        raise SystemExit(f"edit {spec} does not apply exactly once")
    path.write_text(text.replace(old, new))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mylang")
    parser.add_argument("port", type=Path)
    parser.add_argument("work", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--arms", default="qbe,debug,release")
    opts = parser.parse_args()
    edits = json.loads((opts.port / "bench.json").read_text())["edits"]
    opts.work.mkdir(parents=True, exist_ok=True)
    result = {"load_before": os.getloadavg(), "arms": {}}
    for arm in opts.arms.split(","):
        shutil.rmtree(opts.work / f"cache-{arm}", ignore_errors=True)
        record = {"cold": build(opts.mylang, opts.port, opts.work, arm)}
        record["noop"] = [build(opts.mylang, opts.port, opts.work, arm) for _ in range(opts.rounds)]
        record["edits"] = {}
        for name, spec in edits.items():
            samples = []
            for index in range(opts.rounds):
                fresh = unique(spec, f"r{index}")
                edit(opts.port, fresh, True)
                try:
                    samples.append(build(opts.mylang, opts.port, opts.work, arm))
                finally:
                    edit(opts.port, fresh, False)
                build(opts.mylang, opts.port, opts.work, arm)
            record["edits"][name] = samples
        result["arms"][arm] = record
        print(arm, "cold", record["cold"]["wall"], "noop", min(s["wall"] for s in record["noop"]),
              {name: min(s["wall"] for s in samples) for name, samples in record["edits"].items()}, flush=True)
    result["load_after"] = os.getloadavg()
    opts.out.write_text(json.dumps(result, indent=1) + "\n")


if __name__ == "__main__":
    main()

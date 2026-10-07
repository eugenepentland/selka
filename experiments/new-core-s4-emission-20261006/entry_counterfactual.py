#!/usr/bin/env python3
"""LLVM-only experiment: preserve signatures while exposing the proven stdout token."""
import argparse
import fcntl
import hashlib
import json
import random
import re
import subprocess
from pathlib import Path
from types import SimpleNamespace
import paired_units as paired


def identity(path):
    return {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--whole", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    area = args.evidence.resolve()
    area.relative_to(paired.ROOT / "experiments")
    area.mkdir(exist_ok=False)
    modules = sorted((args.input / "cache/lox_eval").glob("program-*/*.ll"))
    runtime = paired.unique(args.input / "cache/lox_eval", "core_rt-*.o")
    report = {"production_change": False, "inputs": [identity(path) for path in modules],
              "runtime": identity(runtime), "arms": {}}
    for arm in ("baseline", "stdout_constant"):
        inputs = area / arm
        inputs.mkdir()
        selected = []
        replacements = 0
        for source in modules:
            text = source.read_text()
            if arm == "stdout_constant":
                pattern = re.compile(r'(define hidden fastcc i64 @"my\.app::main"\([^\n]*\) nounwind uwtable[^\n]*\{\n)(.*?)(^\})', re.MULTILINE | re.DOTALL)
                match = pattern.search(text)
                if match:
                    body, replacements = re.subn(r'%p2\b', '1', match[2])
                    text = text[:match.start(2)] + body + text[match.end(2):]
            target = inputs / source.name
            target.write_text(text)
            selected.append(target)
        if arm == "stdout_constant" and replacements == 0:
            raise ValueError("entry stdout substitution did not match actual LLVM")
        output = inputs / "program"
        argv = ["zig", "cc", "-O3", *paired.rows.CPU_FLAGS, "-Wno-override-module", "-o", str(output),
                *map(str, selected), str(runtime), str(paired.ROOT / "benchmarks/runtime/ports/native_clock.c")]
        paired.run_build(argv, inputs / "compile.log")
        report["arms"][arm] = {"argv": argv, "replacements": replacements,
                               "inputs": [identity(path) for path in selected], "binary": identity(output)}
    with Path("/run/user/1000/mylang-slots/cpu10.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        report["measurement"] = paired.comparison(SimpleNamespace(rounds=7), "lox_eval", {
            "whole": args.whole,
            "baseline": area / "baseline/program",
            "stdout_constant": area / "stdout_constant/program",
        }, random.Random(81924))
    (area / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    for size, row in report["measurement"]["sizes"].items():
        print(size, row["comparisons"], flush=True)


if __name__ == "__main__":
    main()

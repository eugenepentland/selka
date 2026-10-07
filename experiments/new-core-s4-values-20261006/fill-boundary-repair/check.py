#!/usr/bin/env python3
"""Retain native evidence for the counted fill's post-loop append regression."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[3]
AREA = Path(__file__).resolve().parent
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--core", type=Path, required=True)
p.add_argument("--label", choices=("red", "green"), required=True)
a = p.parse_args()
old = ROOT / ".mylang-cache/s4-v/immutable-final-checker/mylang"
core = a.core.resolve()
source = AREA / "repro.my"
records = []
summary = {"source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "qualified": False, "records": records}
modes = (("old-debug", old, ()), ("old-release", old, ("--release",)),
         ("new-debug", core, ()), ("new-release", core, ("--release",)),
         ("new-verify", core, ("--release", "--verify-facts")))
try:
    for role, compiler, flags in modes:
        argv = [str(compiler), "test", str(source), "--json", "--cache-dir",
                str(ROOT / ".mylang-cache/s4-v/fill-boundary-repair" / a.label / role), *flags]
        done = subprocess.run(argv, text=True, capture_output=True, timeout=120,
                              env={**os.environ, "MYL_CORE_LEAKCHECK": "1"})
        log = AREA / (a.label + "-" + role + ".log")
        with log.open("x") as out:
            out.write("$ " + shlex.join(argv) + "\nstdout=" + repr(done.stdout) +
                      "\nstderr=" + repr(done.stderr) + "\nexit=" + str(done.returncode) + "\n")
        report = json.loads(done.stdout) if done.stdout else None
        records.append({"role": role, "compiler_sha256": hashlib.sha256(compiler.read_bytes()).hexdigest(),
                        "exit": done.returncode, "report": report, "stderr": done.stderr})
        print(role + " exit=" + str(done.returncode) + " report=" + json.dumps(report), flush=True)
    assert all(item["exit"] == 0 and item["report"]["passed"] == 1 and item["stderr"] == "" for item in records[:-1])
    last = records[-1]
    if a.label == "red":
        assert last["exit"] == 1 and last["report"]["failed"] == 1
        summary["reduced_before_fix"] = True
    else:
        assert last["exit"] == 0 and last["report"]["passed"] == 1 and last["stderr"] == ""
    summary["qualified"] = True
finally:
    (AREA / (a.label + "-summary.json")).write_text(json.dumps(summary, indent=2) + "\n")

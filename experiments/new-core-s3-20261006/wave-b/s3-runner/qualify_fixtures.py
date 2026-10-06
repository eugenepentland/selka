#!/usr/bin/env python3
"""Execute actual old/Core trials; preserve one log and status per invocation."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--old", required=True)
    parser.add_argument("--core", required=True)
    parser.add_argument("--run", required=True)
    parser.add_argument("--only", action="append")
    args = parser.parse_args()
    cases = [
        ("properties", "c_runner_properties.my", 0, None, 7),
        ("failures", "c_runner_failures.my", 1, None, 7),
        ("standins", "c_runner_standins.my", 0, None, 7),
        ("state", "c_runner_state_capture.my", 1, None, 7),
        ("signal", "c_runner_signal.my", 1, "signal", 7),
        ("exit", "c_runner_signal.my", 1, "exit", 7),
        ("name-seed", "c_runner_state_capture.my", 1, None, None),
    ]
    rows = []
    pairs = []
    environment = dict(os.environ, MYL_CORE_LEAKCHECK="1")
    for case, fixture, status, helper, seed in cases:
        if args.only and case not in args.only:
            continue
        logs = []
        for kind, executable in (("old", args.old), ("core", args.core)):
            log = HERE / "logs" / f"final-{args.run}-{case}-{kind}.txt"
            if log.exists():
                raise ValueError(f"refusing to overwrite {log}")
            argv = [str(Path(executable).resolve()), "test", f"test/core/{fixture}", "--json", "--property-runs", "12", "--cache-dir", str(ROOT / ".mylang-cache/s3-runner" / f"final-{args.run}-{case}-{kind}")]
            if seed is not None:
                argv += ["--seed", str(seed)]
            argv += ["--release", "--verify-facts"] if kind == "core" else ["--mode", "ReleaseFast"]
            if helper:
                path = ROOT / ".mylang-cache/s3-runner" / f"c-{helper}-pic.o" if kind == "old" else HERE / f"c_runner_{helper}.c"
                argv += ["--link", str(path)]
            started = time.monotonic()
            with log.open("x") as output:
                done = subprocess.run(argv, cwd=ROOT, env=environment, stdout=output, stderr=subprocess.STDOUT, timeout=180)
            row = {"case": case, "compiler": kind, "argv": argv, "status": done.returncode, "expected_status": status, "seconds": time.monotonic() - started, "log": str(log)}
            rows.append(row)
            print(json.dumps(row), flush=True)
            if done.returncode != status:
                raise ValueError(f"unexpected status for {case}/{kind}: {done.returncode}")
            logs.append(str(log))
        pairs += ["--pair", *logs]
    compiler_hashes = {kind: hashlib.sha256(Path(path).read_bytes()).hexdigest() for kind, path in (("old", args.old), ("core", args.core))}
    evidence = HERE / f"final-{args.run}-commands.json"
    evidence.write_text(json.dumps({"compilers": compiler_hashes, "commands": rows}, indent=2) + "\n")
    return subprocess.run(["python3", str(HERE / "compare_reports.py"), *pairs, "--output", str(HERE / f"final-{args.run}-comparison.json")], cwd=ROOT).returncode


if __name__ == "__main__":
    raise SystemExit(main())

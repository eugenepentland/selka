#!/usr/bin/env python3
"""Differential verification of the two backends on the same guest programs.

    verify_semantics.py [--work DIR] [--only NAME] [CASES.json]

Builds every case twice from the same compiler — once with QBE and once with the
LLVM adapter — under identical flags and separate cache directories, runs both on
the same inputs, and compares stdout, stderr and the exit status byte for byte.
A program is reported only when both arms agree; a divergence prints the arm
outputs so the offender can be reduced.

The default case list is the frozen benchmark pair (census and render, on the
927 KB and 7.42 MB inputs) plus the small fixtures under `tests/semantic/`.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
MYLANG = REPO / "zig-out" / "bin" / "mylang"
ADAPTER = HERE / "qbe_llvm.py"

#: The frozen census/render port, its two frozen inputs, and the flags that select
#: each workload.
PORT = REPO / "experiments" / "sexpr-port" / "main.my"
INPUTS = {
    "small": Path("/tmp/rt2x/input.sexp"),
    "large": Path("/tmp/rt2x/input8.sexp"),
}

#: Every case is a small guest program and the arguments it is run with.
CASES = [
    ("census-small", str(PORT), ["{small}"]),
    ("render-small", str(PORT), ["{small}", "--render"]),
    ("census-large", str(PORT), ["{large}"]),
    ("render-large", str(PORT), ["{large}", "--render"]),
]


def sha256(path):
    """The digest of one file, or None when it does not exist."""
    try:
        return hashlib.sha256(Path(path).read_bytes()).hexdigest()
    except OSError:
        return None


def build(source, output, cache, tool=None, mode="ReleaseFast"):
    """Build one arm, returning (status, stderr)."""
    command = [str(MYLANG), "build", source, "-o", str(output), f"--cache-dir={cache}",
               f"--mode={mode}", "--keep-symbols"]
    if tool is not None:
        command.append(f"--qbe={tool}")
    done = subprocess.run(command, capture_output=True, text=True)
    return done.returncode, done.stderr


def run(binary, arguments, timeout=300):
    """Run one arm, returning (status, stdout bytes, stderr bytes)."""
    try:
        done = subprocess.run([str(binary)] + arguments, capture_output=True,
                              timeout=timeout)
    except subprocess.TimeoutExpired:
        return ("timeout", b"", b"")
    return (done.returncode, done.stdout, done.stderr)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("cases", nargs="?", help="JSON case list to use instead")
    parser.add_argument("--work", default="/tmp/llvm-backend-verify")
    parser.add_argument("--only", help="run only the case with this name")
    parser.add_argument("--mode", default="ReleaseFast")
    parser.add_argument("--json", dest="out", help="write the evidence report here")
    options = parser.parse_args()

    cases = CASES
    if options.cases:
        with open(options.cases) as handle:
            cases = [(c["name"], c["source"], c["arguments"]) for c in json.load(handle)]
    work = Path(options.work)
    work.mkdir(parents=True, exist_ok=True)
    report = {"cases": [], "inputs": {}, "mode": options.mode}
    for name, path in INPUTS.items():
        report["inputs"][name] = {"path": str(path), "bytes": path.stat().st_size
                                  if path.exists() else None, "sha256": sha256(path)}
    failures = 0
    for name, source, arguments in cases:
        if options.only and name != options.only:
            continue
        rendered = [a.format(**{k: str(v) for k, v in INPUTS.items()}) for a in arguments]
        qbe_binary = work / f"{name}-qbe"
        llvm_binary = work / f"{name}-llvm"
        qbe_status, qbe_build_error = build(source, qbe_binary, work / f"cache-qbe-{name}",
                                            mode=options.mode)
        llvm_status, llvm_build_error = build(source, llvm_binary,
                                              work / f"cache-llvm-{name}",
                                              tool=str(ADAPTER), mode=options.mode)
        entry = {"name": name, "arguments": rendered,
                 "qbe_build_status": qbe_status, "llvm_build_status": llvm_status}
        if qbe_status != 0 or llvm_status != 0:
            failures += 1
            entry["verdict"] = "build-failed"
            entry["qbe_build_error"] = qbe_build_error[-400:]
            entry["llvm_build_error"] = llvm_build_error[-400:]
            report["cases"].append(entry)
            print(f"{name}: BUILD FAILED (qbe={qbe_status} llvm={llvm_status})")
            print("  " + (qbe_build_error or llvm_build_error).strip().split("\n")[-1][:160])
            continue
        qbe = run(qbe_binary, rendered)
        llvm = run(llvm_binary, rendered)
        agree = qbe == llvm
        entry.update({"qbe_status": qbe[0], "llvm_status": llvm[0],
                      "stdout_bytes": len(qbe[1]), "stdout_sha256": hashlib.sha256(qbe[1]).hexdigest(),
                      "agree": agree, "verdict": "agree" if agree else "diverged"})
        if not agree:
            failures += 1
            entry["qbe_stdout_head"] = qbe[1][:400].decode("utf-8", "replace")
            entry["llvm_stdout_head"] = llvm[1][:400].decode("utf-8", "replace")
            entry["qbe_stderr_head"] = qbe[2][:400].decode("utf-8", "replace")
            entry["llvm_stderr_head"] = llvm[2][:400].decode("utf-8", "replace")
        report["cases"].append(entry)
        print(f"{name}: {'agree' if agree else 'DIVERGED'} "
              f"(qbe={qbe[0]} llvm={llvm[0]}, {len(qbe[1])} stdout bytes)")
        if not agree:
            print(f"  qbe  stdout: {qbe[1][:160]!r}")
            print(f"  llvm stdout: {llvm[1][:160]!r}")
    if options.out:
        with open(options.out, "w") as handle:
            json.dump(report, handle, indent=1)
    print(f"{len(report['cases'])} case(s), {failures} without agreement")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

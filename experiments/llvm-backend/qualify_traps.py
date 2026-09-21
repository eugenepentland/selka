#!/usr/bin/env python3
"""Differential trap, GC-stress and exit-status matrix between the two arms.

    qualify_traps.py [--work DIR] [--jobs N] [--json OUT] [--only NAME]

Every probe is built by both backends from the same compiler with the same
flags, then each binary is run plain and under `--gc-stress`, and the two arms
must agree on stdout, stderr and the exit status byte for byte.  A probe that
declares an expected trap code must actually produce it in *both* arms, so
"both arms agree" cannot be satisfied by two identical silent successes — the
failure mode a plain diff misses.

The probes under `evidence/qualification-20260920/probes/` exist because the
historical `trapdiff` set does not reach every trap code the language defines:
`R_BYTE_RANGE`, `R_OUTPUT`, `R_MEMORY_BUDGET`, `R_FILE`, `R_TEXT_BOUNDS`,
`R_INVALID_SHIFT` and a nonzero `main` status had no fixture there.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

from qualify_identity import identity

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
ADAPTER = HERE / "qbe_llvm.py"
PROBES = REPO / "experiments" / "llvm-backend" / "evidence" / "qualification-20260920" / "probes"

#: probe -> the trap code its stderr must carry, and any build/run arguments.
#: `run_env` is added to the child's environment; `setup` names a run arrangement
#: the plain subprocess call cannot express.
CASES = {
    "okay": {"expect": None},
    "trap_list_bounds": {"expect": "R_LIST_BOUNDS"},
    "trap_text_bounds": {"expect": "R_TEXT_BOUNDS"},
    "trap_overflow": {"expect": "R_OVERFLOW"},
    "trap_division": {"expect": "R_DIVISION_BY_ZERO"},
    "trap_remainder": {"expect": "R_DIVISION_BY_ZERO"},
    "trap_cast": {"expect": "R_OVERFLOW"},
    "trap_float_conversion": {"expect": "R_FLOAT_CONVERSION"},
    "trap_byte_range": {"expect": "R_BYTE_RANGE"},
    "trap_assert": {"expect": "R_ASSERT"},
    "trap_shift": {"expect": "R_INVALID_SHIFT"},
    "trap_output": {"expect": "R_OUTPUT", "setup": "closed-stdout"},
    "trap_file": {"expect": "R_FILE"},
    "trap_memory_budget": {"expect": "R_MEMORY_BUDGET",
                           "run_env": {"MYLANG_MEMORY_LIMIT": "32M"}},
    "trap_step_limit": {"expect": "R_STEP_LIMIT", "arguments": ["--max-steps=500"]},
    "trap_frame_limit": {"expect": "R_FRAME_LIMIT", "arguments": ["--max-frames=3"]},
    "exit_status": {"expect": None, "status": 300 & 0xFF},
    "exit_status_negative": {"expect": None, "status": (-1) & 0xFF},
}

#: (label, mode) pairs every probe is built in.
BUILDS = (("fast", "ReleaseFast"), ("debug", "Debug"))


def build(mylang, source, binary, mode, tool, cache, arguments):
    """Build one probe with one arm, returning the completed process."""
    command = [str(mylang), "build", str(source), "-o", str(binary), f"--mode={mode}",
               f"--cache-dir={cache}", "--keep-symbols", *arguments]
    if tool is not None:
        command.append(f"--qbe={tool}")
    return subprocess.run(command, capture_output=True, text=True, timeout=900)


def run(binary, arguments, case, cwd, stress=False):
    """Run one arm, returning (status, stdout, stderr)."""
    environment = dict(os.environ)
    environment.update(case.get("run_env", {}))
    command = [str(binary), *case.get("arguments", []), *arguments]
    if stress:
        command.append("--gc-stress")
    if case.get("setup") == "closed-stdout":
        # `fwrite` to a closed descriptor fails, which is what R_OUTPUT reports.
        done = subprocess.run(["sh", "-c", 'exec "$0" "$@" 1>&-', *command],
                              capture_output=True, timeout=300, cwd=cwd, env=environment)
    else:
        done = subprocess.run(command, capture_output=True, timeout=300, cwd=cwd,
                              env=environment)
    return done.returncode, done.stdout, done.stderr


def check_probe(name, mylang, work):
    """Build and compare one probe in both arms, plain and under GC stress."""
    case = CASES[name]
    arguments = case.get("arguments", [])
    source = PROBES / f"{name}.my"
    checks, failures, results = 0, [], []
    cwd = work / "cwd"
    cwd.mkdir(exist_ok=True)
    for label, mode in BUILDS:
        binaries = {}
        for arm, tool in (("qbe", None), ("llvm", str(ADAPTER))):
            binary = work / f"{name}.{label}.{arm}"
            done = build(mylang, source, binary, mode, tool,
                         work / f"cache-{arm}-{name}-{label}", arguments)
            if done.returncode != 0:
                failures.append({"build": arm, "mode": label, "status": done.returncode,
                                 "stderr": done.stderr[-1200:]})
            else:
                binaries[arm] = binary
        if len(binaries) != 2:
            continue
        outcomes = {}
        for arm, binary in binaries.items():
            outcomes[arm] = {stage: run(binary, [], case, cwd, stress=stage == "stress")
                             for stage in ("plain", "stress")}
            status, _, stderr = outcomes[arm]["plain"]
            text = stderr.decode("utf8", "replace")
            if case["expect"] and case["expect"] not in text:
                failures.append({"missing-trap": arm, "mode": label,
                                 "expected": case["expect"], "status": status,
                                 "stderr": text[-600:]})
            if "status" in case and status != case["status"]:
                failures.append({"wrong-status": arm, "mode": label,
                                 "expected": case["status"], "actual": status})
            if "R_NO_FRAME_ACCOUNTING" in text or "R_NO_STEP_ACCOUNTING" in text:
                failures.append({"accounting": arm, "mode": label, "stderr": text[-400:]})
        for stage in ("plain", "stress"):
            checks += 1
            left, right = outcomes["qbe"][stage], outcomes["llvm"][stage]
            results.append({"mode": label, "stage": stage, "match": left == right,
                            "qbe": [left[0], left[2].decode("utf8", "replace")[-400:]],
                            "llvm": [right[0], right[2].decode("utf8", "replace")[-400:]]})
            if left != right:
                failures.append({"diverged": stage, "mode": label,
                                 "qbe": repr(left)[:600], "llvm": repr(right)[:600]})
    return name, checks, failures, results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mylang", default=str(REPO / "zig-out" / "bin" / "mylang"))
    parser.add_argument("--work", default="/tmp/llvm-qual-traps")
    parser.add_argument("--jobs", type=int, default=8)
    parser.add_argument("--only")
    parser.add_argument("--json", dest="out")
    options = parser.parse_args()

    work = Path(options.work)
    work.mkdir(parents=True, exist_ok=True)
    names = [options.only] if options.only else sorted(CASES)
    for name in names:
        if name not in CASES:
            raise SystemExit(f"unknown probe {name}")
    report = {"tool": "qualify_traps.py", "work": str(work), "probes": {},
              "adapter_sources": {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                                  for path in sorted(HERE.glob("*.py"))},
              "compiler_sha256": hashlib.sha256(Path(options.mylang).read_bytes()).hexdigest(),
              "identity_start": identity(options.mylang)}
    checks = failures_total = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=options.jobs) as pool:
        futures = [pool.submit(check_probe, name, Path(options.mylang), work) for name in names]
        for future in concurrent.futures.as_completed(futures):
            name, probe_checks, failures, results = future.result()
            report["probes"][name] = {"expect": CASES[name].get("expect"),
                                      "checks": results, "failures": failures}
            checks += probe_checks
            failures_total += len(failures)
            mark = "ok" if not failures else f"{len(failures)} FAILURE"
            print(f"{name:24s} {probe_checks} comparisons  {mark}", flush=True)
            for failure in failures:
                print(f"    {json.dumps(failure)[:400]}")
    report.update({"checks": checks, "failures": failures_total, "probes_run": len(names),
                   "identity_end": identity(options.mylang)})
    print(f"\n{checks} arm comparisons across {len(names)} probes, {failures_total} failures")
    if options.out:
        Path(options.out).write_text(json.dumps(report, indent=1) + "\n")
    return 1 if failures_total else 0


if __name__ == "__main__":
    sys.exit(main())

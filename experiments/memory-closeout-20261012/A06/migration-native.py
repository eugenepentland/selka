#!/usr/bin/env python3
"""Run migrated evaluation-order fixtures against immutable registered C0 oracles."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
C0 = "fbfcaa7a923186a8e773c3760f81c10aa345a432"
spec = importlib.util.spec_from_file_location("qualification", HERE / "qualify.py")
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)
ORACLES = {
    "v_snapshot": ("src/core/value_e2e_test.zig", ["v_snapshot_output"]),
    "v_mut_window": ("src/core/value_e2e_test.zig", ["v_mut_window_output"]),
    "u1_state": ("src/core/u1_state_test.zig", ["state_expected"]),
    "ce2_effects": ("src/core/ce2_effects_test.zig",
                    ["fields_expected", "takes_expected", "stores_expected"]),
}


def oracle(case):
    path, names = ORACLES[case]
    raw = subprocess.check_output(["git", "show", C0 + ":" + path], cwd=ROOT)
    source = raw.decode()
    pieces = []
    for name in names:
        match = re.search(r"(?m)^const " + name + r" = (\".*?\");$", source)
        if match:
            pieces.append(json.loads(match[1]))
            continue
        match = re.search(r"(?m)^const " + name + r" =\n(.*?)^;", source, re.S)
        if not match:
            raise ValueError("missing frozen oracle: " + name)
        lines = [line.strip()[2:] for line in match[1].splitlines()
                 if line.strip().startswith("\\\\")]
        pieces.append("\n".join(lines))
    return {"source": path, "base": C0, "sha256": hashlib.sha256(raw).hexdigest(),
            "constants": names, "stdout": "".join(pieces)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("compiler", "zig", "output"):
        parser.add_argument("--" + key, type=Path, required=True)
    parser.add_argument("--cases", default=",".join(ORACLES))
    parser.add_argument("--modes", default="release")
    parser.add_argument("--ownership", choices=("zero", "default"), default="zero")
    args = parser.parse_args()
    args.compiler, args.zig, args.output = (getattr(args, key).resolve()
                                          for key in ("compiler", "zig", "output"))
    env = dict(os.environ, ZIG=str(args.zig), MYLANG_ZIG=str(args.zig), MYL_CORE_LEAKCHECK="1")
    for key in ("MYLANG_COUNTERS", "MYLANG_OPTIONS", "MYLANG_CORE_SANITIZE"):
        env.pop(key, None)
    report = {"compiler": str(args.compiler), "compiler_sha256": q.digest(args.compiler),
              "zig_sha256": q.digest(args.zig), "harness_sha256": q.digest(__file__),
              "ownership": args.ownership, "cases": {},
              "scope": "Counted correctness only; no runtime or compile-time comparison."}
    failed = False
    for case in args.cases.split(","):
        source = ROOT / "test/core" / (case + ".my")
        expected = oracle(case)
        lanes = report["cases"][case] = {"source_sha256": q.digest(source),
                                        "oracle": expected, "modes": {}}
        for mode in args.modes.split(","):
            directory = args.output / case / mode
            binary, llvm, counts = (directory / name for name in ("program", "program.ll", "counts.json"))
            admission = [] if env.get("MYLANG_ADMISSION_DIR") else [ROOT / "scripts/build-slot.sh", "build"]
            build = q.call([*admission, args.compiler, "build", source, "--zig", args.zig,
                            "--cache-dir", args.output / "cache", *q.MODES[mode],
                            *(["--experimental-zero-rc"] if args.ownership == "zero" else []),
                            "--counters", "-o", binary, "--emit-llvm", llvm], directory, "build", env)
            lane = lanes["modes"][mode] = {"build": build, "admitted": build["status"] == 0}
            if build["status"]:
                failed = True
                print("REFUSED", case, mode, build["stderr"][-1200:], flush=True)
                q.save(args.output / "results.json", report)
                continue
            symbols = subprocess.check_output(["nm", str(binary)], text=True)
            lane.update(binary_sha256=q.digest(binary), llvm_sha256=q.digest(llvm))
            lane["structural_rc_free"] = "mylang-zero-rc-v2" in llvm.read_text() and not any(
                symbol in symbols for symbol in ("myl_core_retain", "myl_core_release", "myl_core_share",
                                                "count_retain", "count_release", "count_is_unique"))
            run = q.call([binary], directory, "run", dict(env, MYLANG_COUNTERS=str(counts)))
            lane["run"] = run
            run["correct"] = run["status"] == 0 and not run["stderr"] and run["stdout"] == expected["stdout"]
            if counts.exists():
                run["audit"] = q.audit.audit(counts)
                run["managed_totals"] = json.loads(counts.read_text())["totals"]
                run["correct"] &= run["audit"]["managed_leak_free"] and run["audit"]["observed_rc_free"]
            else:
                run["correct"] = False
            failed |= not run["correct"] or not lane["structural_rc_free"]
            print("PASS" if run["correct"] and lane["structural_rc_free"] else "FAIL", case, mode, flush=True)
            q.save(args.output / "results.json", report)
    raise SystemExit(1 if failed else 0)


if __name__ == "__main__":
    main()

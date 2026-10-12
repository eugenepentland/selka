#!/usr/bin/env python3
"""Qualify four application shapes; all evidence stays under --output."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MODES = {"release": ["--release"], "debug": ["--unoptimized"],
         "verify": ["--release", "--verify-facts"], "optimized_debug": [],
         "no_facts": ["--release", "--no-facts"]}
spec = importlib.util.spec_from_file_location("audit", ROOT / "experiments/zero-rc-20261011/audit.py")
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n")


def call(command, directory, label, env):
    directory.mkdir(parents=True, exist_ok=True)
    started = time.perf_counter_ns()
    ran = subprocess.run(list(map(str, command)), cwd=ROOT, env=env, capture_output=True, text=True, timeout=1800)
    record = {"argv": list(map(str, command)), "status": ran.returncode,
              "elapsed_ns_including_admission": time.perf_counter_ns() - started,
              "stdout": ran.stdout, "stderr": ran.stderr}
    save(directory / (label + ".json"), record)
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("compiler", "zig", "output"):
        parser.add_argument("--" + key, type=Path, required=True)
    parser.add_argument("--modes", default=",".join(MODES))
    parser.add_argument("--cases", default="word_count,nested_json,file_processing,parallel")
    parser.add_argument("--ownership", choices=("zero", "default", "rc"), default="zero")
    parser.add_argument("--source-version", choices=("original", "migrated"), default="migrated")
    parser.add_argument("--uncounted", action="store_true")
    args = parser.parse_args()
    for key in ("compiler", "zig", "output"):
        setattr(args, key, getattr(args, key).resolve())
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((HERE / "manifest.json").read_text())
    env = dict(os.environ, ZIG=str(args.zig), MYLANG_ZIG=str(args.zig), MYL_CORE_LEAKCHECK="1")
    for key in ("MYLANG_COUNTERS", "MYLANG_OPTIONS", "MYLANG_CORE_SANITIZE"):
        env.pop(key, None)
    report = {"schema": "memory-closeout-applications-v1", "compiler": str(args.compiler),
              "compiler_sha256": digest(args.compiler), "zig_sha256": digest(args.zig),
              "harness_sha256": digest(__file__), "ownership": args.ownership,
              "source_version": args.source_version,
              "counted": not args.uncounted, "cases": {},
              "limitations": ["Build elapsed time includes admission wait and is not compile-time evidence.",
                              "Managed counters do not measure RSS or native provider storage."]}
    failed = False
    for case in args.cases.split(","):
        source = HERE / ("originals/programs" if args.source_version == "original" else "programs") / case / "main.my"
        source_hashes = {str(p.relative_to(HERE)): digest(p) for p in sorted(source.parent.glob("*.my"))}
        if args.source_version == "migrated":
            expected_hashes = manifest["cases"][case]["sources"]
        else:
            migrations = json.loads((HERE / "migration.json").read_text())["sources"]
            expected_hashes = {item["original"]: item["original_sha256"] for item in migrations
                               if Path(item["original"]).parent.name == case}
        if source_hashes != expected_hashes:
            raise ValueError("source changed since manifest freeze: " + case)
        record = report["cases"][case] = {"source_sha256": source_hashes, "modes": {}}
        for mode in args.modes.split(","):
            directory = args.output / case / mode
            directory.mkdir(parents=True, exist_ok=True)
            binary, llvm = directory / "program", directory / "program.ll"
            admission = [] if env.get("MYLANG_ADMISSION_DIR") else [ROOT / "scripts/build-slot.sh", "build"]
            command = [*admission, args.compiler, "build", source,
                       "--zig", args.zig, "--cache-dir", args.output / "cache", *MODES[mode],
                       *(["--experimental-zero-rc"] if args.ownership == "zero" else []),
                       *([] if args.uncounted else ["--counters"]), "-o", binary, "--emit-llvm", llvm]
            build = call(command, directory, "build", env)
            lane = record["modes"][mode] = {"build": build, "admitted": build["status"] == 0, "runs": []}
            if build["status"]:
                failed = True
                print("REFUSED", case, mode, build["stderr"][-1800:], flush=True)
                save(args.output / "results.json", report)
                continue
            lane.update(binary_sha256=digest(binary), llvm_sha256=digest(llvm))
            symbols = subprocess.run(["nm", str(binary)], capture_output=True, text=True, check=True).stdout
            ir = llvm.read_text()
            lane["structural_rc_free"] = "mylang-zero-rc-v2" in ir and not any(
                symbol in symbols or ("@" + symbol + "(") in ir
                for symbol in ("myl_core_retain", "myl_core_release", "myl_core_share"))
            if args.ownership != "rc" and not lane["structural_rc_free"]:
                failed = True
            for size, parameters in manifest["cases"][case]["inputs"].items():
                for threads in ((1, 2, 8) if case == "parallel" else (1,)):
                    label = size + "-threads-" + str(threads)
                    counts = directory / ("counts-" + label + ".json")
                    ran = call([binary, *parameters["args"]], directory, "run-" + label,
                               dict(env, MYLANG_THREADS=str(threads), MYLANG_COUNTERS=str(counts)))
                    ran.update(size=size, threads=threads)
                    ran["correct"] = ran["status"] == 0 and ran["stdout"] == parameters["stdout"] and not ran["stderr"]
                    if not args.uncounted and counts.exists():
                        ran["audit"] = audit.audit(counts)
                        ran["managed_totals"] = json.loads(counts.read_text())["totals"]
                        ran["correct"] &= ran["audit"]["managed_leak_free"]
                        if args.ownership != "rc":
                            ran["correct"] &= ran["audit"]["observed_rc_free"]
                    elif not args.uncounted:
                        ran["correct"] = False
                    failed |= not ran["correct"]
                    lane["runs"].append(ran)
            save(args.output / "results.json", report)
            print("PASS" if all(run["correct"] for run in lane["runs"]) else "FAIL", case, mode, flush=True)
    report["passed"] = not failed
    if report["compiler_sha256"] != digest(args.compiler):
        raise ValueError("compiler changed during qualification")
    save(args.output / "results.json", report)
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())

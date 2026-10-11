#!/usr/bin/env python3
"""Reproduce stage 1 whole-execution qualification against the frozen controls."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import audit
spec = importlib.util.spec_from_file_location("census", HERE.parent / "rc-census-20261010/census.py")
census = importlib.util.module_from_spec(spec)
spec.loader.exec_module(census)
MODES = {"release": ["--release"], "debug": ["--unoptimized"],
         "verify": ["--release", "--verify-facts"], "optimized_debug": [],
         "no_facts": ["--release", "--no-facts"]}
EXTRA = ("15_", "24_", "25_", "26_", "27_", "28_")


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, data):
    path.write_text(json.dumps(data, indent=2) + "\n")


def command(argv, prefix, env):
    prefix.parent.mkdir(parents=True, exist_ok=True)
    start = time.perf_counter_ns()
    ran = subprocess.run(list(map(str, argv)), cwd=ROOT, env=env, capture_output=True, timeout=300)
    elapsed = time.perf_counter_ns() - start
    prefix.with_suffix(".stdout").write_bytes(ran.stdout)
    prefix.with_suffix(".stderr").write_bytes(ran.stderr)
    save(prefix.with_suffix(".command.json"), {"argv": list(map(str, argv)), "status": ran.returncode, "elapsed_ns": elapsed})
    if ran.returncode:
        raise RuntimeError(f"{prefix}: exit {ran.returncode}: {ran.stderr.decode(errors='replace')[:3000]}")
    return ran.stdout.decode()


def clean_ir(path):
    text = path.read_text()
    assert "; mylang-zero-rc-v1" in text
    for line in text.splitlines():
        assert "load atomic i32" not in line, line
        assert not ("store i32" in line and "!tbaa !3" in line), line
        if "call " in line:
            assert not any(name in line for name in ("@myl_core_retain", "@myl_core_release", "@myl_core_share(")), line


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--compiler", type=Path, required=True)
    p.add_argument("--before", type=Path, required=True)
    p.add_argument("--zig", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    args = p.parse_args()
    for key in ("compiler", "before", "zig", "output"):
        setattr(args, key, getattr(args, key).resolve())
    args.output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, MYLANG_ZIG=str(args.zig), ZIG=str(args.zig), MYL_CORE_LEAKCHECK="1")
    env.pop("MYLANG_COUNTERS", None)
    result = {"schema": "zero-rc-stage1-v1", "executions": 0, "cases": {},
              "artifacts": {key: {"path": str(getattr(args, key)), "sha256": digest(getattr(args, key))}
                            for key in ("compiler", "before", "zig")}, "harness_sha256": digest(__file__)}
    baseline = json.loads((HERE.parent / "single-owner-followup-20261011/results.json").read_text())
    for name, lanes in baseline["census"].items():
        control = lanes["single_owner_after"]
        source = ROOT / control["source"]
        migrated = HERE / "migrated" / source.name
        if not migrated.exists():
            migrated = source
        record = {"source": str(migrated.relative_to(ROOT)), "source_sha256": digest(migrated), "configs": {}}
        answers = {n: value["stdout"] for n, value in control["configs"]["release"].items()}
        if name.startswith(EXTRA):
            directory = args.output / name / "extra_baseline"
            directory.mkdir(parents=True, exist_ok=True)
            binary = directory / "program"
            command([args.before, "build", source, "--release", "--experimental-single-owner", "--zig", args.zig,
                     "--cache-dir", args.output / "baseline-cache", "-o", binary], directory / "build", env)
            for n in (0, 64):
                answers[str(n)] = command([binary, *(["x"] * n)], directory / f"run-{n}", env)
        for mode, flags in MODES.items():
            directory = args.output / name / mode
            directory.mkdir(parents=True, exist_ok=True)
            binary, llvm = directory / "program", directory / "program.ll"
            command([args.compiler, "build", migrated, "--experimental-zero-rc", "--zig", args.zig,
                     "--cache-dir", args.output / "cache", "--counters", *flags, "-o", binary,
                     "--emit-llvm", llvm], directory / "build", env)
            clean_ir(llvm)
            runs = {}
            for n, answer in answers.items():
                counts = directory / f"counts-{n}.json"
                stdout = command([binary, *(["x"] * int(n))], directory / f"run-{n}", dict(env, MYLANG_COUNTERS=str(counts)))
                if stdout != answer or (directory / f"run-{n}.stderr").read_bytes():
                    raise RuntimeError(f"{name}/{mode}/{n}: output mismatch")
                checked = audit.audit(counts)
                if not checked["observed_rc_free"] or not checked["managed_leak_free"]:
                    raise RuntimeError(f"{name}/{mode}/{n}: RC or leaked managed memory")
                summary = census.summarize(json.loads(counts.read_text()))
                runs[n] = {"stdout": stdout, "audit": checked, "kernel": summary["kernel"], "whole_program": summary["whole_program"]}
                result["executions"] += 1
            record["configs"][mode] = {"binary_sha256": digest(binary), "llvm_sha256": digest(llvm), "runs": runs}
        if digest(migrated) != record["source_sha256"]:
            raise RuntimeError("source changed during measurement")
        result["cases"][name] = record
        save(args.output / "partial-results.json", result)
        print("pass", name, flush=True)
    result["summary"] = {"supported": len(result["cases"]), "configurations": len(MODES),
                         "zero_rc_executions": result["executions"], "leak_free_executions": result["executions"],
                         "allocating_workloads": {n: sum(bool(record["configs"]["release"]["runs"][n]["kernel"]["allocs"] or
                                                              record["configs"]["release"]["runs"][n]["kernel"]["reallocs"])
                                                         for record in result["cases"].values()) for n in ("4", "11")}}
    for value in result["artifacts"].values():
        assert digest(value["path"]) == value["sha256"], "tool changed during measurement"
    save(HERE / "results.json", result)
    print(json.dumps(result["summary"]), flush=True)


if __name__ == "__main__":
    main()

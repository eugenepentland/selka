#!/usr/bin/env python3
"""Capture exact explicit-copy fixture counters; correctness runs, never timings."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--compiler-sha256", required=True)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--zig", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--mode", action="append")
    parser.add_argument("--expected", default="100 101 4")
    parser.add_argument("--no-trap", action="store_true")
    args = parser.parse_args()
    if os.environ.get("MYLANG_ADMISSION_KIND") != "build":
        parser.error("requires one enclosing build admission")
    if digest(args.compiler) != args.compiler_sha256:
        parser.error("compiler identity changed")
    args.output.mkdir(parents=True, exist_ok=True)
    result_path = args.output / "results.json"
    if result_path.exists():
        parser.error("refusing to overwrite existing evidence")
    modes = {
        "ordinary_default": [],
        "ordinary_unoptimized": ["--unoptimized"],
        "ordinary_release": ["--release"],
        "zero_unoptimized": ["--unoptimized", "--experimental-zero-rc"],
        "zero_release": ["--release", "--experimental-zero-rc"],
        "zero_verify": ["--release", "--verify-facts", "--experimental-zero-rc"],
        "zero_optimized_debug": ["--optimize-debug", "--experimental-zero-rc"],
        "zero_no_facts": ["--release", "--no-facts", "--experimental-zero-rc"],
    }
    if args.mode:
        if any(mode not in modes for mode in args.mode):
            parser.error("unknown mode")
        modes = {mode: modes[mode] for mode in args.mode}
    result = {"revision": args.revision, "compiler": str(args.compiler),
              "compiler_sha256": args.compiler_sha256, "source": str(args.source),
              "source_sha256": digest(args.source), "zig_sha256": digest(args.zig),
              "scope": __doc__, "modes": {}}
    for mode, flags in modes.items():
        directory = args.output / mode
        directory.mkdir()
        binary, llvm = directory / "program", directory / "program.ll"
        argv = [str(args.compiler), "build", str(args.source), "--counters", *flags,
                "--zig", str(args.zig), "--cache-dir", str(args.output / "cache"),
                "-o", str(binary), "--emit-llvm", str(llvm)]
        built = subprocess.run(argv, capture_output=True, text=True)
        (directory / "build.stdout").write_text(built.stdout)
        (directory / "build.stderr").write_text(built.stderr)
        row = {"flags": flags, "build_argv": argv, "build_status": built.returncode, "runs": {}}
        result["modes"][mode] = row
        save(result_path, result)
        if built.returncode:
            print(mode, "build failed", flush=True)
            continue
        row["binary_sha256"] = digest(binary)
        row["llvm_sha256"] = digest(llvm)
        symbols = subprocess.run(["nm", "-a", str(binary)], capture_output=True, text=True, check=True).stdout
        row["legacy_symbols"] = sorted(set(re.findall(r"\b(?:myl_core_retain(?:_slow)?|myl_core_release_slow|count_retain|count_release(?:_shared)?)\b", symbols)))
        runs = [("normal", [])] if args.no_trap else [("normal", []), ("trap", ["trap"])]
        for label, arguments in runs:
            env = dict(os.environ)
            for key in ("MYLANG_OPTIONS", "MYLANG_CORE_SANITIZE", "MYL_CORE_LEAKCHECK"):
                env.pop(key, None)
            counts = directory / f"{label}.json"
            env["MYLANG_COUNTERS"] = str(counts)
            ran = subprocess.run([str(binary), *arguments], capture_output=True, text=True, env=env)
            document = json.loads(counts.read_text()) if counts.exists() else None
            passed = (ran.stdout == args.expected + "\n" and ran.returncode == (1 if arguments else 0)
                      and (("R_LIST_BOUNDS" in ran.stderr) if arguments else ran.stderr == "")
                      and document is not None)
            row["runs"][label] = {"status": ran.returncode, "stdout": ran.stdout,
                                   "stderr": ran.stderr, "passed": passed, "counts": document}
            save(result_path, result)
            print(mode, label, "pass" if passed else "FAIL", flush=True)
    if digest(args.compiler) != args.compiler_sha256:
        raise SystemExit("compiler changed while collecting counters")
    if any(row["build_status"] or any(not run["passed"] for run in row["runs"].values())
           for row in result["modes"].values()):
        raise SystemExit("counter qualification failed; raw evidence preserved")


if __name__ == "__main__":
    main()

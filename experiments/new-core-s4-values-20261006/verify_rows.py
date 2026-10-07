#!/usr/bin/env python3
"""Run every registered row in debug, release and verified release with leak checks."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("s4rows", ROOT / "experiments/new-core-s4-20261006/integration/measure_all46.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--bin", type=Path, required=True)
    p.add_argument("--evidence", type=Path, required=True)
    p.add_argument("--cache", type=Path, required=True)
    p.add_argument("--core", type=Path, default=ROOT / "zig-out/bin/mylang-core")
    a = p.parse_args()
    area, cache = a.evidence.resolve(), a.cache.resolve()
    area.mkdir(parents=True, exist_ok=False)
    cache.mkdir(parents=True, exist_ok=False)
    binaries = a.bin.resolve()
    journal = []
    summary = {"qualified": False, "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(), "commands": journal}
    core = a.core.resolve()
    summary["core_sha256"] = hashlib.sha256(core.read_bytes()).hexdigest()

    def run(command, native=False):
        result = subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=120,
                                env={**os.environ, **({"MYL_CORE_LEAKCHECK": "1"} if native else {})})
        name = f"command-{len(journal)+1:04d}.log"
        (area / name).write_text("$ " + shlex.join(map(str, command)) + "\nstdout=" + repr(result.stdout) + "\nstderr=" + repr(result.stderr) + f"\nexit={result.returncode}\n")
        journal.append({"command": list(map(str, command)), "status": result.returncode, "log": name})
        if result.returncode or result.stderr:
            raise RuntimeError("invalid child; retained " + name)
        return result.stdout

    try:
        for row in module.rows.UNITS:
            stem = module.rows.stem(row)
            source = ROOT / "test/core" / (stem + ".my")
            new = {"release": binaries / (stem + "_new")}
            for mode, flags in (("debug", []), ("verify", ["--release", "--verify-facts"])):
                new[mode] = cache / (stem + "_" + mode)
                run([core, "build", source, "-o", new[mode], "--cache-dir", cache / "frontend", "--link", ROOT / "benchmarks/runtime/ports/native_clock.c", *flags])
            for size in (2, 64, 4096):
                arguments = [str(size), "3", "7"]
                expected, elapsed = module.rows.parse_stdout(run([binaries / (stem + "_old"), *arguments], True))
                if elapsed <= 0:
                    raise RuntimeError("nonpositive old timer")
                for mode, binary in new.items():
                    actual, duration = module.rows.parse_stdout(run([binary, *arguments], True))
                    if actual != expected or duration <= 0:
                        raise RuntimeError(f"wrong checksum/timer: {row}/{mode}/{size}")
            print(row + ": debug/release/verify checksums agree; leak stderr empty", flush=True)
        summary["qualified"] = True
        summary["rows"] = len(module.rows.UNITS)
        summary["native_comparisons"] = len(module.rows.UNITS) * 9
        if hashlib.sha256(core.read_bytes()).hexdigest() != summary["core_sha256"]:
            raise RuntimeError("compiler changed during sweep")
    finally:
        (area / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Require byte-identical native trap/error traces from real split and whole builds."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
CASES = {
    "assert": (
        "module app\nimport leaf\ndef main() -> int:\n    return leaf.origin(1)\n",
        "module leaf\npublic def origin(x: int) -> int:\n    assert x == 0, \"leaf check\"\n    return x\n",
    ),
    "result": (
        "module app\nimport leaf\ndef main() -> Result[int, str]:\n    value = leaf.origin()?\n    return Ok(value)\n",
        "module leaf\npublic def origin() -> Result[int, str]:\n    return Err(\"leaf failure\")\n",
    ),
}
FLAGS = ("-march=native", "-mllvm", "-x86-experimental-pref-innermost-loop-alignment=6")


def command(argv, log, expected=0):
    started = time.monotonic()
    result = subprocess.run(list(map(str, argv)), capture_output=True, text=True,
                            env={**os.environ, "MYL_CORE_LEAKCHECK": "1"}, timeout=600)
    record = {"command": list(map(str, argv)), "status": result.returncode, "stdout": result.stdout,
              "stderr": result.stderr, "seconds": time.monotonic() - started}
    log.write_text(json.dumps(record, indent=2) + "\n")
    if result.returncode != expected:
        raise ValueError(f"expected exit {expected}: retained {log}")
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    area = args.evidence.resolve()
    area.relative_to(ROOT / "experiments")
    area.mkdir(parents=True, exist_ok=False)
    cache = ROOT / ".mylang-cache/s4-emission" / area.name
    cache.mkdir(parents=True, exist_ok=False)
    report = {"qualified": False, "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
              "compiler_sha256": hashlib.sha256(args.core.read_bytes()).hexdigest(), "comparisons": []}
    try:
        for case, (app, leaf) in CASES.items():
            source = area / case
            source.mkdir()
            (source / "app.my").write_text(app)
            (source / "leaf.my").write_text(leaf)
            for mode in ("debug", "release", "verify"):
                stem = f"{case}-{mode}"
                split = cache / f"split-{stem}"
                whole = cache / f"whole-{stem}"
                llvm = area / f"whole-{stem}.ll"
                argv = [args.core.resolve(), "build", source / "app.my", "-o", split, "--cache-dir", cache / "native", "--emit-llvm", llvm]
                if mode != "debug": argv.append("--release")
                if mode == "verify": argv.append("--verify-facts")
                command(argv, area / f"build-split-{stem}.json")
                runtimes = list((cache / "native").glob("core_rt-*.o"))
                if len(runtimes) != 1: raise ValueError(f"ambiguous runtime objects: {runtimes}")
                command(["zig", "cc", "-O0" if mode == "debug" else "-O3", *FLAGS, "-Wno-override-module", "-o", whole, llvm, runtimes[0]], area / f"build-whole-{stem}.json")
                left = command([split], area / f"run-split-{stem}.json", 1)
                right = command([whole], area / f"run-whole-{stem}.json", 1)
                if left["stdout"] != right["stdout"] or left["stderr"] != right["stderr"]:
                    raise ValueError(f"native trace bytes differ: {stem}")
                if "leaf.my:" not in left["stderr"] or "app.my:" not in left["stderr"]:
                    raise ValueError(f"source paths absent: {stem}")
                if "leak:" in left["stderr"]: raise ValueError(f"native trace leaked: {stem}")
                report["comparisons"].append({"case": case, "mode": mode, "identical": True, "stderr": left["stderr"]})
                print(f"{stem}: exact split/whole trap or trace bytes, both source paths", flush=True)
        report["qualified"] = True
    finally:
        (area / "summary.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()

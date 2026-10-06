#!/usr/bin/env python3
"""Force a real source-identical core rebuild while exclusive_core owns all slots.

Only the private local compile artifact matching the installed core is moved.
The original executable is restored on failure; source and installed binaries
are untouched before the normal successful installation replaces the latter.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    installed = root / "zig-out/bin/mylang-core"
    original = digest(installed)
    candidates = [path for path in (root / ".zig-cache/o").glob("*/mylang-core")
                  if path.is_file() and digest(path) == original]
    if len(candidates) != 1:
        parser.error(f"expected one matching private compile artifact, found {len(candidates)}")
    artifact = candidates[0]
    backup = artifact.with_name("mylang-core.s4-rebuild-backup")
    if backup.exists():
        parser.error("a previous rebuild backup exists; retain it before proceeding")
    artifact.rename(backup)
    result = None
    started = time.perf_counter()
    try:
        result = subprocess.run(["zig", "build", "core", "--summary", "all"], cwd=root)
        seconds = time.perf_counter() - started
        report = {"source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
                  "command": ["zig", "build", "core", "--summary", "all"],
                  "seconds": seconds, "exit": result.returncode,
                  "source_identical_rebuild": True, "compile_artifact": str(artifact),
                  "original_sha256": original,
                  "rebuilt_sha256": digest(installed) if result.returncode == 0 else None,
                  "affinity": sorted(os.sched_getaffinity(0)),
                  "qualified": result.returncode == 0 and seconds <= 10}
        with args.evidence.open("x") as stream:
            stream.write(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report), flush=True)
        return 0 if report["qualified"] else 1
    finally:
        if result is None or result.returncode:
            backup.replace(artifact)
        else:
            backup.unlink()


if __name__ == "__main__":
    raise SystemExit(main())

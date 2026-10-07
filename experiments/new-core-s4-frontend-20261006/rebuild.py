#!/usr/bin/env python3
"""Force a real source-identical core rebuild while exclusive_core owns all slots.

Only private manifests naming Core's main and the matching compile artifact move.
The original executable is restored on failure; source and installed binaries
are untouched before the normal successful installation replaces the latter.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
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
    # Zig owns and may replace complete o/h directories during recompilation.
    # Recovery copies must live outside those managed namespaces.
    staging = tempfile.TemporaryDirectory(prefix="s4-core-rebuild-", dir=root / ".mylang-cache/s4-frontend")
    backup = Path(staging.name) / "mylang-core"
    artifact.rename(backup)
    manifests = [path for path in (root / ".zig-cache/h").glob("*.txt")
                 if "src/core/main.zig" in path.read_text(errors="replace")]
    if not manifests:
        backup.replace(artifact)
        parser.error("no private core compile manifests found")
    moved = []
    for manifest in manifests:
        saved = Path(staging.name) / manifest.name
        if saved.exists():
            for original_manifest, saved_manifest in moved:
                saved_manifest.replace(original_manifest)
            backup.replace(artifact)
            parser.error("a previous manifest backup exists; retain it before proceeding")
        manifest.rename(saved)
        moved.append((manifest, saved))
    result = None
    started = time.perf_counter()
    try:
        result = subprocess.run(["zig", "build", "core", "--summary", "all"], cwd=root)
        seconds = time.perf_counter() - started
        report = {"source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
                  "command": ["zig", "build", "core", "--summary", "all"],
                  "seconds": seconds, "exit": result.returncode,
                  "source_identical_rebuild": True, "compile_artifact": str(artifact),
                  "invalidated_private_manifests": [str(path) for path in manifests],
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
            artifact.parent.mkdir(parents=True, exist_ok=True)
            backup.replace(artifact)
            for manifest, saved in moved:
                saved.replace(manifest)
        else:
            backup.unlink()
            for _, saved in moved:
                saved.unlink()
        staging.cleanup()


if __name__ == "__main__":
    raise SystemExit(main())

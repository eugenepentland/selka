#!/usr/bin/env python3
"""Preserve a completed application run without copying binaries or caches."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--label", required=True)
    args = parser.parse_args()
    source = args.run.resolve()
    target = HERE / "evidence" / args.label
    if target.exists():
        raise ValueError("refusing to overwrite evidence: " + str(target))
    target.mkdir(parents=True)
    results = json.loads((source / "results.json").read_text())
    (target / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    files = {}
    for path in sorted(source.glob("*/*/*.json")):
        relative = path.relative_to(source)
        if not (path.name.startswith(("counts-", "run-")) or path.name == "build.json"):
            continue
        data = path.read_bytes()
        compressed = gzip.compress(data, mtime=0)
        output = target / str(relative.with_suffix(".json.gz"))
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(compressed)
        files[str(relative)] = {"raw_sha256": hashlib.sha256(data).hexdigest(),
                                "compressed_sha256": hashlib.sha256(compressed).hexdigest(),
                                "raw_bytes": len(data)}
    (target / "raw-manifest.json").write_text(json.dumps(files, indent=2) + "\n")


if __name__ == "__main__":
    main()

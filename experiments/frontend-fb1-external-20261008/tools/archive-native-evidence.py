#!/usr/bin/env python3
"""Preserve every native command/output byte in a verified lossless archive."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import tarfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--area", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cases", type=int, required=True)
    args = parser.parse_args()
    area, output = args.area.resolve(), args.output.resolve()
    answer = json.loads((area / "answers.json").read_text())
    assert answer["summary"]["cases"] == args.cases
    assert not answer["summary"]["failed"] and not answer["summary"]["mismatches"]
    assert answer["summary"]["binary_unchanged"]
    archive = output.with_suffix(".tar.gz")
    manifest_path = output.with_suffix(".manifest.json")
    answer_path = output.with_suffix(".answers.json")
    assert not any(path.exists() for path in (archive, manifest_path, answer_path))
    files = sorted(path for path in area.rglob("*") if path.is_file())
    assert not any(path.is_symlink() for path in files), "symlink in evidence"
    members = {path.relative_to(area).as_posix(): {
        "sha256": digest(path.read_bytes()), "bytes": path.stat().st_size} for path in files}
    with archive.open("wb") as raw, gzip.GzipFile(fileobj=raw, mode="wb", mtime=0) as zipped:
        with tarfile.open(fileobj=zipped, mode="w") as tar:
            for path in files:
                tar.add(path, arcname=path.relative_to(area).as_posix(), recursive=False)
    with tarfile.open(archive, "r:gz") as tar:
        archived = {}
        for member in tar.getmembers():
            assert member.isfile()
            data = tar.extractfile(member).read()
            archived[member.name] = {"sha256": digest(data), "bytes": len(data)}
    assert archived == members, "archive membership/content differs"
    manifest = {"source_area": str(area), "archive_sha256": digest(archive.read_bytes()),
        "archive_bytes": archive.stat().st_size, "verified_members": len(members),
        "verified_lossless": True, "members": members}
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    answer_path.write_bytes((area / "answers.json").read_bytes())
    print(json.dumps({"cases": args.cases, "verified_lossless": True,
        "members": len(members), "archive_bytes": archive.stat().st_size}))


if __name__ == "__main__":
    main()

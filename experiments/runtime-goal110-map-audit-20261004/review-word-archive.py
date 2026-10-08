#!/usr/bin/env python3
"""Verify portable typed-lookup evidence, including the documented comment snapshot."""
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[2]
FOLDER = "experiments/runtime-goal110-dictionary-word-20261004"
COMMIT = "b31743c3"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    root = ROOT / FOLDER
    index = root / "index.json"
    doc = json.loads(index.read_text())
    assert sha(index.read_bytes()) == "8afe638519ecc9ddeefee243d04d9d1aaf1fcdf256c00027b06ed7002156e25e"
    tracked = subprocess.check_output(["git", "ls-tree", "-r", COMMIT, "--", FOLDER], cwd=ROOT, text=True).splitlines()
    for line in tracked:
        record, path = line.split("\t", 1)
        assert subprocess.check_output(["git", "hash-object", "--", path], cwd=ROOT, text=True).strip() == record.split()[2]
    count, live, comments = 0, 0, []
    for row in doc["files"]:
        data = (root / row["path"]).read_bytes()
        assert len(data) == row["bytes"] and sha(data) == row["sha256"]
        raw = gzip.decompress(data) if row["encoding"] == "gzip" else data
        if "source_sha256" in row:
            assert len(raw) == row["source_bytes"] and sha(raw) == row["source_sha256"]
            assert Path(row["source_path"]).read_bytes() == raw
            live += 1
        count += 1
    for pack in doc["packs"]:
        data = (root / pack["path"]).read_bytes()
        assert len(data) == pack["bytes"] and sha(data) == pack["sha256"]
        with tarfile.open(root / pack["path"], "r:gz") as tar:
            assert len(tar.getnames()) == len(pack["entries"])
            assert set(tar.getnames()) == {row["path"] for row in pack["entries"]}
            for row in pack["entries"]:
                raw = tar.extractfile(row["path"]).read()
                assert len(raw) == row["bytes"] and sha(raw) == row["sha256"]
                count += 1
                if "source_path" not in row:
                    continue
                current = Path(row["source_path"]).read_bytes()
                if pack["path"] == "unit-tested-comment-snapshot.tar.gz" and row["path"] == "src/qbe_test.zig":
                    old = b'// spec-case: PY-DICT-4\n// spec-case: QBE-PURE-READ-1\ntest "PY-DICT-4 word schemas specialize ordinary index and get"'
                    new = old.replace(b"spec-case: PY-DICT-4", b"spec: PY-DICT-4", 1)
                    assert current.count(old) == 1
                    current = current.replace(old, new, 1)
                    old = b'// spec-case: PY-DICT-4\n// spec-case: RC-SITES-1\ntest "PY-DICT-4 word counting and sites retain ordinary callee inventories"'
                    new = old.replace(b"spec-case: RC-SITES-1", b"spec: RC-SITES-1", 1)
                    assert current.count(old) == 1
                    current = current.replace(old, new, 1)
                    comments.append(dict(path=row["path"], changes="exact two spec/spec-case comment tags", reconstructed_sha256=sha(current)))
                assert current == raw, (pack["path"], row["path"])
                live += 1
    for row in doc["live_bindings"]:
        assert sha(Path(row["path"]).read_bytes()) == row["sha256"]
    replay = subprocess.run(["python3", str(root / "verify-archive.py")], capture_output=True, text=True)
    assert replay.returncode == 0, replay.stdout + replay.stderr
    result = dict(status="pass", reviewed_utc=datetime.now(timezone.utc).isoformat(),
                  archive_commit=subprocess.check_output(["git", "rev-parse", COMMIT], cwd=ROOT, text=True).strip(),
                  index_sha256=sha(index.read_bytes()), tracked_files=len(tracked),
                  stored_decoded_members=count, live_sources=live, live_bindings=len(doc["live_bindings"]),
                  tested_comment_reconstruction=comments, script_sha256=sha(Path(__file__).read_bytes()),
                  replay=dict(status=replay.returncode, stdout=replay.stdout),
                  limitations=["Archive byte integrity, separate from prior semantic/static/timing reviews.",
                               "Initial strict live-equality attempt rejected the intentionally historical two-comment snapshot; exact reconstruction verifies it.",
                               "ELFs remain live and receipt-bound, not stored in Git."])
    with Path(sys.argv[1]).open("x") as out:
        out.write(json.dumps(result, indent=2) + "\n")
    print(f"PASS {len(tracked)} Git files, {count} stored members, {live} live sources and {len(doc['live_bindings'])} live bindings")


if __name__ == "__main__":
    main()

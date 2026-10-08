#!/usr/bin/env python3
"""Small retained archive-integrity tests; these do not qualify a compiler."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import unittest
from unittest import mock

import archive_raw_processes as archive


class ArchiveChecks(unittest.TestCase):
    evidence = None

    def setUp(self):
        self.home = self.evidence / self._testMethodName
        self.home.mkdir()
        self.raw = self.home / "processes"
        self.raw.mkdir()
        (self.raw / "nested").mkdir()
        (self.raw / "nested" / "empty-dir").mkdir()
        self.payloads = {
            "00001.stdout": b"invalid UTF-8: \xff\xfe\x80\x00\r\n",
            "00001.stderr": b"",
            "nested/00002.stdout": bytes(range(256)) * 8193,
            "nested/00002.stderr": "nested output λ\n".encode(),
        }
        for name, data in self.payloads.items():
            (self.raw / name).write_bytes(data)
        self.out = self.home / "archive"

    def capture_cli(self, label, *args):
        argv = [sys.executable, str(Path(archive.__file__).absolute()), *map(str, args)]
        result = subprocess.run(argv, capture_output=True, timeout=10)
        (self.home / (label + ".stdout")).write_bytes(result.stdout)
        (self.home / (label + ".stderr")).write_bytes(result.stderr)
        (self.home / (label + ".json")).write_text(json.dumps({
            "argv": argv, "status": result.returncode,
            "tool_sha256": archive.digest_file(archive.__file__),
        }, indent=2) + "\n")
        return result

    def repack(self, path, entries):
        with tarfile.open(path, "w:gz") as packed:
            for name, kind, data in entries:
                info = tarfile.TarInfo(name)
                info.type = kind
                if kind == tarfile.REGTYPE:
                    info.size = len(data)
                    packed.addfile(info, io.BytesIO(data))
                else:
                    info.linkname = "../../outside" if kind in (tarfile.SYMTYPE, tarfile.LNKTYPE) else ""
                    packed.addfile(info)

    def entries(self, replacement=None):
        entries = [("nested", tarfile.DIRTYPE, b""), ("nested/empty-dir", tarfile.DIRTYPE, b"")]
        entries += [(name, tarfile.REGTYPE, replacement if name == "00001.stdout" and replacement is not None else data)
                    for name, data in self.payloads.items()]
        return entries

    def retained_rejection(self, label, path, index):
        index = {**index, "archive_sha256": archive.digest_file(path)}
        index_path = self.home / (label + ".index.json")
        index_path.write_text(json.dumps(index, indent=2, sort_keys=True) + "\n")
        result = self.capture_cli(label, "verify", "--archive", path, "--index", index_path)
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn(b"archive rejected:", result.stdout)
        return result

    def test_binary_nested_round_trip_preserves_readable_evidence(self):
        outside = {"summary.json": b'{"complete": false}\n',
                   "commands.jsonl": b'{"argv": ["compiler"]}\n',
                   "generated.my": b"fn main() -> int { 7 }\n"}
        for name, data in outside.items():
            (self.home / name).write_bytes(data)
        before = archive.snapshot(self.raw)
        created = self.capture_cli("create", "create", "--raw", self.raw, "--output", self.out)
        self.assertEqual(created.returncode, 0, created.stdout)
        index = json.loads((self.out / "index.json").read_text())
        self.assertEqual(set(index["files"]), set(self.payloads))
        self.assertEqual(index["file_count"], 4)
        self.assertEqual(index["total_bytes"], sum(map(len, self.payloads.values())))
        for name, data in self.payloads.items():
            self.assertEqual(index["files"][name]["sha256"], hashlib.sha256(data).hexdigest())
            self.assertEqual(index["files"][name]["size"], len(data))
            self.assertEqual((self.raw / name).read_bytes(), data)
        self.assertEqual(archive.snapshot(self.raw), before)
        self.assertTrue(json.loads((self.out / "status.json").read_text())["lossless_bytes_verified"])
        for name, data in outside.items():
            self.assertEqual((self.home / name).read_bytes(), data)
        for label, extra in (("verify-index", []), ("verify-original", ["--raw", self.raw])):
            result = self.capture_cli(label, "verify", "--archive", self.out / "raw-processes.tar.gz",
                                      "--index", self.out / "index.json", *extra)
            self.assertEqual(result.returncode, 0, result.stdout)

    def test_changed_member_rejected_after_updated_archive_hash(self):
        index = archive.create_archive(self.raw, self.out)
        path = self.home / "tampered-member.tar.gz"
        self.repack(path, self.entries(b"x" * len(self.payloads["00001.stdout"])))
        result = self.retained_rejection("tampered-member", path, index)
        self.assertIn(b"member hash mismatch", result.stdout)

    def test_unsafe_duplicate_missing_and_link_members_rejected(self):
        index = archive.create_archive(self.raw, self.out)
        variants = {
            "parent-traversal": self.entries() + [("../escape", tarfile.REGTYPE, b"bad")],
            "absolute": self.entries() + [("/absolute", tarfile.REGTYPE, b"bad")],
            "duplicate": self.entries() + [self.entries()[-1]],
            "missing": self.entries()[:-1],
            "symlink": [(name, tarfile.SYMTYPE if name == "00001.stdout" else kind, data)
                        for name, kind, data in self.entries()],
            "hardlink": [(name, tarfile.LNKTYPE if name == "00001.stdout" else kind, data)
                         for name, kind, data in self.entries()],
        }
        for label, entries in variants.items():
            with self.subTest(label=label):
                path = self.home / (label + ".tar.gz")
                self.repack(path, entries)
                self.retained_rejection(label, path, index)
        self.assertFalse((self.home / "escape").exists())

    def test_symlink_and_special_input_refused(self):
        for label, prepare in (
                ("file-symlink", lambda home: (home / "link").symlink_to(self.raw / "00001.stdout")),
                ("directory-symlink", lambda home: (home / "link").symlink_to(self.raw, target_is_directory=True)),
                ("fifo", lambda home: os.mkfifo(home / "pipe"))):
            with self.subTest(label=label):
                raw = self.home / label
                raw.mkdir()
                prepare(raw)
                output = self.home / (label + "-archive")
                result = self.capture_cli(label, "create", "--raw", raw, "--output", output)
                self.assertEqual(result.returncode, 1)
                self.assertFalse(output.exists())
        link = self.home / "raw-root-link"
        link.symlink_to(self.raw, target_is_directory=True)
        result = self.capture_cli("root-symlink", "create", "--raw", link, "--output", self.out)
        self.assertEqual(result.returncode, 1)
        self.assertFalse(self.out.exists())

    def test_output_and_verification_symlinks_refused(self):
        parent = self.home / "output-parent-link"
        parent.symlink_to(self.home, target_is_directory=True)
        result = self.capture_cli("output-parent-symlink", "create", "--raw", self.raw,
                                  "--output", parent / "forbidden")
        self.assertEqual(result.returncode, 1)
        self.assertFalse((self.home / "forbidden").exists())
        archive.create_archive(self.raw, self.out)
        for label, target in (("archive-link", self.out / "raw-processes.tar.gz"),
                              ("index-link", self.out / "index.json")):
            link = self.home / label
            link.symlink_to(target)
            result = self.capture_cli(label, "verify", "--archive",
                link if label == "archive-link" else self.out / "raw-processes.tar.gz", "--index",
                link if label == "index-link" else self.out / "index.json")
            self.assertEqual(result.returncode, 1)

    def test_changed_input_after_round_trip_never_completes(self):
        before = archive.snapshot(self.raw)
        original_verify = archive.verify_archive
        victim = self.raw / "00001.stdout"
        old_stat = victim.stat()

        def mutate():
            victim.write_bytes(b"z" * len(self.payloads["00001.stdout"]))
            os.utime(victim, ns=(old_stat.st_atime_ns, old_stat.st_mtime_ns))

        def mutate_after(*args):
            count = original_verify(*args)
            with ThreadPoolExecutor(max_workers=1) as pool:
                pool.submit(mutate).result()
            return count

        with mock.patch.object(archive, "verify_archive", side_effect=mutate_after):
            with self.assertRaisesRegex(ValueError, "input changed") as rejected:
                archive.create_archive(self.raw, self.out)
        (self.home / "rejection.txt").write_text(str(rejected.exception) + "\n")
        after = archive.snapshot(self.raw)
        (self.home / "input-snapshots.json").write_text(json.dumps({"before": before, "after": after}, indent=2) + "\n")
        self.assertNotEqual(after, before)
        self.assertEqual(victim.stat().st_mtime_ns, old_stat.st_mtime_ns)
        self.assertFalse(json.loads((self.out / "status.json").read_text())["complete"])

    def test_byte_identical_rewrite_and_inventory_change_refused(self):
        original_verify = archive.verify_archive
        for label in ("identical-rewrite", "added-file"):
            def mutate_after(*args):
                count = original_verify(*args)
                def mutate():
                    if label == "identical-rewrite":
                        path = self.raw / "00001.stdout"
                        info = path.stat()
                        path.write_bytes(self.payloads["00001.stdout"])
                        os.utime(path, ns=(info.st_atime_ns, info.st_mtime_ns))
                    else:
                        (self.raw / "new.stdout").write_bytes(b"new")
                with ThreadPoolExecutor(max_workers=1) as pool:
                    pool.submit(mutate).result()
                return count
            with self.subTest(label=label), mock.patch.object(archive, "verify_archive", side_effect=mutate_after):
                output = self.home / label
                with self.assertRaisesRegex(ValueError, "input changed") as rejected:
                    archive.create_archive(self.raw, output)
                (self.home / (label + ".rejection.txt")).write_text(str(rejected.exception) + "\n")
                self.assertFalse(json.loads((output / "status.json").read_text())["complete"])

    def test_fresh_output_and_consistent_index_required(self):
        index = archive.create_archive(self.raw, self.out)
        original = (self.out / "index.json").read_bytes()
        result = self.capture_cli("existing-output", "create", "--raw", self.raw, "--output", self.out)
        self.assertEqual(result.returncode, 1)
        self.assertEqual((self.out / "index.json").read_bytes(), original)
        result = self.capture_cli("inside-input", "create", "--raw", self.raw, "--output", self.raw / "archive")
        self.assertEqual(result.returncode, 1)
        self.assertFalse((self.raw / "archive").exists())
        bad = {**index, "file_count": 0}
        self.retained_rejection("false-index-total", self.out / "raw-processes.tar.gz", bad)
        orphaned = {**index, "directories": {".": index["directories"]["."]}}
        self.retained_rejection("missing-index-directory", self.out / "raw-processes.tar.gz", orphaned)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True, help="Fresh directory for fixture bytes and receipts")
    args = parser.parse_args()
    evidence = args.evidence.absolute()
    evidence.mkdir(parents=True, exist_ok=False)
    ArchiveChecks.evidence = evidence
    source_hashes = {Path(path).name: archive.digest_file(path) for path in (__file__, archive.__file__)}
    with (evidence / "tests.log").open("w") as log:
        result = unittest.TextTestRunner(stream=log, verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(ArchiveChecks))
    after = {Path(path).name: archive.digest_file(path) for path in (__file__, archive.__file__)}
    summary = {"helper_checks_passed": result.wasSuccessful() and source_hashes == after,
               "tests_run": result.testsRun, "failures": len(result.failures), "errors": len(result.errors),
               "source_before": source_hashes, "source_after": after,
               "scope": "Archive integrity helper only; no compiler qualification claim"}
    (evidence / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    print(json.dumps(summary, sort_keys=True))
    return 0 if summary["helper_checks_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

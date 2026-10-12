"""Adversarial request-local adapter checks with private fixture artifacts only."""
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import bootstrap_evidence_bridge as B


class EvidenceBridgeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "owner"
        self.root.mkdir()
        self.cache = Path(self.temporary.name) / "cache"
        self.pin = {"commit": "a" * 40, "archive_sha256": "b" * 64, "zig": "fixture-tool"}
        self.write(self.root / "selfhost/component-seed.json", self.pin)
        self.bytes(self.root / ".zigversion", b"fixture-tool\n")
        self.seed = {"recipe": {"pin": self.pin, "zig_sha256": "c" * 64},
                     "sha256": self.sha(b"fixture seed"), "source_identity": {"seed.my": "d" * 64}}
        seed_key = self.sha(B.canonical(self.seed["recipe"]))
        seed_root = self.cache / "seeds" / seed_key
        self.write(seed_root / "receipt.json", self.seed)
        self.bytes(seed_root / "source/zig-out/focus/mylang", b"fixture seed")
        self.bytes(self.root / "zig-out/bin/mylang", b"fixture host")
        self.directory = self.root / "zig-out/libexec/mylang/components"
        for name, (source, protocol, schema) in B.PACKAGES.items():
            self.bytes(self.root / "selfhost/components" / source / "main.my", b"source fixture")
            artifact = name + "-" + self.sha(name.encode())
            self.bytes(self.directory / artifact, name.encode())
            identity = {"component": name, "protocol": protocol, "schema": schema,
                        "build_cache_root": str(self.cache), "sources": {"main.my": self.sha(b"source fixture")},
                        "seed": self.seed, "flags": ["fixture"]}
            key = self.sha(B.canonical(identity))
            self.write(self.cache / "artifacts" / key / "receipt.json", {"identity": identity, "sha256": self.sha(name.encode())})
            self.write(self.directory / (name + ".json"), {"format": 1, "component": name, "protocol": protocol,
                                                       "schema": schema, "artifact": artifact,
                                                       "key": key, "sha256": self.sha(name.encode())})
        for index, name in enumerate(B.ARCHIVES):
            directory = self.root / "docs/audits/evidence" / name
            raw = b"historical partial fixture"
            compressed = gzip.compress(raw)
            self.bytes(directory / "control.gz", compressed)
            if index == 0:
                item = {"name": "control", "compressed": "control.gz", "compressed_sha256": self.sha(compressed),
                        "sha256": self.sha(raw), "bytes": len(raw)}
                receipt = {"scope": "old body subset", "body_schema": 10, "full_gate": "pending", "evidence": [item]}
            else:
                item = {"name": "control.gz", "archive_sha256": self.sha(compressed), "sha256": self.sha(raw), "bytes": len(raw)}
                receipt = {"scope": "focused repair only", "artifacts": [item]}
            self.write(directory / "receipt.json", receipt)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        subprocess.run(["git", "-C", str(self.root), "add", "."], check=True)
        subprocess.run(["git", "-C", str(self.root),
                        "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                        "commit", "-qm", "private fixture"], check=True)
        self.commit = subprocess.check_output(["git", "-C", str(self.root), "rev-parse", "HEAD"], text=True).strip()
        supported = patch.object(B, "SUPPORTED_OWNER_COMMIT", self.commit)
        supported.start()
        self.addCleanup(supported.stop)

    def sha(self, data):
        return hashlib.sha256(data).hexdigest()

    def bytes(self, path, data):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def write(self, path, value):
        self.bytes(path, json.dumps(value).encode())

    def evaluate(self):
        return B.evaluate_bootstrap(self.root, self.cache, self.commit)

    def manifest(self):
        return json.loads((self.directory / "body-check.json").read_text())

    def test_valid_partial_evidence_never_grants_bootstrap(self):
        report = self.evaluate()
        self.assertEqual(report["status"], "partial")
        self.assertFalse(report["complete"])
        self.assertEqual(len(report["packages"]), 7)
        self.assertEqual(sum(x["archive_files_authenticated"] for x in report["archives"]), 2)
        self.assertEqual(report["archives"][0]["full_gate"], "pending")
        self.assertGreater(len(report["inputs"]), 20)

    def test_replaced_seed_binary_invalidates_evidence(self):
        key = self.sha(B.canonical(self.seed["recipe"]))
        self.bytes(self.cache / "seeds" / key / "source/zig-out/focus/mylang", b"replaced")
        report = self.evaluate()
        self.assertEqual(report["status"], "invalid")
        self.assertFalse(report["complete"])
        self.assertIn("seed executable", report["diagnostics"][0]["reason"])

    def test_changed_producer_recipe_cannot_preserve_key(self):
        manifest = self.manifest()
        path = self.cache / "artifacts" / manifest["key"] / "receipt.json"
        receipt = json.loads(path.read_text())
        receipt["identity"]["flags"] = ["different mode"]
        self.write(path, receipt)
        report = self.evaluate()
        self.assertEqual(report["status"], "invalid")
        self.assertIn("not bound", report["diagnostics"][0]["reason"])

    def test_missing_selected_artifact_is_invalid(self):
        (self.directory / self.manifest()["artifact"]).unlink()
        report = self.evaluate()
        self.assertEqual(report["status"], "invalid")
        self.assertFalse(report["complete"])

    def test_malformed_or_duplicate_json_fails(self):
        with self.assertRaisesRegex(ValueError, "duplicate"):
            B.parse(b'{"format":1,"format":1}')
        with self.assertRaises(ValueError):
            B.parse(b'{')
        with self.assertRaisesRegex(ValueError, "must be an object"):
            B.parse(b'[]')

    def test_hostile_archive_path_is_refused(self):
        for name in ("../outside.gz", "/outside.gz", ".."):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, "unsafe"):
                B.basename(name)

    def test_compressed_corruption_is_invalid(self):
        name = B.ARCHIVES[0]
        observations = B.Observations()
        path = self.root / "docs/audits/evidence" / name / "control.gz"
        self.bytes(path, b"wrong gzip")
        with self.assertRaisesRegex(ValueError, "compressed digest"):
            B.archives(observations, self.root, name)

    def test_uncompressed_hash_is_independently_verified(self):
        name = B.ARCHIVES[0]
        path = self.root / "docs/audits/evidence" / name / "receipt.json"
        value = json.loads(path.read_text())
        value["evidence"][0]["sha256"] = "0" * 64
        self.write(path, value)
        with self.assertRaisesRegex(ValueError, "uncompressed identity"):
            B.archives(B.Observations(), self.root, name)

    def test_tracked_owner_mutation_refuses_snapshot(self):
        self.bytes(self.root / "selfhost/components/body_check/main.my", b"edited")
        report = self.evaluate()
        self.assertEqual(report["status"], "invalid")
        self.assertIn("uncommitted", report["diagnostics"][0]["reason"])

    def test_final_recheck_detects_replacement(self):
        original = B.Observations.recheck
        def replacement(observer):
            self.bytes(self.cache / "seeds" / self.sha(B.canonical(self.seed["recipe"])) / "source/zig-out/focus/mylang", b"changed seed")
            return original(observer)
        with patch.object(B.Observations, "recheck", replacement):
            report = self.evaluate()
        self.assertEqual(report["status"], "invalid")
        self.assertIn("between reads", report["diagnostics"][-1]["reason"])

    def test_source_membership_added_before_final_check_is_invalid(self):
        original = B.Observations.recheck
        def addition(observer):
            self.bytes(self.root / "selfhost/components/body_check/added.my", b"late source")
            return original(observer)
        with patch.object(B.Observations, "recheck", addition):
            report = self.evaluate()
        self.assertEqual(report["status"], "invalid")
        self.assertIn("membership changed", report["diagnostics"][-1]["reason"])

    def test_source_aba_is_not_accepted_as_unchanged(self):
        observer = B.Observations()
        path = self.root / "selfhost/components/body_check/main.my"
        observer.read(path, "fixture")
        original = path.read_bytes()
        path.write_bytes(b"changed source")
        path.write_bytes(original)
        with self.assertRaisesRegex(ValueError, "metadata/alias changed"):
            observer.recheck()

    def test_source_edit_is_partial_provenance_without_adoption(self):
        self.bytes(self.root / "selfhost/components/body_check/main.my", b"edited")
        value = B.package(B.Observations(), self.root, self.cache, "body-check", self.pin, None)
        self.assertFalse(value["source_current"])
        self.assertFalse(value["complete"])
        self.assertEqual(value["changed_source_paths"], ["main.my"])

    def test_schema10_receipt_cannot_qualify_current_body_profile(self):
        manifest = self.manifest()
        path = self.cache / "artifacts" / manifest["key"] / "receipt.json"
        receipt = json.loads(path.read_text())
        receipt["identity"]["schema"] = 10
        key = self.sha(B.canonical(receipt["identity"]))
        self.write(self.cache / "artifacts" / key / "receipt.json", receipt)
        manifest.update(key=key, schema=10)
        self.write(self.directory / "body-check.json", manifest)
        value = B.package(B.Observations(), self.root, self.cache, "body-check", self.pin, None)
        self.assertFalse(value["schema_current"])
        self.assertFalse(value["complete"])
        self.assertEqual(value["expected_schema"], 11)

    def test_wrong_owner_commit_refuses_snapshot(self):
        report = B.evaluate_bootstrap(self.root, self.cache, "f" * 40)
        self.assertEqual(report["status"], "invalid")
        self.assertFalse(report["complete"])

    def test_aggregate_read_budget_is_not_a_success(self):
        path = self.root / "aggregate"
        self.bytes(path, b"12345")
        with self.assertRaisesRegex(ValueError, "aggregate diagnostic byte budget"):
            B.Observations(byte_budget=4).read(path, "fixture")

    def test_conflicting_seed_receipts_are_refused(self):
        observer = B.Observations()
        B.seed_identity(observer, self.cache, self.seed, self.pin, None)
        changed = json.loads(json.dumps(self.seed))
        changed["sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "conflicting qualifications"):
            B.seed_identity(observer, self.cache, changed, self.pin, None)

    def test_bounded_reader_refuses_oversize(self):
        path = self.root / "too-large"
        self.bytes(path, b"12345")
        with self.assertRaisesRegex(ValueError, "bounded read"):
            B.Observations().read(path, "fixture", limit=4)


if __name__ == "__main__":
    unittest.main()

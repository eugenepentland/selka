#!/usr/bin/env python3
"""Authentication and owned-filesystem regressions for bundle provisioning."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

import native_platform_bundle as bundle


class BundleTests(unittest.TestCase):
    def test_cached_package_tampering_is_rejected_before_use(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "package.deb"
            path.write_bytes(b"tampered")
            with self.assertRaises(ValueError), mock.patch.object(bundle.urllib.request, "urlopen", side_effect=AssertionError("network must not repair corrupt content")):
                bundle.download("https://invalid.example/package", path, bundle.digest(b"reviewed"), 8)

    def test_hash_and_size_are_independent_checks(self):
        with self.assertRaises(ValueError):
            bundle.checked(b"reviewed", bundle.digest(b"reviewed"), 7)
        with self.assertRaises(ValueError):
            bundle.checked(b"modified", bundle.digest(b"reviewed"), 8)

    def test_release_signature_still_required_if_manifest_digest_changes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            profile = root / "profile"
            shutil.copytree(bundle.PROFILE, profile)
            release = (profile / "InRelease").read_bytes().replace(b"Origin: Debian", b"Origin: Forger", 1)
            (profile / "InRelease").write_bytes(release)
            manifest = json.loads((profile / "manifest.json").read_text())
            manifest["release_sha256"] = bundle.digest(release)
            with self.assertRaises(subprocess.CalledProcessError), mock.patch.object(bundle.urllib.request, "urlopen", side_effect=AssertionError("no unauthenticated downloads")):
                bundle.authenticate(profile, manifest, root)

    def test_tree_records_absent_members_additions_and_symlink_targets(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "one").write_bytes(b"same")
            (root / "two").write_bytes(b"same")
            (root / "link").symlink_to("one")
            original = bundle.tree_manifest(root)
            (root / "link").unlink()
            (root / "link").symlink_to("two")
            self.assertNotEqual(original, bundle.tree_manifest(root))
            (root / "added").mkdir()
            self.assertTrue(any(row["path"] == "added" for row in bundle.tree_manifest(root)))
            (root / "added").rmdir()
            (root / "link").unlink()
            (root / "link").symlink_to("one")
            self.assertEqual(original, bundle.tree_manifest(root))


if __name__ == "__main__":
    unittest.main()

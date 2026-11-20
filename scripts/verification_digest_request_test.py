#!/usr/bin/env python3
"""End-to-end request controls for persisted verification digests."""
import contextlib
import io
import os
from pathlib import Path
import unittest
from unittest.mock import patch

import verify_cache as coordinator
import verify_cache_test as fixtures


class DigestRequest(fixtures.VerificationCoordinator):
    def test_verify_cli_rehashes_inputs_without_forcing_valid_actions(self):
        with patch.object(coordinator, "ROOT", self.root), \
                patch.object(coordinator, "CACHE_DIRECTORY", Path(".receipts")), \
                patch.dict(os.environ, SELKA_ADMISSION_BACKEND="legacy"), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            argv = ["--zig", str(self.zig), "--shared-cache-dir", ""]
            self.assertEqual(coordinator.main(argv), 0)
            self.assertTrue((self.cache / "digests-v1.json").is_file())
            self.admissions.clear()
            self.assertEqual(coordinator.main(["--verify", *argv]), 0)
        report = coordinator.read_record(self.cache / "last-run.json")
        self.assertEqual(self.admissions, [])
        self.assertEqual(self.states(), {"unit": "reused", "docs": "reused"})
        self.assertEqual(report["snapshot_statistics"]["digest_reuses"], 0)
        self.assertGreater(report["snapshot_statistics"]["files_hashed"], 0)

    def test_verified_pending_request_keeps_rehash_control_in_own_execution(self):
        shared = self.root / ".shared-digest-review"
        with patch.dict(os.environ, SELKA_ADMISSION_BACKEND="legacy"):
            self.assertEqual(self.execute(shared=shared), 0)
        self.input.write_text("changed input requires work")
        with patch.dict(os.environ, SELKA_ADMISSION_BACKEND="scheduler"), \
                patch.object(coordinator, "subscribe_gate", side_effect=AssertionError(
                    "--verify must not delegate to a worker lacking its rehash control")):
            self.assertEqual(self.execute(shared=shared, verify_digests=True), 0)
        report = coordinator.read_record(self.cache / "last-run.json")
        self.assertEqual(report["snapshot_statistics"]["digest_reuses"], 0)
        self.assertEqual(report["subscriptions"], [])
        self.assertTrue(any(kind == "gate" for kind, _ in self.admissions))


def load_tests(loader, tests, pattern):
    return unittest.TestSuite(DigestRequest(name) for name in sorted(DigestRequest.__dict__)
                              if name.startswith("test_"))


if __name__ == "__main__":
    unittest.main()

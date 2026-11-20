#!/usr/bin/env python3
"""The read audit's comparison of a traced build with its replay record (`audit_cache_reads.py trace`), on synthetic records.

    python3 scripts/audit_cache_reads_test.py

The comparison is the regression check for recorded reads: a project path a build opened, looked for or listed must be an
input of its replay record (`src/core/inputs.zig`). It went blind when the record changed from `dependencies` to `inputs`
(format `core-build-replay-v8`): every project read then showed as unrecorded. No compiler runs here.
"""
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audit_cache_reads as audit  # noqa: E402


def record(cache, name, payload):
    """Write a replay record named NAME whose payload is PAYLOAD, in the on-disk wrapper (a JSON string inside JSON)."""
    folder = Path(cache) / "replay-v1"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / name).write_text(json.dumps({"version": "core-build-replay-v8", "payload": json.dumps(payload), "checksum": "x"}))


FILE = {"kind": "file", "name": "/p/main.selka", "digest": "a" * 64, "stamp": {"size": 1, "inode": 2, "mtime": 3, "ctime": 4}}
ABSENT = {"kind": "file", "name": "/p/missing.selka"}
EXISTS = {"kind": "exists", "name": "/p/probe.txt", "present": False}
LISTING = {"kind": "listing", "name": "/p", "digest": "b" * 64, "filter": "standard_modules"}
VARIABLE = {"kind": "variable", "name": "SELKA_HOST_LIMIT_CHECKPOINT", "value": "1:2"}


class ReplayInputsTest(unittest.TestCase):
    def test_every_kind_of_input_fills_its_own_set(self):
        with tempfile.TemporaryDirectory() as cache:
            record(cache, "one.inputs", {"key": "k", "inputs": [FILE, ABSENT, EXISTS, LISTING, VARIABLE]})
            recorded, records = audit.replay_inputs(Path(cache))
        self.assertEqual(len(records), 1)
        self.assertEqual(recorded["file"], {"/p/main.selka"})
        self.assertEqual(recorded["absent"], {"/p/missing.selka"})
        self.assertEqual(recorded["exists"], {"/p/probe.txt"})
        self.assertEqual(recorded["listing"], {"/p"})
        self.assertEqual(recorded["variable"], {"SELKA_HOST_LIMIT_CHECKPOINT"})

    def test_the_inputs_of_several_records_unite(self):
        with tempfile.TemporaryDirectory() as cache:
            record(cache, "one.inputs", {"inputs": [FILE]})
            record(cache, "two.inputs", {"inputs": [LISTING]})
            recorded, records = audit.replay_inputs(Path(cache))
        self.assertEqual(len(records), 2)
        self.assertEqual((recorded["file"], recorded["listing"]), ({"/p/main.selka"}, {"/p"}))

    def test_an_old_record_with_dependencies_only_yields_no_inputs(self):
        with tempfile.TemporaryDirectory() as cache:
            record(cache, "old.inputs", {"dependencies": [{"path": "/p/main.selka"}]})
            recorded, records = audit.replay_inputs(Path(cache))
        self.assertEqual(len(records), 1)
        self.assertTrue(all(not names for names in recorded.values()))

    def test_partial_damaged_and_missing_records_are_skipped(self):
        with tempfile.TemporaryDirectory() as cache:
            record(cache, "one.inputs", {"inputs": [FILE]})
            record(cache, "two.inputs.partial", {"inputs": [LISTING]})
            (Path(cache) / "replay-v1" / "damaged").write_text("not json")
            recorded, records = audit.replay_inputs(Path(cache))
            self.assertEqual((len(records), recorded["listing"]), (1, set()))
            self.assertEqual(audit.replay_inputs(Path(cache) / "absent")[1], [])


class UnrecordedTest(unittest.TestCase):
    def recorded(self, *inputs):
        with tempfile.TemporaryDirectory() as cache:
            record(cache, "r.inputs", {"inputs": list(inputs)})
            return audit.replay_inputs(Path(cache))[0]

    def test_a_read_is_covered_by_a_file_input_or_the_configuration_and_nothing_else(self):
        recorded = self.recorded(FILE, EXISTS)
        gaps = audit.unrecorded({"/p/main.selka", "/p/other.selka", "/p/selka.json", "/p/probe.txt"}, set(), set(), recorded, {"/p/selka.json"})
        self.assertEqual(gaps["reads"], ["/p/other.selka", "/p/probe.txt"])

    def test_a_path_looked_for_is_covered_by_an_absent_file_an_exists_probe_or_a_read_file(self):
        recorded = self.recorded(FILE, ABSENT, EXISTS)
        gaps = audit.unrecorded(set(), {"/p/missing.selka", "/p/probe.txt", "/p/main.selka", "/p/unknown.selka"}, set(), recorded, set())
        self.assertEqual(gaps["probes"], ["/p/unknown.selka"])

    def test_a_listed_directory_needs_a_listing_input(self):
        recorded = self.recorded(FILE, LISTING)
        gaps = audit.unrecorded(set(), set(), {"/p", "/p/sub"}, recorded, set())
        self.assertEqual(gaps["listings"], ["/p/sub"])

    def test_nothing_recorded_leaves_every_access_unrecorded(self):
        gaps = audit.unrecorded({"/p/main.selka"}, {"/p/x"}, {"/p"}, self.recorded(), set())
        self.assertEqual((gaps["reads"], gaps["probes"], gaps["listings"]), (["/p/main.selka"], ["/p/x"], ["/p"]))


if __name__ == "__main__":
    unittest.main()

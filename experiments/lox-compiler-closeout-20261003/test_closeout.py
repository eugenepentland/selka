"""Host-only refusal/arithmetic and private synthetic archive lifecycle tests."""
import copy
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

from archive import create, inventory, regular_files, verify
from validation import FOUR, SIX, FOCUSED, checked_samples, paired, protocol, same_math, sha


class ReceiptTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        source, expected = root / "case.lox", root / "expected.out"
        source.write_text("print 1;\n")
        expected.write_text("1\n")
        self.names = {"case" + str(index) for index in range(13)}
        self.manifest = {"binary_sha256": {arm: "identity-" + arm for arm in SIX}}
        self.cases = [{"id": engine + "/" + name, "engine": engine, "name": name,
                       "script": str(source), "script_sha256": sha(source), "expected": str(expected)}
                      for engine in ("vm", "tree") for name in sorted(self.names)]

    def document(self, phase="counters", rounds=1, arms=FOUR):
        rows = []
        for case in self.cases:
            for arm in sorted(arms):
                for index in range(rounds):
                    row = {"case": case["id"], "arm": arm, "round": index, "status": 0,
                           "stdout_sha256": sha(case["expected"]), "wall_s": 1.0, "stderr": ""}
                    if phase == "check":
                        row["stderr"] = "[stats] engine=" + case["engine"] + " allocations=3 collections=0 freed=0 live=3\n"
                        row["collector_stats"] = {"allocations": 3, "collections": 0, "freed": 0, "live": 3}
                    elif phase == "counters":
                        for event in ("instructions", "cycles", "branches", "branch-misses"):
                            row[event] = 100
                            row[event + "_running_pct"] = 100.0
                    rows.append(row)
        return {"verified_after": True, "phase": phase, "rounds": rounds,
                "manifest": self.manifest, "cases": self.cases, "samples": rows,
                "binary_sha256": {arm: self.manifest["binary_sha256"][arm] for arm in arms}}

    def checked(self, doc, phase="counters", rounds=1, arms=FOUR):
        return checked_samples(doc, self.manifest, self.names, phase, rounds, arms)

    def test_valid_protocol_cardinalities(self):
        for phase, rounds, arms, count in [("check", 1, SIX, 156), ("counters", 1, FOUR, 104),
                                           ("time", 3, SIX, 468), ("counters", 3, SIX, 468)]:
            doc = self.document(phase, rounds, arms)
            self.assertEqual(len(doc["samples"]), count)
            self.checked(doc, phase, rounds, arms)

    def test_duplicate_cell_cannot_replace_missing_cell(self):
        doc = self.document()
        doc["samples"][-1] = copy.deepcopy(doc["samples"][0])
        with self.assertRaisesRegex(ValueError, "missing or duplicate"):
            self.checked(doc)

    def test_focused24_scope_is_distinct_and_exact(self):
        self.names |= {"equality", "string_equality"}
        self.cases = [dict(self.cases[0], id=name, engine="vm", name=name.split("/")[1]) for name in sorted(FOCUSED)]
        doc = self.document("time", 3, FOUR)
        self.assertEqual(len(doc["samples"]), 24)
        checked_samples(doc, self.manifest, self.names, "time", 3, FOUR, FOCUSED)
        result = paired(doc, "baseline-qbe", "candidate-qbe", "wall_s")
        self.assertEqual(set(result["engines"]), {"vm"})
        self.assertEqual(result["engines"]["vm"]["cases"], 2)
        with self.assertRaisesRegex(ValueError, "case coverage"):
            self.checked(doc, "time", 3, FOUR)
        doc["samples"].pop()
        with self.assertRaisesRegex(ValueError, "missing or duplicate"):
            checked_samples(doc, self.manifest, self.names, "time", 3, FOUR, FOCUSED)

    def test_unknown_completed_phase_and_scope_refused(self):
        for phase, rounds, arms in [("rss", 3, SIX), ("time", 1, FOUR), ("counters", 3, FOUR)]:
            doc = self.document(phase, rounds, arms)
            with self.subTest(phase=phase, rounds=rounds), self.assertRaisesRegex(ValueError, "unsupported"):
                protocol(doc)
        with self.assertRaisesRegex(ValueError, "incomplete"):
            protocol({"phase": "time", "verified_after": True})

    def test_partial_and_wrong_ELF_refused(self):
        for change in ("partial", "ELF", "input", "output", "status"):
            doc = self.document()
            if change == "partial":
                doc["verified_after"] = False
            elif change == "ELF":
                doc["binary_sha256"]["candidate-qbe"] = "different"
            elif change == "input":
                doc["cases"] = copy.deepcopy(doc["cases"])
                doc["cases"][0]["script_sha256"] = "different"
            elif change == "output":
                doc["samples"][0]["stdout_sha256"] = "different"
            else:
                doc["samples"][0]["status"] = False
            with self.subTest(change=change), self.assertRaises(ValueError):
                self.checked(doc)

    def test_each_PMU_must_run_fully(self):
        for event in ("instructions", "cycles", "branches", "branch-misses"):
            doc = self.document()
            doc["samples"][0][event + "_running_pct"] = 99.99
            with self.subTest(event=event), self.assertRaisesRegex(ValueError, "PMU"):
                self.checked(doc)

    def test_diagnostics_and_inconsistent_smoke_stats_refused(self):
        doc = self.document("check", 1, SIX)
        doc["samples"][0]["stderr"] = "warning\n" + doc["samples"][0]["stderr"]
        with self.assertRaisesRegex(ValueError, "diagnostic"):
            self.checked(doc, "check", 1, SIX)
        doc = self.document("check", 1, SIX)
        doc["samples"][0]["stderr"] = doc["samples"][0]["stderr"].replace("live=3", "live=2")
        doc["samples"][0]["collector_stats"]["live"] = 2
        with self.assertRaisesRegex(ValueError, "stats differ"):
            self.checked(doc, "check", 1, SIX)

    def test_independent_paired_median_and_geomean(self):
        doc = self.document("time", 3, SIX)
        for row in doc["samples"]:
            if row["arm"] == "candidate-llvm":
                row["wall_s"] = [0.5, 1.0, 2.0][row["round"]]
        result = paired(doc, "baseline-llvm", "candidate-llvm", "wall_s")
        self.assertEqual(result["engines"]["vm"]["reduction_pct"], 0.0)
        self.assertEqual(result["rows"]["vm/case0"]["spread_pct"], 150.0)
        altered = copy.deepcopy(result)
        altered["engines"]["vm"]["reduction_pct"] = 1.0
        self.assertFalse(same_math(result, altered))
        self.assertTrue(same_math(result, json.loads(json.dumps(result))))


class InventoryTests(unittest.TestCase):
    def test_only_build_caches_excluded_and_guards_override(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in ("source/target/keep", "rust/Cargo.toml", "rust/target/build", "cache-rebuilt-qbe/drop", "ordinary"):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(name)
            retained = {str(path.relative_to(root)) for path in regular_files(root)}
            self.assertEqual(retained, {"source/target/keep", "rust/Cargo.toml", "ordinary"})
            guard = root / "cache-rebuilt-qbe/drop"
            snapshot = inventory(root, {str(guard): sha(guard)}, [], [])
            self.assertIn(str(guard), snapshot)
            self.assertEqual(len(snapshot), 4)


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="compiler-closeout-synthetic-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.work = self.root / "work"
        self.work.mkdir()
        self.source = self.work / "receipt.json"
        self.source.write_text('{"synthetic": true}\n')
        self.extra = self.root / "extra.json"
        self.extra.write_bytes(self.source.read_bytes())
        self.guards = {str(self.source): sha(self.source)}
        self.report = {"synthetic_test_only": True, "performance_selection_inferred": False}
        self.destination = self.root / "sealed"

    def seal(self):
        return create(self.work, self.guards, [self.extra], self.report, self.destination, [])

    def test_create_deduplicate_relocate_and_original_identity(self):
        result = self.seal()
        self.assertEqual(result["objects_verified"], 1)
        self.assertEqual(result["original_paths_recorded"], 2)
        self.assertTrue(result["original_identities_checked"])
        relocated = self.root / "relocated"
        shutil.copytree(self.destination, relocated)
        checked = verify(relocated, expected_manifest=result["manifest_sha256"])
        self.assertFalse(checked["original_identities_checked"])
        self.source.write_text("changed original\n")
        verify(relocated)
        with self.assertRaisesRegex(ValueError, "original changed"):
            verify(relocated, originals=True)
        with self.assertRaisesRegex(ValueError, "manifest identity"):
            verify(relocated, expected_manifest="0" * 64)

    def test_corruption_missing_extra_objects_and_symlinks_refused(self):
        self.seal()
        digest = sha(self.source)
        for fault in ("bytes", "missing", "extra", "symlink"):
            relocated = self.root / fault
            shutil.copytree(self.destination, relocated)
            obj = relocated / "objects" / digest[:2] / digest
            if fault == "bytes":
                obj.write_text("corrupt\n")
            elif fault == "missing":
                obj.unlink()
            elif fault == "extra":
                additional = relocated / "objects" / "00" / ("0" * 64)
                additional.parent.mkdir(exist_ok=True)
                additional.write_bytes(b"")
            else:
                obj.unlink()
                obj.symlink_to(self.source)
            with self.subTest(fault=fault), self.assertRaises(ValueError):
                verify(relocated)

    def test_evidence_growth_fails_and_preserves_failed_staging(self):
        calls = 0

        def growing_inventory(*args):
            nonlocal calls
            calls += 1
            if calls == 2:
                (self.work / "new.log").write_text("new evidence\n")
            return inventory(*args)

        with patch("archive.inventory", growing_inventory), self.assertRaisesRegex(ValueError, "archive failed"):
            self.seal()
        self.assertFalse(self.destination.exists())
        retained = list(self.root.glob("sealed.pending-*"))
        self.assertEqual(len(retained), 1)
        self.assertTrue((retained[0] / "FAILED.json").is_file())
        with self.assertRaisesRegex(ValueError, "failed"):
            verify(retained[0])

    def test_new_receipt_between_validation_and_archive_refused(self):
        self.report["validated_inventory"] = inventory(self.work, self.guards, [], [])
        (self.work / "unvalidated-phase.json").write_text('{"phase": "time"}\n')
        with self.assertRaisesRegex(ValueError, "after validation"):
            self.seal()
        self.assertFalse(self.destination.exists())

    def test_overwrite_nested_destination_and_changed_symlink_refused(self):
        link = self.work / "receipt-link.json"
        link.symlink_to(self.extra)
        result = self.seal()
        with self.assertRaisesRegex(ValueError, "overwrite"):
            self.seal()
        with self.assertRaisesRegex(ValueError, "inside an evidence root"):
            create(self.work, self.guards, [], self.report, self.work / "nested", [])
        copy = self.root / "identical-extra.json"
        copy.write_bytes(self.extra.read_bytes())
        link.unlink()
        link.symlink_to(copy)
        with self.assertRaisesRegex(ValueError, "symlink identity"):
            verify(self.destination, originals=True, expected_manifest=result["manifest_sha256"])


if __name__ == "__main__":
    unittest.main()

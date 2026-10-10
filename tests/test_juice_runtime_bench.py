#!/usr/bin/env python3
"""Integrity checks for alternating native-capture aggregation."""
import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("juice_runtime_bench", Path(__file__).resolve().parents[1] / "scripts/juice_runtime_bench.py")
bench = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bench)


class Aggregation(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def capture(self, name, counts):
        folder = self.root / name
        folder.mkdir()
        (folder / "raw.perf").write_text(str(counts))
        cell = dict(correctness={"stdout": "same"},
                    samples=[dict(metrics=dict(instructions=count, cycles=count * 2,
                                               reference_cycles=count * 3)) for count in counts])
        cell["metrics"] = {key: bench.stats([sample["metrics"][key] for sample in cell["samples"]])
                           for key in cell["samples"][0]["metrics"]}
        record = dict(status="complete", name=name, contract={}, context={}, sources={},
                      build_config={}, collector={}, build={"artifacts": {"plain": "same"}},
                      workloads={"w": cell}, evidence={"raw.perf": bench.digest(folder / "raw.perf")})
        path = folder / "record.json"
        bench.write(path, record)
        return path

    def test_all_samples_and_raw_evidence_are_retained(self):
        first = self.capture("one", [100, 102])
        second = self.capture("two", [104, 106])
        combined = bench.combine([first, second], self.root / "joined")
        record = bench.read(combined)
        summary = record["workloads"]["w"]["metrics"]["reference_cycles"]
        self.assertEqual(summary["samples"], [300, 306, 312, 318])
        self.assertEqual(summary["median"], 309)
        self.assertEqual(len(record["derived_from"]), 2)
        for name, digest in record["evidence"].items():
            self.assertEqual(bench.digest(combined.parent / name), digest)

    def test_corrupt_raw_capture_is_rejected(self):
        first = self.capture("one", [100, 102])
        (first.parent / "raw.perf").write_text("changed")
        with self.assertRaisesRegex(ValueError, "modified"):
            bench.combine([first], self.root / "joined")

    def test_context_artifact_and_correctness_changes_are_rejected(self):
        first = self.capture("one", [100, 102])
        second = self.capture("two", [104, 106])
        original = bench.read(second)
        for index, key in enumerate(("context", "artifacts", "correctness")):
            changed = copy.deepcopy(original)
            if key == "context":
                changed[key] = {"cpu": "different"}
            elif key == "artifacts":
                changed["build"][key]["plain"] = "different"
            else:
                changed["workloads"]["w"][key]["stdout"] = "different"
            bench.write(second, changed)
            with self.assertRaises(ValueError):
                bench.combine([first, second], self.root / f"joined-{index}")


if __name__ == "__main__":
    unittest.main()

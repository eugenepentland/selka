#!/usr/bin/env python3
"""Completed-work oracle for the real compiler/test-driver Juice qualification."""
import importlib.util
from pathlib import Path
import unittest

PATH = Path(__file__).resolve().parents[1] / "experiments/development-loop-closeout-20261012/S05/workloads/oracle.py"
spec = importlib.util.spec_from_file_location("development_loop_oracle", PATH)
oracle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(oracle)


class CompletedWork(unittest.TestCase):
    def value(self):
        return {"version": "native-tests-v1", "passed": 2, "failed": 0, "skipped": 0, "cached": 0, "unsupported": 0,
                "tests": [{"name": "cases::test_sum", "status": "passed", "reason": ""},
                          {"name": "cases::test_values", "status": "passed", "reason": ""}]}

    def test_exact_fresh_work_passes(self):
        self.assertIsNone(oracle.validate(self.value()))

    def test_cached_or_incomplete_work_cannot_satisfy_units(self):
        for changed in ({"passed": 1, "cached": 1}, {"tests": []}, {"failed": 1}, {"cached": False}):
            value = self.value()
            value.update(changed)
            with self.assertRaises(ValueError):
                oracle.validate(value)

    def test_wrong_or_duplicate_test_inventory_is_rejected(self):
        value = self.value()
        value["tests"][1] = value["tests"][0]
        with self.assertRaises(ValueError):
            oracle.validate(value)


if __name__ == "__main__":
    unittest.main()

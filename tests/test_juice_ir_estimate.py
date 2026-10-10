#!/usr/bin/env python3
"""Algebraic counts, refusal boundaries, dependency modeling and timing oracle."""
import importlib.util
from pathlib import Path
import random
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXPERIMENT = ROOT / "experiments/juice-ir-proxy-20261010"
spec = importlib.util.spec_from_file_location("ir_evaluate", EXPERIMENT / "evaluate.py")
evaluation = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = evaluation
spec.loader.exec_module(evaluation)
est = evaluation.estimator


class Counts(unittest.TestCase):
    def test_affine_counts_against_execution(self):
        # Independent small interpreter is only a test oracle; estimator uses
        # constant-time integer arithmetic even for trillion-iteration loops.
        rng = random.Random(987)
        predicates = {"lt": lambda a,b: a < b, "le": lambda a,b: a <= b,
                      "gt": lambda a,b: a > b, "ge": lambda a,b: a >= b}
        for _ in range(2000):
            a, b, step = rng.randrange(-30, 30), rng.randrange(-30, 30), rng.randrange(1, 8)
            pred = rng.choice(list(predicates))
            if pred in ("gt", "ge"):
                step = -step
            value, count = a, 0
            while predicates[pred](value, b):
                count += 1
                value += step
            self.assertEqual(est.trip_count(est.scalar(a), est.scalar(b), step, pred, "i64").value, count)

    def test_final_increment_overflow_refused(self):
        for a, b, step, pred, ty in [(126, 127, 2, "lt", "i8"),
                                     (127, 127, 1, "le", "i8"),
                                     (1, 0, -2, "gt", "u8")]:
            with self.assertRaises(est.Unknown):
                est.trip_count(est.scalar(a), est.scalar(b), step, pred, ty)

    def test_zero_negative_and_large_counts(self):
        for n in (0, -1, 10**12):
            self.assertEqual(est.trip_count(est.scalar(0), est.scalar(n), 1, "lt", "i64").value, max(0,n))

    def test_nontermination_refused(self):
        for step, pred in [(0, "lt"), (-1, "lt"), (1, "eq")]:
            with self.assertRaises(est.Unknown):
                est.trip_count(est.scalar(0), est.scalar(5), step, pred, "i64")


class CoreIR(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ir = (EXPERIMENT / "optimized-core.ir").read_text()

    def result(self, name, n=None, text=None):
        return est.estimate(self.ir if text is None else text, name, {} if n is None else {0:n})

    def test_symbolic_and_nested_count(self):
        symbolic = self.result("three")
        self.assertEqual(symbolic["status"], "symbolic")
        self.assertIn("param0", symbolic["loops"][0]["iterations_per_entry"]["formula"])
        nested = self.result("nested32", 7)
        self.assertEqual(nested["operation_executions"]["shift_left"]["value"], 7*32*2)
        self.assertEqual(nested["operation_executions"]["shift_right"]["value"], 7*32)
        self.assertEqual(self.result("nested32", 0)["operation_executions"]["shift_left"]["value"], 0)

    def test_independent_chains_overlap(self):
        separate, fused = (self.result(name, 10**12) for name in ("lanes2_separate", "lanes2_fused"))
        self.assertAlmostEqual(fused["cycle_score"]["value"] / separate["cycle_score"]["value"], .5)
        self.assertEqual(fused["operation_executions"]["shift_left"]["value"],
                         separate["operation_executions"]["shift_left"]["value"])

    def test_unsupported_paths_abstain(self):
        for name in ("data_exit", "triangular", "main", "absent"):
            result = self.result(name, 100)
            self.assertEqual(result["status"], "unknown", result)
            self.assertNotIn("cycle_score", result)

    def test_unsigned_and_checked_boundaries(self):
        result = self.result("three", 1 << 63)
        self.assertEqual(result["status"], "unknown")
        altered = self.ir.replace("shift_left.proven", "shift_left.exact")
        self.assertEqual(self.result("three", 7, altered)["status"], "unknown")

    def test_unsupported_op_never_counts_as_free(self):
        altered = self.ir.replace("bit_xor i64", "opaque_runtime i64")
        result = self.result("three", 7, altered)
        self.assertEqual(result["status"], "unknown")
        self.assertIn("unsupported operation", result["reason"])

    def test_descending_loop_and_reversed_pred_order(self):
        ir = """fn down(i64) -> i64
b0:
  jump b1
b1: ; preds b2 b0
  %1 = phi i64 %3, 10:i64
  %2 = cmp.gt bool %1, param0
  branch %2, b2, b3
b2: ; preds b1
  %3 = sub.proven i64 %1, 3:i64
  jump b1
b3: ; preds b1
  ret %1
b4:
"""
        result = est.estimate(ir, "down", {0:2})
        self.assertEqual(result["status"], "estimated")
        self.assertEqual(result["loops"][0]["iterations_per_entry"]["value"], 3)
        self.assertEqual(result["block_executions"]["1"]["value"], 4)
        self.assertNotIn("4", result["block_executions"])
        self.assertEqual(est.estimate(ir.replace("jump b1", "jump b4", 1), "down", {0:2})["status"], "unknown")


class Oracle(unittest.TestCase):
    def test_matrix_oracle_against_scalar_execution(self):
        for depth in range(1, 5):
            for count in (0, 1, 2, 7, 31, 93):
                for lanes in (1, 2, 4):
                    values = [17 ^ lane for lane in range(lanes)]
                    for _ in range(count):
                        values = [evaluation.scalar_step(x, depth) for x in values]
                    result = 0
                    for x in values:
                        result ^= x
                    if result >= 1 << 63:
                        result -= 1 << 64
                    arm = dict(seed=17, oracle=dict(depth=depth, steps=count, lanes=lanes))
                    self.assertEqual(evaluation.oracle(arm), result)


if __name__ == "__main__":
    unittest.main()

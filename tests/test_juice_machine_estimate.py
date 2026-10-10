#!/usr/bin/env python3
"""Verify mapping/counts, refusal boundaries, model math and frozen evidence."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXPERIMENT = ROOT / "experiments/juice-machine-proxy-20261010"
OLD = ROOT / "experiments/juice-ir-proxy-20261010"


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    sys.modules[name] = result
    spec.loader.exec_module(result)
    return result


model = module("machine_cost", ROOT / "scripts/juice_machine_estimate.py")
evaluation = module("machine_evaluation", EXPERIMENT / "evaluate.py")


class NativeLoops(unittest.TestCase):
    def sample(self, body="xor rax,rcx", step="add r12,0xfffffffffffffff8", branch="jne 10 <kernel>"):
        return [model.Instruction(0x10, "kernel", body), model.Instruction(0x14, "kernel", step),
                model.Instruction(0x18, "kernel", branch)]

    def test_backend_grouping_and_counter_aliases(self):
        self.assertEqual(model.grouping(self.sample()), 8)
        self.assertEqual(model.grouping(self.sample(step="dec r12")), 1)
        for body in ("xor r12,rax", "xor eax,r12d", "mov r12b,al", "je 14 <kernel+4>"):
            with self.assertRaises(model.Unknown):
                model.grouping(self.sample(body=body))
        for branch in ("jne 14 <kernel+4>", "je 10 <kernel>"):
            with self.assertRaises(model.Unknown):
                model.grouping(self.sample(branch=branch))

    def test_refuse_memory_and_calls(self):
        for instruction in ("mov rax,QWORD PTR [rdi]", "call 100 <helper>", "unknown rax,rcx"):
            with self.assertRaises(model.Unknown):
                model.normalize([model.Instruction(0, "kernel", instruction)])

    def test_latency_override_is_form_specific(self):
        assembly = "mov rax,rcx\nmov rax,rax\nmov eax,ecx\nmov rax,12\nxor rax,rcx\nxor rax,rax\n"
        profile = json.loads((EXPERIMENT / "latency-profile.json").read_text())
        result = model.apply_profile(assembly, profile)
        self.assertEqual(result.count("# LLVM-MCA-LATENCY 0\n"), 1)
        self.assertEqual(result.count("# LLVM-MCA-LATENCY 1\n"), 1)
        self.assertIn("# LLVM-MCA-LATENCY 1\nxor rax,rcx", result)
        self.assertIn("# LLVM-MCA-LATENCY 0\nmov rax,rcx", result)

    def test_steady_state_uses_dependency_cycles(self):
        def report(n, cycles):
            return {"CodeRegions": [{"SummaryView": {"Iterations": n, "TotalCycles": cycles, "BlockRThroughput": 1}}]}
        reports = [report(n, n*7+3) for n in (200,400,800)]
        self.assertEqual(model.fit_cycles(reports), (7, [7,7]))
        reports[-1] = report(800, 10000)
        with self.assertRaises(model.Unknown):
            model.fit_cycles(reports)

    def test_perf_rejects_partial_and_duplicate_measurements(self):
        good = "1000;;cpu_core/cycles/u;4000;100.00;;\n800;;cpu_core/ref-cycles/u;4000;100.00;;\n"
        self.assertEqual(evaluation.counters(good), dict(cycles=1000, reference_cycles=800))
        for bad in (good.replace("100.00", "77.00"), good+good, good.splitlines()[0], good.replace("1000;", "<not counted>;")):
            with self.assertRaises(ValueError):
                evaluation.counters(bad)


class FrozenMapping(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mapping = json.loads((EXPERIMENT / "regions.json").read_text())
        cls.ir = (OLD / "optimized-core.ir").read_text()
        with tarfile.open(EXPERIMENT / "evidence.tar.gz") as archive:
            cls.native = model.disassemble(archive.extractfile("evidence/model02/disassembly.txt").read().decode())

    def prepare(self, function, n, mapping=None):
        return model.prepare(self.ir, function, {0:n,1:17}, mapping or self.mapping, self.native)

    def test_counts_survive_unrolling_and_nesting(self):
        _, rows = self.prepare("three", 160000000)
        self.assertEqual(rows[0]["machine_iterations"], 20000000)
        self.assertEqual(rows[0]["grouping_factor"], 8)
        _, rows = self.prepare("three_unroll4", 40000000)
        self.assertEqual(rows[0]["machine_iterations"], 20000000)
        self.assertEqual(rows[0]["grouping_factor"], 2)
        _, rows = self.prepare("nested32", 5000000)
        self.assertEqual(rows[0]["machine_iterations"], 5000000)
        self.assertEqual(rows[0]["pieces"][1]["expansion"], 4)

    def test_unmapped_tails_and_paths_abstain(self):
        for name,n in (("three", 100003), ("three", 7), ("data_exit", 100000), ("triangular", 100000)):
            with self.assertRaises(model.Unknown):
                self.prepare(name,n)

    def test_missing_loop_and_wrong_symbol_abstain(self):
        bad = copy.deepcopy(self.mapping)
        bad["functions"]["lanes4_separate"]["regions"].pop()
        with self.assertRaises(model.Unknown):
            self.prepare("lanes4_separate", 100000, bad)
        bad = copy.deepcopy(self.mapping)
        bad["functions"]["three"]["regions"][0]["pieces"][0]["symbol"] = "wrong"
        with self.assertRaises(model.Unknown):
            self.prepare("three", 100000, bad)

    def test_different_build_fails_before_invoking_tools(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/"binary"
            path.write_bytes(b"different build")
            result = subprocess.run([sys.executable, str(ROOT/"scripts/juice_machine_estimate.py"),
                "--binary", str(path), "--ir", str(OLD/"optimized-core.ir"), "--map", str(EXPERIMENT/"regions.json"),
                "--suite", str(OLD/"suite.json"), "--mca", "nonexistent-tool", "--output", str(Path(directory)/"out")],
                capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn("exact binary/Core IR", result.stderr)
            self.assertFalse((Path(directory)/"out").exists())


if __name__ == "__main__":
    unittest.main()

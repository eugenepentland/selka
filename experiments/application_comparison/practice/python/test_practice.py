"""Coordinator-only CLI checks; never ship this file with the starter."""

from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parent


def run(variant: str, data: bytes) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-B", str(ROOT / variant / "main.py")],
        input=data, capture_output=True, timeout=5, check=False,
    )


class PracticeTests(unittest.TestCase):
    def test_solution_contract(self):
        cases = [(b"m", 42), (b"d", 9)]
        cases += [(b"f" + bytes([48 + digit]), digit) for digit in range(10)]
        cases += [(data, -1) for data in (
            b"", b"fx", b"f", b"f12", b"f\xff", b"f\xc3\xa9",
            b"f\x00", b"f7\n", b"m\n", b"d ", b" M", b"unknown",
            b"x" * 255, b"x" * 256, b"x" * 257,
            b"f" + b"1" * 255, b"f" + b"1" * 256, b"m" * 4096,
        )]
        for data, expected in cases:
            with self.subTest(data=data[:30], size=len(data)):
                result = run("solution", data)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, f"{expected}\n".encode())
                self.assertEqual(result.stderr, b"")

    def test_starter_has_three_observable_faults(self):
        for data, wrong in ((b"m", b"36\n"), (b"fx", b"0\n")):
            with self.subTest(data=data):
                result = run("starter", data)
                self.assertEqual(result.returncode, 0)
                self.assertEqual(result.stdout, wrong)
                self.assertEqual(result.stderr, b"")
        result = run("starter", b"d")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")
        self.assertIn(b"NameError", result.stderr)
        self.assertIn(b"NINE_VALUE", result.stderr)

    def test_only_three_source_expressions_differ(self):
        starter = (ROOT / "starter" / "main.py").read_text()
        repaired = starter.replace("multiply_by_six(6)", "multiply_by_six(7)")
        repaired = repaired.replace("            return 0\n", "            return -1\n")
        repaired = repaired.replace("return NINE_VALUE", "return NINE")
        self.assertEqual(repaired, (ROOT / "solution" / "main.py").read_text())
        self.assertEqual(
            (ROOT / "starter" / "helper.py").read_bytes(),
            (ROOT / "solution" / "helper.py").read_bytes(),
        )


if __name__ == "__main__":
    unittest.main()

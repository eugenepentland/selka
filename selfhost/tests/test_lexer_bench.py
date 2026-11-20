#!/usr/bin/env python3
"""Smoke test of the lexer throughput harness (`bench/selfhost/lexer_throughput.py`).

    python3 selfhost/tests/test_lexer_bench.py --compiler zig-out/bin/selka

The harness builds the Zig twin with `zig build-exe` and the Selka benchmark with `selka build --release`, runs both
for one round on two files and reports every phase. It takes a minute on a loaded machine, so `zig build
test-selfhost-bench` runs it on request; it is not a dependency of `zig build test` and not a verification action.
"""
from __future__ import annotations

import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parents[1] / "bench" / "selfhost"))

import lexer_throughput  # noqa: E402
import syntax_parity as sp  # noqa: E402

COMPILER = Path(sp.ROOT / "zig-out" / "bin" / "selka")


class ThroughputHarness(unittest.TestCase):
    def test_the_harness_builds_both_arms_and_reports_every_phase(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            names = Path(scratch, "list.txt")
            names.write_text("tests/lang/borrowed_const.selka\nselfhost/corpus/lexer/layout.selka\n")
            out, err = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                status = lexer_throughput.main(["--compiler", str(COMPILER), "--list", str(names), "--rounds", "2", "--sessions", "1", "--out", scratch])
            record = json.loads(Path(scratch, "lexer-throughput.json").read_text())
        self.assertEqual(status, 0, err.getvalue())
        self.assertEqual([r["phase"] for r in record["rows"]], ["tokenize", "layout", "lex"])
        self.assertEqual(record["files"], 2)
        self.assertGreater(record["tokens_after_layout"], 0)
        self.assertEqual(len(record["zig"]), len(record["arms"]["selka"]))


if __name__ == "__main__":
    arguments = sys.argv[1:]
    if "--compiler" in arguments:
        at = arguments.index("--compiler")
        COMPILER = Path(arguments[at + 1]).resolve()
        del arguments[at:at + 2]
    unittest.main(argv=[sys.argv[0], *arguments])

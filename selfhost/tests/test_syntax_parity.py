#!/usr/bin/env python3
"""Tests of the syntax parity harness, and its Zig-against-Zig run over the in-tree corpus.

    python3 selfhost/tests/test_syntax_parity.py --compiler zig-out/bin/selka

The unit tests use a live compiler as the oracle and deliberately broken candidates
(a parser that flips a payload byte, a lexer that drops a token, a command that
fails) to show that a mismatch is found, named and counted. The last test is the
gate: every file of the in-tree corpus, `selka dump-tokens` and `selka dump-syntax`
against themselves, zero mismatches. The Selka lexer's generated tables are checked
against the compiler's, and its own tests (`selka test selfhost/frontend`) are run.
"""
from __future__ import annotations

import contextlib
import io
import json
import shlex
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "tools"))

import gen_lexer_tables  # noqa: E402
import syntax_parity as sp  # noqa: E402

COMPILER = Path(sp.ROOT / "zig-out" / "bin" / "selka")

PROGRAM = "func main() -> int:\n    return 0\n"
MODULE_HEADER = "module main\n\nfunc f() -> int:\n    return 1\n"
LEXICAL_ERROR = "x = $\n"


def run_main(*argv: str) -> tuple[int, str, str]:
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        status = sp.main([*argv, "--compiler", str(COMPILER)])
    return status, out.getvalue(), err.getvalue()


class Scratch(unittest.TestCase):
    def setUp(self) -> None:
        self._holder = tempfile.TemporaryDirectory()
        self.addCleanup(self._holder.cleanup)
        self.dir = Path(self._holder.name)

    def write(self, name: str, text: str) -> Path:
        path = self.dir / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def corpus(self, files: dict[str, str], negative: list[str] | None = None) -> Path:
        for name, text in files.items():
            self.write(f"src/{name}", text)
        return self.write("corpus.json", json.dumps({
            "version": sp.SUPPORTED_CORPUS,
            "roots": [{"name": "scratch", "path": str(self.dir / "src"), "glob": "**/*.selka"}],
            "exclude": ["**/skip/**"],
            "negative": negative or [],
        }))

    def script(self, name: str, body: str) -> str:
        """A candidate command: a Python program that wraps the real compiler."""
        path = self.write(name, "import subprocess, sys\n" + body)
        return f"{shlex.quote(sys.executable)} {shlex.quote(str(path))} {shlex.quote(str(COMPILER))} {{file}}"


class GlobAndCorpus(Scratch):
    def test_glob_translation(self) -> None:
        rx = sp.glob_regex("a/**/*.selka")
        self.assertTrue(rx.match("a/b/c/d.selka"))
        self.assertTrue(rx.match("a/d.selka"))
        self.assertFalse(rx.match("a/d.mx"))
        self.assertFalse(sp.glob_regex("a/*.selka").match("a/b/c.selka"))
        self.assertTrue(sp.glob_regex("**/.*/**").match("x/.hidden/y.selka"))
        self.assertTrue(sp.glob_regex("t?.selka").match("t1.selka"))

    def test_corpus_resolution_sorts_excludes_and_marks_negatives(self) -> None:
        path = self.corpus(
            {"b.selka": PROGRAM, "a.selka": PROGRAM, "skip/c.selka": PROGRAM, ".hidden/d.selka": PROGRAM, "note.txt": "x"},
            negative=["scratch/b.selka"],
        )
        entries, skipped = sp.load_corpus(path, in_tree=False)
        self.assertEqual([e.display for e in entries], ["scratch/a.selka", "scratch/b.selka"])
        self.assertEqual([e.negative for e in entries], [False, True])
        self.assertEqual(skipped, {})

    def test_optional_roots_are_skipped_when_absent_or_in_tree(self) -> None:
        document = {"version": sp.SUPPORTED_CORPUS, "roots": [{"name": "gone", "path": "/no/such/root", "glob": "*.selka", "optional": True}]}
        entries, skipped = sp.load_corpus(self.write("c.json", json.dumps(document)), in_tree=False)
        self.assertEqual((entries, skipped), ([], {"gone": 1}))
        with self.assertRaises(sp.CorpusError):
            sp.load_corpus(self.write("d.json", json.dumps({**document, "version": "other"})), in_tree=False)

    def test_trusted_roots_pass_the_flag(self) -> None:
        document = {"version": sp.SUPPORTED_CORPUS, "roots": [{"name": "std", "path": str(self.dir), "glob": "*.selka", "trusted": True}]}
        self.write("one.selka", PROGRAM)
        entries, _ = sp.load_corpus(self.write("c.json", json.dumps(document)), in_tree=False)
        self.assertEqual(entries[0].flags(), ["--trusted"])


class Frames(Scratch):
    def test_frame_decoding_reads_outcome_diagnostics_and_fix(self) -> None:
        source = self.write("header.selka", MODULE_HEADER)
        ran = sp.execute([str(COMPILER), "dump-syntax", str(source)], sp.ROOT)
        frame = sp.decode_frame(ran.out)
        self.assertEqual((frame.mode, frame.outcome), (1, 1))
        self.assertEqual(frame.payload, b"")
        self.assertEqual(frame.diagnostics[0]["code"], "E_MODULE_HEADER")
        self.assertEqual(frame.diagnostics[0]["fix"], [{"span": (0, 11), "text": ""}])

    def test_a_malformed_frame_is_refused(self) -> None:
        with self.assertRaises(sp.FrameError):
            sp.decode_frame(b"NOTAFRAME")
        with self.assertRaises(sp.FrameError):
            sp.decode_frame(sp.MAGIC + bytes([0, 0, 0]) + (5).to_bytes(8, "little") + b"ab")


class Candidates(Scratch):
    def test_the_compiler_against_itself_matches(self) -> None:
        path = self.corpus({"p.selka": PROGRAM, "m.selka": MODULE_HEADER, "lex.selka": LEXICAL_ERROR}, negative=["scratch/m.selka", "scratch/lex.selka"])
        status, out, err = run_main("--corpus", str(path), "--self")
        self.assertEqual((status, err), (0, ""))
        self.assertIn("lexer: 3 compared, 0 mismatches", out)
        self.assertIn("parser: 3 compared, 0 mismatches", out)
        self.assertIn("1 parsed, 2 refused", out)

    def test_a_negative_fixture_the_reference_accepts_is_a_corpus_error(self) -> None:
        path = self.corpus({"p.selka": PROGRAM}, negative=["scratch/p.selka"])
        status, _, err = run_main("--corpus", str(path), "--self")
        self.assertEqual(status, 2)
        self.assertIn("negative fixtures the reference accepts: scratch/p.selka", err)

    def test_a_parser_that_flips_a_payload_byte_is_named_by_field(self) -> None:
        # Byte 10 of the frame is the outcome; the payload starts after the 8-byte length at 11.
        flipper = self.script("flip.py", (
            "out = subprocess.run([sys.argv[1], 'dump-syntax', sys.argv[2]], capture_output=True).stdout\n"
            "out = bytearray(out)\n"
            "out[19 + 8] ^= 1\n"
            "sys.stdout.buffer.write(bytes(out))\n"
        ))
        path = self.corpus({"p.selka": PROGRAM})
        report = self.dir / "report.json"
        status, out, _ = run_main("--corpus", str(path), "--parser", flipper, "--json", str(report))
        self.assertEqual(status, 1)
        self.assertIn("parser: 1 compared, 1 mismatches", out)
        self.assertIn("scratch/p.selka: payload differs at byte 8 in types.domains.@len", out)
        record = json.loads(report.read_text())["files"][0]
        self.assertEqual(record["mismatches"][0]["kind"], "parser")

    def test_a_parser_that_fails_or_reports_the_wrong_mode_is_a_mismatch(self) -> None:
        failing = self.script("fail.py", "sys.stderr.write('boom\\n')\nsys.exit(3)\n")
        path = self.corpus({"p.selka": PROGRAM})
        status, out, _ = run_main("--corpus", str(path), "--parser", failing)
        self.assertEqual(status, 1)
        self.assertIn("exit status 3 (boom)", out)
        wrong_mode = self.script("mode.py", (
            "out = bytearray(subprocess.run([sys.argv[1], 'dump-syntax', sys.argv[2]], capture_output=True).stdout)\n"
            "out[8] = 1\n"
            "sys.stdout.buffer.write(bytes(out))\n"
        ))
        status, out, _ = run_main("--corpus", str(path), "--parser", wrong_mode)
        self.assertEqual(status, 1)
        self.assertIn("mode: reference program, candidate module", out)

    def test_a_lexer_that_drops_a_token_or_misreports_a_failure_is_a_mismatch(self) -> None:
        dropper = self.script("drop.py", (
            "import json\n"
            "doc = json.loads(subprocess.run([sys.argv[1], 'dump-tokens', sys.argv[2]], capture_output=True).stdout)\n"
            "doc['tokens'].pop(2)\n"
            "doc['count'] -= 1\n"
            "sys.stdout.write(json.dumps(doc, separators=(',', ':')))\n"
        ))
        path = self.corpus({"p.selka": PROGRAM})
        status, out, _ = run_main("--corpus", str(path), "--lexer", dropper)
        self.assertEqual(status, 1)
        self.assertIn("lexer: 1 compared, 1 mismatches", out)
        self.assertIn("token 2:", out)
        silent = self.script("silent.py", "sys.exit(0)\n")
        bad = self.corpus({"lex.selka": LEXICAL_ERROR}, negative=["scratch/lex.selka"])
        status, out, _ = run_main("--corpus", str(bad), "--lexer", silent)
        self.assertEqual(status, 1)
        self.assertIn("exit status 0, reference 1", out)

    def test_filters_and_the_listing(self) -> None:
        path = self.corpus({"p.selka": PROGRAM, "q.selka": PROGRAM})
        status, out, _ = run_main("--corpus", str(path), "--list", "--filter", "q.selka")
        self.assertEqual((status, out.split()), (0, ["scratch/q.selka"]))


class SelkaLexer(unittest.TestCase):
    def test_generated_token_tables_are_current(self) -> None:
        status = gen_lexer_tables.main(["--check", "--compiler", str(COMPILER)])
        self.assertEqual(status, 0, "selfhost/frontend/{token_kinds,keywords}.selka differ from `selka dump-tokens --tables`")

    def test_the_selka_lexer_tests_pass(self) -> None:
        with tempfile.TemporaryDirectory() as cache:
            done = subprocess.run([str(COMPILER), "test", "selfhost/frontend", "--cache-dir", cache], cwd=sp.ROOT, capture_output=True, text=True)
        self.assertEqual(done.returncode, 0, done.stdout[-2000:] + done.stderr[-2000:])
        self.assertRegex(done.stdout, r"\d+ passed, \d+ cached, 0 failed")


    def test_the_selka_lexer_matches_the_zig_lexer_over_the_in_tree_corpus(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            program = Path(scratch, "lexer_cli")
            built = subprocess.run(
                [str(COMPILER), "build", "selfhost/frontend/lexer_cli.selka", "-o", str(program), "--cache-dir", str(Path(scratch, "cache"))],
                cwd=sp.ROOT, capture_output=True, text=True)
            self.assertEqual(built.returncode, 0, built.stdout[-2000:] + built.stderr[-2000:])
            status, out, err = run_main("--lexer", f"{shlex.quote(str(program))} {{file}}", "--in-tree", "--jobs", "4")
        self.assertEqual((status, err), (0, ""), out)
        self.assertRegex(out, r"lexer: \d+ compared, 0 mismatches")


class SelkaWorker(unittest.TestCase):
    def test_the_selka_worker_frame_tests_pass(self) -> None:
        with tempfile.TemporaryDirectory() as cache:
            done = subprocess.run([str(COMPILER), "test", "selfhost/worker", "--cache-dir", cache], cwd=sp.ROOT, capture_output=True, text=True)
        self.assertEqual(done.returncode, 0, done.stdout[-2000:] + done.stderr[-2000:])
        self.assertRegex(done.stdout, r"\d+ passed, \d+ cached, 0 failed")


class InTreeCorpus(unittest.TestCase):
    def test_zig_against_itself_has_zero_mismatches_over_the_in_tree_corpus(self) -> None:
        status, out, err = run_main("--self", "--in-tree", "--jobs", "4")
        self.assertEqual((status, err), (0, ""), out)
        self.assertIn("lexer: ", out)
        self.assertRegex(out, r"parser: \d+ compared, 0 mismatches")
        self.assertRegex(out, r"lexer: \d+ compared, 0 mismatches")


if __name__ == "__main__":
    arguments = sys.argv[1:]
    if "--compiler" in arguments:
        at = arguments.index("--compiler")
        COMPILER = Path(arguments[at + 1]).resolve()
        del arguments[at:at + 2]
    unittest.main(argv=[sys.argv[0], *arguments])

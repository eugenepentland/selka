#!/usr/bin/env python3
"""Tests for scripts/fact_proof.py: the pure parts and both checks, with a stand-in for the compiler."""
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path

sys.path[:0] = [str(Path(__file__).resolve().parent)]
import fact_proof as proof  # noqa: E402

SUMMARY = "summary files=2 functions=5 accept=5 reject=0 errors=0 derived=40 assumed=3 proven=9 unchecked=1\n"

# A stand-in `selka`: lowering prints a certificate, mutating writes two mutants of the first function, validating accepts
# everything but a mutant file named by $FACT_PROOF_ACCEPT, which it leaves accepted.
STANDIN = """\
import os, sys
command = sys.argv[1]
if command == "dump-ir":
    print("fact-certificate-v1")
elif command == "mutate-fact-certificates":
    out = sys.argv[3]
    os.makedirs(out, exist_ok=True)
    for name in ("0.fact-certificate", "1.fact-certificate"):
        open(os.path.join(out, name), "w").write("fact-certificate-v1\\n")
    print("0.fact-certificate narrow_range main")
    print("1.fact-certificate loop_range main")
elif command == "validate-fact-certificates":
    target = sys.argv[2]
    if os.path.isdir(target) and any(n.startswith("0.") for n in os.listdir(target)):
        accept = os.environ.get("FACT_PROOF_ACCEPT", "")
        for name in ("0.fact-certificate", "1.fact-certificate"):
            verdict = "accept" if name == accept else "reject F2 b0 %1"
            print(f"{target}/{name} main {verdict}")
            print(f"{target}/{name} helper accept")
        print("summary files=2 functions=4 accept=2 reject=2 errors=0 derived=1 assumed=0 proven=0 unchecked=0")
        sys.exit(1)
    print("summary files=%s functions=5 accept=5 reject=0 errors=0 derived=40 assumed=3 proven=9 unchecked=1" % os.environ.get("FACT_PROOF_FILES", "2"))
"""


class Pure(unittest.TestCase):
    def test_the_summary_line_is_read_whatever_comes_before_it(self):
        counts = proof.parse_summary("x main accept\n" + SUMMARY)
        self.assertEqual((counts["files"], counts["functions"], counts["proven"], counts["unchecked"]), (2, 5, 9, 1))
        with self.assertRaises(proof.FactError):
            proof.parse_summary("x main accept\n")

    def test_a_manifest_and_the_verdicts_are_read_per_file_and_function(self):
        manifest = proof.manifest_of("0.fact-certificate narrow_range main\n1.fact-certificate loop_range f g\n")
        self.assertEqual(manifest, [("0.fact-certificate", "narrow_range", "main"), ("1.fact-certificate", "loop_range", "f g")])
        verdicts = proof.verdicts_of("/t/0.fact-certificate main reject F2 b0 %1\n/t/0.fact-certificate helper accept\nsummary files=1\n")
        self.assertEqual(verdicts, {("0.fact-certificate", "main"): True, ("0.fact-certificate", "helper"): False})

    def test_an_accepted_mutant_and_a_rejection_in_another_function_are_both_problems(self):
        manifest = [("0.fact-certificate", "narrow_range", "main")]
        good = {("0.fact-certificate", "main"): True, ("0.fact-certificate", "helper"): False}
        self.assertEqual(proof.judge_mutants(manifest, good, "p"), [])
        accepted = {("0.fact-certificate", "main"): False, ("0.fact-certificate", "helper"): False}
        self.assertIn("accepted mutant p/0.fact-certificate", proof.judge_mutants(manifest, accepted, "p")[0])
        misplaced = {("0.fact-certificate", "main"): True, ("0.fact-certificate", "helper"): True}
        self.assertIn("rejected helper", proof.judge_mutants(manifest, misplaced, "p")[0])


class WithStandIn(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = Path(self.directory.name)
        script = root / "standin.py"
        script.write_text(STANDIN)
        self.compiler = root / "selka"
        self.compiler.write_text(f"#!/bin/sh\nexec {sys.executable} {script} \"$@\"\n")
        self.compiler.chmod(self.compiler.stat().st_mode | stat.S_IEXEC)
        self.fixtures = root / "fixtures"
        self.fixtures.mkdir()
        (self.fixtures / "p.selka").write_text("func main() -> int:\n    return 0\n")

    def test_the_corpus_is_accepted_and_counted(self):
        counts = proof.corpus_check(str(self.compiler), Path(self.directory.name))
        self.assertEqual((counts["files"], counts["reject"]), (2, 0))

    def test_a_corpus_with_no_fact_certificate_fails(self):
        os.environ["FACT_PROOF_FILES"] = "0"
        self.addCleanup(os.environ.pop, "FACT_PROOF_FILES", None)
        with self.assertRaises(proof.FactError) as caught:
            proof.corpus_check(str(self.compiler), Path(self.directory.name))
        self.assertIn("no fact certificates", str(caught.exception))

    def test_every_mutant_rejected_in_its_own_function_passes_until_the_classes_run_short(self):
        scratch = Path(self.directory.name) / "scratch"
        with self.assertRaises(proof.FactError) as caught:
            proof.mutant_check(str(self.compiler), scratch, fixtures=self.fixtures)
        self.assertIn("of 9 fault classes", str(caught.exception))

    def test_an_accepted_mutant_fails_the_check_and_names_it(self):
        os.environ["FACT_PROOF_ACCEPT"] = "1.fact-certificate"
        self.addCleanup(os.environ.pop, "FACT_PROOF_ACCEPT", None)
        with self.assertRaises(proof.FactError) as caught:
            proof.mutant_check(str(self.compiler), Path(self.directory.name) / "scratch", fixtures=self.fixtures)
        self.assertIn("accepted mutant p.selka/1.fact-certificate (loop_range in main)", str(caught.exception))


# A stand-in `lake`: `build` prints $FACT_PROOF_LAKE_BUILD and exits 0. A stand-in Lean checker prints $FACT_PROOF_LEAN.
LAKE = """\
import os, sys
if sys.argv[1] == "build":
    print(os.environ.get("FACT_PROOF_LAKE_BUILD", ""))
"""
FACTCHECK = """\
import os, sys
sys.stdout.write(os.environ.get("FACT_PROOF_LEAN", ""))
"""

AGREE = "/t/a.fact-certificate main accept\n/t/a.fact-certificate helper accept\nsummary files=1 functions=2 accept=2 reject=0 errors=0 derived=1 assumed=0 proven=0 unchecked=0\n"


class Lean(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = Path(self.directory.name)
        script = root / "lake.py"
        script.write_text(LAKE)
        self.lake = root / "lake"
        self.lake.write_text(f"#!/bin/sh\nexec {sys.executable} {script} \"$@\"\n")
        self.lake.chmod(self.lake.stat().st_mode | stat.S_IEXEC)
        compiler = root / "standin.py"
        compiler.write_text("import sys\nsys.stdout.write(%r)\n" % AGREE)
        self.compiler = root / "selka"
        self.compiler.write_text(f"#!/bin/sh\nexec {sys.executable} {compiler} \"$@\"\n")
        self.compiler.chmod(self.compiler.stat().st_mode | stat.S_IEXEC)
        for name in ("FACT_PROOF_LAKE_BUILD", "FACT_PROOF_LEAN"):
            self.addCleanup(os.environ.pop, name, None)
        # a project directory whose built checker is the stand-in
        project = root / "project"
        binary = project / ".lake" / "build" / "bin"
        binary.mkdir(parents=True)
        (project / "factcheck.py").write_text(FACTCHECK)
        checker = binary / "factcheck"
        checker.write_text(f"#!/bin/sh\nexec {sys.executable} {project / 'factcheck.py'} \"$@\"\n")
        checker.chmod(checker.stat().st_mode | stat.S_IEXEC)
        self.project = project
        self.addCleanup(setattr, proof, "PROOFS", proof.PROOFS)
        proof.PROOFS = project

    def test_the_lean_tool_is_found_or_the_action_fails_naming_it(self):
        self.assertEqual(proof.find_lake({"SELKA_LAKE": str(self.lake)}), str(self.lake))
        with self.assertRaises(proof.FactError) as caught:
            proof.find_lake({"HOME": "/nonexistent"})
        self.assertIn("never skips", str(caught.exception))

    def test_a_sorry_or_an_error_in_the_build_fails_it(self):
        proof.lake_build(str(self.lake))
        os.environ["FACT_PROOF_LAKE_BUILD"] = "warning: Facts/Inv.lean:1:1: declaration uses `sorry`"
        with self.assertRaises(proof.FactError) as caught:
            proof.lake_build(str(self.lake))
        self.assertIn("lake build", str(caught.exception))
        os.environ["FACT_PROOF_LAKE_BUILD"] = "error: Facts/Inv.lean:1:1: unknown identifier"
        with self.assertRaises(proof.FactError):
            proof.lake_build(str(self.lake))

    def test_a_build_that_leaves_no_checker_fails(self):
        (self.project / ".lake" / "build" / "bin" / "factcheck").unlink()
        with self.assertRaises(proof.FactError) as caught:
            proof.run_factcheck(str(self.lake), Path("."))
        self.assertIn("did not build the Lean checker", str(caught.exception))

    def test_two_outputs_are_the_same_or_the_differing_lines_are_named(self):
        self.assertEqual(proof.differences(AGREE, AGREE), [])
        other = AGREE.replace("helper accept", "helper reject F2 b0 %1")
        found = proof.differences(AGREE, other)
        self.assertEqual(len(found), 1)
        self.assertIn("helper reject F2 b0 %1", found[0])
        self.assertEqual(len(proof.differences(AGREE, AGREE + "x\n")), 1)

    def test_the_corpus_needs_the_lean_checker_to_print_the_same_lines(self):
        os.environ["FACT_PROOF_LEAN"] = AGREE
        counts = proof.corpus_check(str(self.compiler), Path(self.directory.name), lake=str(self.lake))
        self.assertEqual(counts["lean"], 2)
        os.environ["FACT_PROOF_LEAN"] = AGREE.replace("helper accept", "helper reject F2 b0 %1")
        with self.assertRaises(proof.FactError) as caught:
            proof.corpus_check(str(self.compiler), Path(self.directory.name), lake=str(self.lake))
        self.assertIn("disagree", str(caught.exception))

    def test_the_fixtures_must_get_their_expected_verdicts(self):
        fixtures = Path(self.directory.name) / "fx"
        fixtures.mkdir()
        (fixtures / "a.fact-certificate").write_text("fact-certificate-v1\n")
        (fixtures / "a.expected").write_text("f accept\n")
        os.environ["FACT_PROOF_LEAN"] = "/p/fx/a.fact-certificate f accept\nsummary files=1\n"
        self.assertEqual(proof.fixtures_check(str(self.lake), directory=fixtures), 1)
        os.environ["FACT_PROOF_LEAN"] = "/p/fx/a.fact-certificate f reject F2 b0 %1\nsummary files=1\n"
        with self.assertRaises(proof.FactError) as caught:
            proof.fixtures_check(str(self.lake), directory=fixtures)
        self.assertIn("a.fact-certificate", str(caught.exception))
        (fixtures / "b.fact-certificate").write_text("fact-certificate-v1\n")
        with self.assertRaises(proof.FactError) as caught:
            proof.fixture_expectations(fixtures)
        self.assertIn("no .expected", str(caught.exception))

    def test_the_real_fixtures_are_all_described(self):
        expected = proof.fixture_expectations()
        self.assertGreaterEqual(len(expected), 12)
        for name, lines in expected.items():
            self.assertTrue(lines and all(line.split(" ")[1] in ("accept", "reject") for line in lines), name)

    def test_the_shared_fixtures_expect_a_shift_with_a_mistyped_left_operand_to_be_refused_as_the_lean_checker_does(self):
        expected = proof.fixture_expectations(proof.SHARED_FIXTURES)
        self.assertEqual(expected["shift_left_type_f1.fact-certificate"], ["f reject F1 b- -"])
        self.assertEqual(expected["shift_left_count_ok.fact-certificate"], ["f accept"])


# A stand-in for both checkers that accepts every certificate file under its target and logs the target it was given.
WALKER = """\
import os, sys
args = sys.argv[1:]
target = args[1] if args and args[0] == "validate-fact-certificates" else args[0]
names = sorted(os.path.join(d, f) for d, _, fs in os.walk(target) for f in fs if f.endswith(".fact-certificate"))
with open(os.environ["FACT_PROOF_LOG"], "a") as log:
    log.write(" ".join(os.path.relpath(n, target) for n in names) + "\\n")
for n in names:
    print(n, "main accept")
print("summary files=%d functions=%d accept=%d reject=0 errors=0 derived=0 assumed=0 proven=0 unchecked=0" % (len(names), len(names), len(names)))
"""


class Cached(unittest.TestCase):
    """A file whose digest the store has a verdict for under this pair of checkers is not checked again."""

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = Path(self.directory.name)
        script = root / "walker.py"
        script.write_text(WALKER)
        self.log = root / "log"
        os.environ["FACT_PROOF_LOG"] = str(self.log)
        self.addCleanup(os.environ.pop, "FACT_PROOF_LOG", None)
        self.compiler = root / "selka"
        self.compiler.write_text(f"#!/bin/sh\nexec {sys.executable} {script} \"$@\"\n")
        self.compiler.chmod(self.compiler.stat().st_mode | stat.S_IEXEC)
        project = root / "project"
        binary = project / ".lake" / "build" / "bin"
        binary.mkdir(parents=True)
        checker = binary / "factcheck"
        checker.write_text(f"#!/bin/sh\nexec {sys.executable} {script} \"$@\"\n")
        checker.chmod(checker.stat().st_mode | stat.S_IEXEC)
        self.addCleanup(setattr, proof, "PROOFS", proof.PROOFS)
        proof.PROOFS = project
        self.corpus = root / "corpus"
        for name in ("a/p.fact-certificate", "b/p.fact-certificate"):
            (self.corpus / name).parent.mkdir(parents=True)
            (self.corpus / name).write_text("fact-certificate-v1\n" + name + "\n")
        import ownership_verdict_store as store_module
        self.store = store_module.VerdictStore(root / "store")

    def calls(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def check(self, identity="x" * 64):
        return proof.corpus_check(str(self.compiler), self.corpus, lake="/bin/true", store=self.store, identity=identity)

    def test_a_second_run_checks_nothing_and_a_new_file_alone_is_checked(self):
        first = self.check()
        self.assertEqual((first["files"], first["reused_files"], first["corpus_files"]), (2, 0, 2))
        self.assertEqual(self.calls(), ["a/p.fact-certificate b/p.fact-certificate"] * 2)
        self.log.unlink()
        again = self.check()
        self.assertEqual((again["files"], again["reused_files"], again["corpus_files"], again["corpus_functions"]), (0, 2, 2, 2))
        self.assertEqual(self.calls(), [])
        (self.corpus / "c").mkdir()
        (self.corpus / "c" / "p.fact-certificate").write_text("fact-certificate-v1\nnew\n")
        third = self.check()
        self.assertEqual((third["files"], third["reused_files"], third["corpus_files"]), (1, 2, 3))
        self.assertEqual(self.calls(), ["c/p.fact-certificate"] * 2)

    def test_another_pair_of_checkers_checks_everything_again(self):
        self.check()
        self.log.unlink()
        again = self.check("y" * 64)
        self.assertEqual((again["files"], again["reused_files"]), (2, 0))

    def test_the_identity_of_the_checkers_moves_with_their_sources(self):
        first = proof.zig_identity()
        self.assertEqual(first, proof.zig_identity())
        self.assertEqual(len(first), 64)


if __name__ == "__main__":
    unittest.main()

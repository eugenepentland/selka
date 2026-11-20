#!/usr/bin/env python3
"""Tests for scripts/ownership_corpus.py: the stamps, and the revert scenario with a stand-in compiler whose receipts hide builds."""
import re
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path[:0] = [str(Path(__file__).resolve().parent)]
import ownership_corpus as corpus  # noqa: E402

REAL_ROOT = Path(__file__).resolve().parents[1]

# A compiler that names itself from a file, keeps receipts per (identity, program) like the shared test store, writes a
# certificate only for a program it builds, and builds every program under --force.
FAKE_COMPILER = """#!/usr/bin/env python3
import fcntl, json, os, sys
state = os.environ["FAKE_COMPILER_STATE"]
# Regeneration runs several suites at once, so the receipts are read, changed and written under a lock, and replaced
# atomically: without it one process can read the file while another has it half written.
lock = open(os.path.join(state, "receipts.lock"), "w")
fcntl.flock(lock, fcntl.LOCK_EX)
identity = open(os.path.join(state, "identity")).read().strip()
args = sys.argv[1:]
if args[:2] == ["validate-certificates", "--identity"]:
    print(identity)
    sys.exit(0)
assert args[0] == "test", args
destination = args[args.index("--emit-certificates") + 1] if "--emit-certificates" in args else None
force = "--force" in args
receipts_path = os.path.join(state, "receipts.json")
receipts = json.load(open(receipts_path)) if os.path.exists(receipts_path) else []
tests = []
for program in ("alpha", "beta"):
    hit = [identity, program] in receipts and not force
    if not hit and destination:
        os.makedirs(os.path.join(destination, program), exist_ok=True)
        with open(os.path.join(destination, program, "unit.certificate"), "w") as out:
            out.write("written by " + identity)
    if [identity, program] not in receipts:
        receipts.append([identity, program])
    tests.append({"name": program + "::test_one", "status": "cached" if hit else "passed", "reason": ""})
with open(receipts_path + ".tmp", "w") as out:
    json.dump(receipts, out)
os.replace(receipts_path + ".tmp", receipts_path)
counts = {s: sum(t["status"] == s for t in tests) for s in ("passed", "cached", "failed", "skipped", "unsupported")}
print(json.dumps({"version": "native-tests-v1", "tests": tests, **counts}))
"""


class Stamps(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)

    def tearDown(self):
        self.directory.cleanup()

    def test_the_inputs_digest_follows_every_file_of_the_suite_and_nothing_else(self):
        suite = self.root / "tests" / "lang"
        (suite / "inner").mkdir(parents=True)
        (suite / "a.selka").write_text("one")
        (suite / "inner" / "b.selka").write_text("two")
        first = corpus.inputs_digest(self.root, "tests/lang")
        self.assertEqual(first, corpus.inputs_digest(self.root, "tests/lang"))
        (suite / "inner" / "b.selka").write_text("three")
        second = corpus.inputs_digest(self.root, "tests/lang")
        self.assertNotEqual(first, second)
        (self.root / "tests" / "other.selka").write_text("elsewhere")
        self.assertEqual(second, corpus.inputs_digest(self.root, "tests/lang"))
        (suite / "c.bin").write_bytes(b"\0\1")
        self.assertNotEqual(second, corpus.inputs_digest(self.root, "tests/lang"))

    def test_a_directory_is_trusted_only_with_the_current_stamp_and_a_failed_run_leaves_none(self):
        directory = self.root / "debug"
        key = {"version": corpus.STAMP_VERSION, "compiler": "a" * 64, "inputs": "b" * 64}
        self.assertTrue(corpus.begin(directory, key))  # nothing stamped: rebuild
        (directory / "m").mkdir()
        (directory / "m" / "u.certificate").write_text("x")
        self.assertIsNone(corpus.read_stamp(directory))  # the run has not finished
        corpus.commit(directory, key)
        self.assertTrue(corpus.is_fresh(directory, key))
        self.assertFalse(corpus.begin(directory, key))  # same compiler and inputs: kept
        self.assertTrue((directory / "m" / "u.certificate").exists())
        other = dict(key, inputs="c" * 64)
        self.assertTrue(corpus.begin(directory, other))  # other inputs: emptied
        self.assertFalse((directory / "m").exists())
        self.assertIsNone(corpus.read_stamp(directory))

    def test_a_damaged_stamp_is_no_stamp(self):
        directory = self.root / "debug"
        directory.mkdir()
        (directory / corpus.STAMP).write_text("{not json")
        self.assertIsNone(corpus.read_stamp(directory))
        (directory / corpus.STAMP).write_text("[1, 2]")
        self.assertIsNone(corpus.read_stamp(directory))

    def test_the_recipes_are_the_runs_build_zig_starts(self):
        text = (REAL_ROOT / "build.zig").read_text()
        # build.zig spells the work directory through src/product.zig (GH-5.1); the recipes here spell it out.
        work = re.search(r'pub const work_dir = "([^"]+)";', (REAL_ROOT / "src/product.zig").read_text()).group(1)
        for suite, cache in corpus.SUITES.items():
            self.assertTrue(cache.startswith(work + "/"), cache)
            self.assertIn(f'.{{ .dir = "{suite}", .cache = product.work_dir ++ "{cache[len(work):]}" }}', text)
        self.assertTrue(corpus.CORPUS.startswith(work + "/"), corpus.CORPUS)
        self.assertIn('debug.addArgs(&.{ "--allowlist", "tests/unsupported.json", suite.dir, "--verify-facts", "--cache-dir", suite.cache });', text)
        self.assertIn('product.work_dir ++ "/ownership-certificates/{s}/debug"', text)
        self.assertIn('product.work_dir ++ "/ownership-certificates/{s}/release"', text)
        self.assertIn('"--release", "--verify-facts", "--cache-dir", b.fmt("{s}-release", .{suite.cache})', text)
        self.assertIn('"env", "SELKA_CORE_LEAKCHECK=1"', text)
        # The release run is built only under -Dtest-release=true, and the proof is told to read its directories.
        self.assertIn("if (test_release) {", text)
        self.assertIn('if (test_release) proof_run.addArg("--with-release-certificates");', text)
        found = corpus.recipes()
        self.assertEqual([recipe.mode for recipe in found], ["debug", "debug", "debug"])
        for recipe in found:
            self.assertEqual(recipe.environment, {"SELKA_CORE_LEAKCHECK": "1"})
            self.assertEqual(recipe.arguments[-1], recipe.directory)
            self.assertIn("--verify-facts", recipe.arguments)
        released = corpus.recipes(release=True)
        self.assertEqual(len(released), 6)
        for recipe in released:
            if recipe.mode == "release":
                self.assertEqual(recipe.arguments[:2], ("--release", "--verify-facts"))
                self.assertEqual(recipe.arguments[-1], recipe.directory)


class Revert(unittest.TestCase):
    """Build, edit, build, revert, then edit proofs/: the gate must still check the certificates of the tree it is on."""

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        # A tree of its own, so the wrapper's root, its suites and its allowlist are this test's and not the repository's.
        (self.root / "scripts").mkdir()
        for name in ("test_lang.py", "ownership_corpus.py"):
            shutil.copy(REAL_ROOT / "scripts" / name, self.root / "scripts" / name)
        (self.root / "tests").mkdir()
        (self.root / "tests" / "unsupported.json").write_text('{"version": 1, "tests": []}')
        for suite in corpus.SUITES:
            (self.root / suite).mkdir(parents=True)
            (self.root / suite / "program.selka").write_text("a program of " + suite)
        self.state = self.root / "state"
        self.state.mkdir()
        self.compiler = self.root / "fake-selka"
        self.compiler.write_text(FAKE_COMPILER)
        self.compiler.chmod(self.compiler.stat().st_mode | stat.S_IXUSR)
        os.environ["FAKE_COMPILER_STATE"] = str(self.state)

    def tearDown(self):
        os.environ.pop("FAKE_COMPILER_STATE", None)
        self.directory.cleanup()

    def use(self, identity):
        (self.state / "identity").write_text(identity)

    def regenerate(self, release=False):
        return corpus.regenerate(str(self.compiler), self.root, jobs=3, release=release)

    def written_by(self, suite="tests/ported", mode="debug"):
        base = self.root / corpus.CORPUS / suite / mode
        return {path.parent.name: path.read_text() for path in base.glob("*/unit.certificate")}

    def test_a_revert_to_a_compiler_whose_receipts_hit_still_leaves_that_compilers_certificates(self):
        self.use("a" * 64)
        self.assertEqual(len(self.regenerate()), 3)  # build
        self.assertEqual(self.written_by(), {"alpha": "written by " + "a" * 64, "beta": "written by " + "a" * 64})
        self.use("b" * 64)  # edit the compiler
        self.assertEqual(len(self.regenerate()), 3)
        self.assertEqual(set(self.written_by().values()), {"written by " + "b" * 64})
        self.use("a" * 64)  # revert: every test hits a receipt of the first build, which would write nothing
        self.assertEqual(len(self.regenerate()), 3)
        self.assertEqual(set(self.written_by().values()), {"written by " + "a" * 64})
        # edit proofs/: no certificate changes and nothing is regenerated, so the corpus is still the reverted tree's
        self.assertEqual(self.regenerate(), [])
        self.assertEqual(set(self.written_by().values()), {"written by " + "a" * 64})

    def test_release_directories_are_regenerated_only_when_asked_and_retired_otherwise(self):
        self.use("a" * 64)
        self.assertEqual(len(self.regenerate(release=True)), 6)
        self.assertEqual(set(self.written_by("tests/lang", "release").values()), {"written by " + "a" * 64})
        # a gate without -Dtest-release=true removes what an earlier release run left, and regenerates no release directory
        self.assertEqual(sorted(corpus.retire(self.root)), [f"{corpus.CORPUS}/{suite}/release" for suite in sorted(corpus.SUITES)])
        self.assertFalse((self.root / corpus.CORPUS / "tests/lang" / "release").exists())
        self.assertEqual(corpus.retire(self.root), [])
        self.assertEqual(len(self.regenerate()), 0)
        self.assertEqual(set(self.written_by().values()), {"written by " + "a" * 64})

    def test_a_directory_deleted_programs_left_is_emptied_not_trusted(self):
        self.use("a" * 64)
        self.regenerate()
        stale = self.root / corpus.CORPUS / "tests" / "ported" / "debug" / "gone"
        stale.mkdir()
        (stale / "unit.certificate").write_text("left by a program that is no longer in the suite")
        (self.root / corpus.CORPUS / "tests" / "ported" / "debug" / corpus.STAMP).write_text(json.dumps({"inputs": "an older digest"}))
        self.regenerate()
        self.assertEqual(sorted(self.written_by()), ["alpha", "beta"])

    def test_a_failing_regeneration_is_an_error_not_a_pass(self):
        self.use("not an identity")
        with self.assertRaises(corpus.CorpusError):
            self.regenerate()


if __name__ == "__main__":
    unittest.main()

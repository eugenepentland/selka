#!/usr/bin/env python3
"""Tests for scripts/ownership_proof.py: the pure parts and the verdict reuse, with stand-ins for the two checkers."""
import json
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path

sys.path[:0] = [str(Path(__file__).resolve().parent)]
import ownership_proof as proof  # noqa: E402

HEADER = "ownership-certificate-v2\nclass add Pure\n"
ACCEPTED = "function good result scalar from - unchecked -\nblock b- preds -\nblock b0 preds -\nterm ret -\nend\n"
LEAKY = "function bad result scalar from - unchecked -\nblock b- preds -\nblock b0 preds -\nterm ret -\nend\n"
STANDIN = """\
import sys
which, path = sys.argv[1], sys.argv[2]
for line in open(path):
    if line.startswith("function "):
        name = line.split()[1]
        if name == "bad" and which == "lean":
            print(f"{path} {name} reject J2 b0 1")
        elif name == "bad":
            print(f"{path} {name} reject J3 b0 1")
        elif name == "weird":
            print(f"{path} {name} unchecked task-group")
        else:
            print(f"{path} {name} accept")
print("summary files=1")
"""


class Link(unittest.TestCase):
    """The program-level link runs both checkers over the certificate root and needs their lines to agree and to be none."""

    def run_with(self, zig_out, lean_out, zig_code=0, lean_code=0):
        def run(command, **_):
            lean = "--link" in command
            out, code = (lean_out, lean_code) if lean else (zig_out, zig_code)
            return type("Done", (), {"stdout": out, "stderr": "", "returncode": code})()

        with tempfile.TemporaryDirectory() as directory:
            fake = Path(directory) / "lake"
            fake.write_text("#!/bin/sh\n")
            fake.chmod(fake.stat().st_mode | stat.S_IEXEC)
            os.environ["SELKA_LAKE"] = str(fake)
            try:
                return proof.link_programs("selka", str(fake), Path(directory), run)
            finally:
                del os.environ["SELKA_LAKE"]

    def test_a_clean_link_reports_the_counts_and_both_times(self):
        found = self.run_with("summary programs=2 functions=5 entries=7 reject=0 errors=0\n", "summary programs=2\n")
        self.assertEqual(found["summary"], "summary programs=2 functions=5 entries=7 reject=0 errors=0")
        self.assertGreaterEqual(found["zig_seconds"], 0)

    def test_an_entry_that_does_not_link_fails_the_action_even_when_both_checkers_say_so(self):
        line = "d f link-reject 0 callee-missing\n"
        with self.assertRaisesRegex(proof.ProofError, "do not match their callee"):
            self.run_with(line + "summary x\n", line + "summary y\n", zig_code=1, lean_code=1)

    def test_a_disagreement_between_the_checkers_names_the_lines(self):
        with self.assertRaisesRegex(proof.ProofError, "disagree"):
            self.run_with("d f link-reject 0 callee-missing\n", "d f link-reject 0 callee-arity\n", zig_code=1, lean_code=1)

    def test_a_checker_that_cannot_link_fails_with_its_output(self):
        with self.assertRaisesRegex(proof.ProofError, "could not link"):
            self.run_with("summary x\n", "unknown option --link\n", lean_code=2)


class Pure(unittest.TestCase):
    def test_functions_and_header_are_split_by_their_end_lines(self):
        text = HEADER + ACCEPTED + LEAKY
        self.assertEqual([name for name, _ in proof.functions_of(text)], ["good", "bad"])
        self.assertEqual(proof.header_of(text), HEADER)
        self.assertEqual(proof.functions_of(text)[0][1], ACCEPTED)

    def test_batches_cover_every_function_once_and_start_the_largest_first(self):
        sizes = {f"d{i}": size for i, size in enumerate([900, 800, 10, 10, 10, 10, 10, 10])}
        batches = proof.batches_of(list(sizes), sizes, 1000)
        self.assertEqual(sorted(d for b in batches for d in b), sorted(sizes))
        self.assertEqual(batches[0], ["d0"])  # above half the target: a batch of its own, first
        self.assertEqual(batches[1], ["d1"])
        self.assertEqual(len(batches[2]), 6)  # the small ones share a batch
        self.assertTrue(all(sum(sizes[d] for d in b) <= 1000 or len(b) == 1 for b in batches))
        self.assertEqual(proof.batches_of([], {}, 1000), [])

    def test_the_default_jobs_follow_the_cpus_admission_allows(self):
        allowed = len(os.sched_getaffinity(0))
        self.assertEqual(proof.available_cpus(), allowed)
        self.assertEqual(proof.default_jobs(), max(1, min(16, allowed - 1)))

    def test_a_verdict_is_read_per_function_in_order_and_an_error_line_fails(self):
        expected = [("a", "good"), ("b", "bad")]
        out = "x good accept\nx bad reject J2 b0 1\nsummary files=1\n"
        self.assertEqual(proof.parse_verdicts(out, Path("."), expected, "zig"), ["accept", "reject J2 b0 1"])
        with self.assertRaises(proof.ProofError):
            proof.parse_verdicts("x error line 2: bad\n", Path("."), expected, "zig")
        with self.assertRaises(proof.ProofError):
            proof.parse_verdicts("x good accept\n", Path("."), expected, "zig")
        with self.assertRaises(proof.ProofError):
            proof.parse_verdicts("x good accept\nx other accept\n", Path("."), expected, "zig")

    def test_a_missing_lake_fails_with_a_message_that_says_it_is_never_skipped(self):
        with tempfile.TemporaryDirectory() as home:
            with self.assertRaises(proof.ProofError) as caught:
                proof.find_lake({"HOME": home})
            self.assertIn("never skips", str(caught.exception))
            self.assertIn("SELKA_LAKE", str(caught.exception))
            fake = Path(home) / "lake"
            fake.write_text("#!/bin/sh\n")
            fake.chmod(fake.stat().st_mode | stat.S_IXUSR)
            self.assertEqual(proof.find_lake({"HOME": home, "SELKA_LAKE": str(fake)}), str(fake))

    def test_fixtures_are_read_from_the_validators_test_source(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "t.zig"
            source.write_text(
                'const cases = [_]Case{\n'
                '    .{ .name = "first", .text =\n'
                '        \\\\function a result scalar from - unchecked -\n'
                '        \\\\end\n'
                '    },\n'
                '    .{ .name = "second", .reject = .j2, .text =\n'
                '        \\\\function b result scalar from - unchecked -\n'
                '        \\\\end\n'
                '    },\n'
                '};\n'
            )
            found = proof.fixtures_of(source)
            self.assertEqual([name for name, _ in found], ["first", "second"])
            self.assertEqual(found[1][1], "function b result scalar from - unchecked -\nend\n")
        self.assertGreaterEqual(len(proof.fixtures_of()), proof.MIN_FIXTURES)

    def test_known_disagreements_need_a_digest_a_function_and_a_reason(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "known.json"
            path.write_text(json.dumps({"version": 1, "disagreements": [{"digest": "abc", "function": "f", "reason": "Lean follows the design"}]}))
            self.assertEqual(proof.load_known(path), {"abc": "Lean follows the design"})
            path.write_text(json.dumps({"version": 1, "disagreements": [{"digest": "abc", "function": "f", "reason": " "}]}))
            with self.assertRaises(proof.ProofError):
                proof.load_known(path)
            path.write_text(json.dumps({"version": 2, "disagreements": []}))
            with self.assertRaises(proof.ProofError):
                proof.load_known(path)
            self.assertEqual(proof.load_known(Path(directory) / "absent.json"), {})


def function_text(name: str, padding: int = 0, unchecked: str = "-") -> str:
    """A function of `padding` extra bytes, as the certificate files print it."""
    body = "".join("inst - drop Drop reads - consumes - state none parents -\n" for _ in range(padding // 56))
    return f"function {name} result scalar from - unchecked {unchecked}\nblock b- preds -\nblock b0 preds -\n{body}term ret -\nend\n"


class Cap(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.big, self.small, self.odd = function_text("big", 5000), function_text("small"), function_text("odd", 5000, "task-group")
        self.digests = {name: proof.block_digest(text) for name, text in (("big", self.big), ("small", self.small), ("odd", self.odd))}
        self.wanted = set(self.digests.values())

    def tearDown(self):
        self.directory.cleanup()

    def store(self, zig="z" * 64, lean="l" * 64, kept=True):
        """The store as a run opens it: with `kept`, after an earlier run with the default checkers saved its verdicts."""
        if kept:
            proof.Store(self.root / "store", "z" * 64, "l" * 64).save()
        store = proof.Store(self.root / "store", zig, lean)
        for text in (self.big, self.small, self.odd):
            store.remember(proof.block_digest(text), text)
        return store

    def test_a_function_above_the_cap_is_skipped_when_the_checkers_are_unchanged_but_not_an_unchecked_one(self):
        store = self.store()
        self.assertFalse(store.zig_fresh or store.lean_fresh)
        run, skipped = proof.lean_plan(store, self.wanted, 1000)
        self.assertEqual(skipped, [self.digests["big"]])
        self.assertEqual(sorted(run), sorted([self.digests["small"], self.digests["odd"]]))
        self.assertTrue(proof.is_unchecked(self.odd))
        self.assertFalse(proof.is_unchecked(self.big))

    def test_the_first_run_a_changed_validator_and_a_changed_proof_check_every_function(self):
        for first in (self.store(kept=False), self.store(zig="y" * 64), self.store(lean="m" * 64)):
            run, skipped = proof.lean_plan(first, self.wanted, 1000)
            self.assertEqual((len(run), skipped), (3, []))
            self.assertTrue(first.zig_fresh or first.lean_fresh)

    def test_a_cap_of_zero_checks_every_function_and_a_verdict_already_kept_is_not_skipped(self):
        store = self.store()
        self.assertEqual(proof.lean_plan(store, self.wanted, 0), (sorted(self.wanted), []))
        store.lean[self.digests["big"]] = "accept"
        run, skipped = proof.lean_plan(store, self.wanted, 1000)
        self.assertEqual((self.digests["big"] in run, skipped), (False, []))

    def test_a_skipped_function_has_no_lean_verdict_to_disagree_with(self):
        store = self.store()
        for digest in self.wanted:
            store.zig[digest] = "accept"
        store.lean[self.digests["small"]] = "accept"
        store.lean[self.digests["odd"]] = "reject J2 b0 1"
        found = proof.disagreements(store, self.wanted)
        self.assertEqual([entry[0] for entry in found], [self.digests["odd"]])


class Reuse(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        stand_in = self.root / "standin.py"
        stand_in.write_text(STANDIN)
        self.commands = {"zig": [sys.executable, str(stand_in), "zig"], "lean": [sys.executable, str(stand_in), "lean"]}
        self.certificates = self.root / "certificates"
        (self.certificates / "suite" / "mod").mkdir(parents=True)
        (self.certificates / "suite" / "mod" / "unit.certificate").write_text(HEADER + ACCEPTED + LEAKY)

    def tearDown(self):
        self.directory.cleanup()

    def run_once(self, store_directory=None, certificates=None):
        store = proof.Store(store_directory or self.root / "store", "z" * 64, "l" * 64)
        proof.collect(certificates or self.certificates, store)
        scratch = self.root / "scratch"
        scratch.mkdir(exist_ok=True)
        wanted = {d for entries in store.corpus.values() for d, _ in entries}
        missing = {"zig": sorted(d for d in wanted if d not in store.zig), "lean": sorted(d for d in wanted if d not in store.lean)}
        proof.check_batches(store, missing, self.commands, 2, scratch, {})
        store.save()
        return store, wanted, missing

    def test_a_function_is_checked_once_and_its_verdicts_are_compared(self):
        store, wanted, missing = self.run_once()
        self.assertEqual((len(missing["zig"]), len(missing["lean"])), (2, 2))
        found = proof.disagreements(store, wanted)
        self.assertEqual(len(found), 1)
        self.assertEqual((found[0][1], found[0][2]), ("reject J3 b0 1", "reject J2 b0 1"))
        self.assertEqual(proof.where(store, found[0][0]), ["suite/mod/unit.certificate:bad"])

    def test_a_second_run_reuses_every_verdict_and_a_new_function_is_the_only_one_checked(self):
        self.run_once()
        _, _, missing = self.run_once()
        self.assertEqual((missing["zig"], missing["lean"]), ([], []))
        (self.certificates / "suite" / "mod" / "unit.certificate").write_text(HEADER + ACCEPTED + LEAKY + ACCEPTED.replace("good", "weird"))
        _, _, missing = self.run_once()
        self.assertEqual((len(missing["zig"]), len(missing["lean"])), (1, 1))

    def test_the_corpus_is_what_the_directory_holds_now(self):
        store, wanted, _ = self.run_once()
        self.assertEqual(len(wanted), 2)
        (self.certificates / "suite" / "mod" / "unit.certificate").unlink()
        (self.certificates / "suite" / "mod" / "other.certificate").write_text(HEADER + ACCEPTED)
        fresh = proof.Store(self.root / "store", "z" * 64, "l" * 64)
        self.assertEqual(proof.collect(self.certificates, fresh), (1, 1))
        self.assertEqual(list(fresh.corpus), ["suite/mod/other.certificate"])
        self.assertEqual(len(fresh.zig), 1)  # only the verdicts of the functions the corpus holds are read
        self.assertEqual(len(fresh.shared.get_many("zig", "z" * 64, store.zig)), 2)  # the others persist

    def test_a_second_work_directory_reuses_the_verdicts_the_first_published(self):
        shared = self.root / "shared"
        self.run_once(store_directory=shared)
        other = self.root / "other-work" / "certificates"
        (other / "suite" / "mod").mkdir(parents=True)
        (other / "suite" / "mod" / "unit.certificate").write_text(HEADER + ACCEPTED + LEAKY)
        store, wanted, missing = self.run_once(store_directory=shared, certificates=other)
        self.assertEqual((missing["zig"], missing["lean"]), ([], []))
        self.assertFalse(store.zig_fresh or store.lean_fresh)
        self.assertEqual(len(proof.disagreements(store, wanted)), 1)

    def test_a_changed_checker_identity_discards_only_that_checkers_verdicts(self):
        self.run_once()
        store = proof.Store(self.root / "store", "z" * 64, "m" * 64)
        proof.collect(self.certificates, store)
        self.assertEqual(len(store.zig), 2)
        self.assertEqual(len(store.lean), 0)
        self.assertFalse(store.zig_fresh)
        self.assertTrue(store.lean_fresh)

    def test_a_run_that_never_finished_leaves_its_checker_fresh_so_the_cap_stays_off(self):
        store = proof.Store(self.root / "store", "z" * 64, "l" * 64)
        proof.collect(self.certificates, store)
        store.record("zig", proof.block_digest(ACCEPTED), "accept")
        store.shared.put_many("zig", store.zig_id, {proof.block_digest(ACCEPTED): "accept"})  # a verdict published, the run then died
        again = proof.Store(self.root / "store", "z" * 64, "l" * 64)
        self.assertTrue(again.zig_fresh and again.lean_fresh)


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Mutation and policy boundaries of formerly fresh verification cohorts."""
from contextlib import ExitStack
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import verification_profiles as profiles
from verification_snapshot import Snapshot, DigestSession
import verification_warm as warm
import verify_cache as coordinator


class WarmInputs(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="warm-inputs-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "repo"
        self.root.mkdir()
        self.env = dict({name: value for name, value in os.environ.items() if not name.startswith("GIT_")}, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_SYSTEM="/dev/null",
                        GIT_AUTHOR_NAME="test", GIT_AUTHOR_EMAIL="test@example.invalid",
                        GIT_COMMITTER_NAME="test", GIT_COMMITTER_EMAIL="test@example.invalid")
        self.git("init", "-q", "-b", "main")
        self.write("SPEC.md", "spec\n")
        self.write("src/check.zig", "const value = 1;\n")
        self.git("add", ".")
        self.git("commit", "-qm", "base")
        self.metadata = {}

    def git(self, *args, input=None):
        # No detached `git maintenance` after a commit: it writes objects/maintenance.lock behind the test's back.
        return subprocess.run(["git", "-c", "maintenance.auto=false", *args], cwd=self.root, env=self.env, input=input,
                              capture_output=True, text=True, check=True).stdout.strip()

    def write(self, name, value):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)
        return path

    def group(self, name, inputs):
        return {"id": name, "target": "verification-" + name, "label": name,
                "inputs": inputs, "cacheable": True, "reason": "declared complete inputs"}

    def key(self, group):
        with ExitStack() as stack:
            snapshots = []
            files = stack.enter_context(Snapshot(self.root, group["inputs"]))
            snapshots.append(files)
            extra = warm.identities(self.root, [group], self.env, stack, snapshots, DigestSession(), self.metadata)
            payload = coordinator.action_payload(group, files, {"compiler": "a" * 64, "environment": "b" * 64}, self.root)
            payload["warm_inputs"] = extra.get(group["id"])
            self.assertTrue(all(guard.unchanged() for guard in snapshots))
            return coordinator.key(payload)

    def assert_source_invalidates(self, name, path):
        source = self.write(path, "original\n")
        group = self.group(name, [path])
        first = self.key(group)
        self.assertEqual(first, self.key(group))
        source.write_text("modified\n")
        self.assertNotEqual(first, self.key(group))

    def test_identity_qualification_source_mutation_invalidates(self):
        self.assert_source_invalidates("identity-qualification", "tests/compiler_identity_cache.py")

    def test_guest_source_mutation_invalidates(self):
        self.assert_source_invalidates("guest", "tests/guest/case.selka")

    def test_language_source_mutation_invalidates(self):
        self.assert_source_invalidates("language", "tests/lang/case.selka")

    def test_guest_live_host_provider_cannot_use_whole_action_receipt(self):
        self.write("tests/lang/live.selka", "public func test_live(host: Host) -> bool:\n    return True\n")
        group = self.group("language", ["tests/"])
        self.key(group)
        self.assertFalse(group["cacheable"])
        self.assertIn("fresh compiler admission", group["reason"])

    def test_guest_host_word_in_strings_and_comments_keeps_the_receipt(self):
        # An HTTP header named Host in test data is not the Host capability.
        self.write("tests/lang/http.selka",
                   "# the Host header and an extern-looking word in a comment\n"
                   "public func test_header() -> bool:\n"
                   "    const wire = b\"GET / HTTP/1.1\\r\\nHost: example.test\\r\\n\\r\\n\"\n"
                   "    const name = \"Host\"\n"
                   "    return len(wire) > 0 and name == 'Host'\n")
        group = self.group("language", ["tests/"])
        self.key(group)
        self.assertTrue(group["cacheable"])

    def test_guest_host_capability_in_code_or_interpolation_stays_fresh(self):
        cases = {
            "extern": "extern func f(host: Host, value: int) -> int\n",
            "parameter": 'public func test_p(host: Host) -> bool:\n    return "Host" == "Host"\n',
            "fstring": 'public func test_f() -> bool:\n    return f"{Host}" != ""\n',
        }
        for label, source in cases.items():
            with self.subTest(label=label):
                self.write("tests/lang/live.selka", source)
                group = self.group("language", ["tests/"])
                self.key(group)
                self.assertFalse(group["cacheable"])
                self.assertIn("fresh compiler admission", group["reason"])

    def test_nonliteral_guest_embed_is_not_assumed_to_be_inside_source_closure(self):
        self.write("tests/lang/embedded.selka", 'const NAME = "/tmp/external"\nconst DATA = embed_bytes(NAME)\n')
        group = self.group("language", ["tests/"])
        self.key(group)
        self.assertFalse(group["cacheable"])
        self.assertIn("nonliteral embedded", group["reason"])

    def test_guest_configuration_arrival_revokes_the_live_absence_guard(self):
        self.write("tests/guest/case.selka", "public func test_case() -> bool:\n    return True\n")
        group = self.group("guest", ["tests/"])
        with ExitStack() as stack:
            snapshots = []
            warm.identities(self.root, [group], self.env, stack, snapshots, DigestSession(), self.metadata)
            self.write("selka.json", "{}")
            self.assertFalse(all(guard.unchanged() for guard in snapshots))
        group = self.group("guest", ["tests/"])
        self.key(group)
        self.assertFalse(group["cacheable"])

    def test_guardian_and_spec_history_install_no_warm_authority(self):
        # Guardian is off (GH-2) and the SPEC history replay borrowed its Git authority: no extra identity for either.
        self.assertNotIn("guardian", warm.KEYED)
        self.assertNotIn("spec-history", warm.KEYED)
        with ExitStack() as stack:
            groups = [self.group("guardian", ["src/"]), self.group("spec-history", ["SPEC.md"])]
            self.assertEqual({}, warm.identities(self.root, groups, self.env, stack, [], DigestSession(), self.metadata))

    def test_coverage_newly_existing_named_fixture_invalidates(self):
        source = Path(__file__).resolve().parents[1] / "tests/test_inputs_coverage.py"
        self.write("tests/test_inputs_coverage.py", source.read_text())
        self.write("src/root_test.zig", 'test "coverage" { const path = "examples/new.selka"; }\n')
        group = self.group("coverage", ["tests/test_inputs_coverage.py", "src/"])
        first = self.key(group)
        self.assertEqual(first, self.key(group))
        self.write("examples/new.selka", "new fixture\n")
        self.assertNotEqual(first, self.key(group))

    def test_coverage_ignores_output_churn_but_rejects_candidate_aba(self):
        self.write("examples/candidate.selka", "fixture")
        with warm.NamedPathAuthority(self.root, ["SPEC.md", "examples/candidate.selka"]) as guard:
            self.write(".selka-cache/output", "gate output")
            self.write("examples/unrelated.selka", "unrelated")
            self.assertTrue(guard.unchanged())
            candidate = self.root / "examples/candidate.selka"
            candidate.unlink()
            candidate.write_text("fixture")
            self.assertFalse(guard.unchanged())

    def test_current_preparation_has_no_selected_gate_and_never_claims_a_receipt(self):
        names = sorted(warm.PREPARATION | warm.QUALIFICATION)
        groups = [self.group(name, []) for name in names]
        for group in groups:
            group.update(cacheable=False, reason="validated preparation discovery v1")
        rows = [{"id": group["id"], "state": warm.disposition(group),
                 "action_key": hashlib.sha256(group["id"].encode()).hexdigest()} for group in groups]
        plan = {"groups": groups, "configuration": {"filtered": False, "proofs": True}}
        scheduled = profiles.schedule(plan, rows)
        report = profiles.coverage(plan, rows, scheduled["selected"], status=0, inputs_stable=True)
        self.assertEqual([], scheduled["selected"])
        self.assertEqual(0, report["counts"]["reused"])
        self.assertEqual(0, report["counts"]["executed"])
        self.assertEqual(3, report["counts"]["prepared"])
        self.assertEqual(2, report["counts"]["qualification_owed"])
        self.assertTrue(report["complete_verification"])
        self.assertFalse(report["complete_qualification"])

    def test_forced_preparation_and_native_filter_remain_fresh(self):
        prepared = self.group("input-discovery", [])
        prepared.update(cacheable=False, reason="validated preparation discovery v1")
        self.assertEqual("fresh", warm.disposition(prepared, force=True))
        self.assertEqual("fresh", warm.disposition(self.group("unit", []), filtered=True))
        self.assertEqual("cacheable", warm.disposition(self.group("language", []), filtered=True))
        self.assertEqual("owed", warm.disposition(self.group("juice", []), force=True))


class WarmCoordinator(unittest.TestCase):
    def setUp(self):
        import verify_cache_test as fixtures
        self.fixture = fixtures.VerificationCoordinator("runTest")
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        names = sorted(warm.PREPARATION | warm.QUALIFICATION)
        self.fixture.plan["groups"] = [fixtures.group(name, [], False) for name in names]
        for group in self.fixture.plan["groups"]:
            group["reason"] = "validated preparation discovery v1"
        self.fixture.plan["coverage"].update(required_actions=len(names), registered_actions=len(names))
        self.fixture.save_plan()

    def test_two_unchanged_requests_need_no_gate_and_warm_request_no_admission(self):
        fixture = self.fixture
        self.assertEqual(0, fixture.execute())
        self.assertEqual([], fixture.events("gate"))
        fixture.admissions.clear()
        self.assertEqual(0, fixture.execute())
        self.assertEqual([], fixture.admissions)
        report = coordinator.read_record(fixture.cache / "last-run.json")
        self.assertEqual(0, sum(row["state"] == "fresh" for row in report["actions"]))
        self.assertEqual(3, report["profile_coverage"]["counts"]["prepared"])
        self.assertEqual(["juice", "juice-runtime"], report["profile_coverage"]["qualification_owed"])
        self.assertEqual([], fixture.receipts())


if __name__ == "__main__":
    unittest.main()

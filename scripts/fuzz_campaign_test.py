#!/usr/bin/env python3
"""Coordinator boundary tests with simulated workers and real filesystem watches."""
from contextlib import ExitStack, redirect_stdout
import io
import hashlib
import json
import multiprocessing
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import fuzz_campaign as campaign
import fuzz_campaign_identity as identity
import fuzz_campaign_store as evidence


def campaign_lock_process(private, shared, family, channel):
    store = campaign.CampaignStore(private, shared)
    with store.lease():
        channel.send("waiting")
        with store.coordinator_lock(family):
            channel.send(("entered", store.success.gc(dry_run=False)["skipped_active"]))
            channel.recv()


class StableHost:
    identity = {"test-host": 1}

    def unchanged(self):
        return True


class CampaignTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="fuzz-coordinator-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.binary = self.root / "candidate"
        self.binary.write_text("#!/bin/sh\nexit 0\n")
        self.binary.chmod(0o755)
        self.components = self.root / "components"
        self.components.mkdir()
        for name in ("test-index", "cache-plan"):
            (self.components / (name + ".json")).write_text(json.dumps({"artifact": "." + name}))
            (self.components / ("." + name)).write_bytes(name.encode())
        for script, project, _adapter, _entry in campaign.DIFFERENTIAL.values():
            (self.root / script).parent.mkdir(parents=True, exist_ok=True)
            (self.root / script).write_text("# simulated adapter\n")
            (self.root / project).mkdir(parents=True, exist_ok=True)
            (self.root / project / "main.my").write_text("func main() -> int:\n    return 0\n")
        (self.root / "tests/differential_corpus.py").write_text("# corpus contract\n")
        (self.root / "src/stdlib").mkdir(parents=True)
        (self.root / "src/stdlib/fixture.my").write_text("# runtime input\n")
        (self.root / "coordinator.py").write_text("# common code\n")
        (self.root / "scripts").mkdir()
        (self.root / "scripts/fuzz_coverage.py").write_text("# simulated coverage adapter\n")
        self.initial = self.root / "initial"
        self.initial.mkdir()
        (self.initial / "seed").write_bytes(b"seed")
        self.environment = {"PATH": os.environ["PATH"], "HOME": str(self.root)}
        self.calls = []
        self.limits = []
        self.failure = False
        self.interrupt_at = None
        self.before = None
        self.after = None
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(campaign, "ROOT", self.root))
        self.stack.enter_context(patch.object(identity, "COMMON_INPUTS", ["coordinator.py"]))
        self.stack.enter_context(patch.object(identity, "tools", side_effect=lambda _env, binaries, _zig: ([], binaries)))
        self.stack.enter_context(patch.object(campaign.verification, "normalized_environment", side_effect=lambda _root: dict(self.environment)))
        self.stack.enter_context(patch.object(campaign.verification, "HostContext", StableHost))
        self.stack.enter_context(patch.object(campaign.verification, "run_admitted", side_effect=self.admitted))
        self.store = evidence.Store(self.root / "cache/evidence-v2")

    def admitted(self, root, kind, command, environment, unchanged, timings, limits=None):
        self.assertEqual("gate", kind)
        self.limits.append(limits)
        request_path = Path(command[-2])
        request = campaign.worker_request(request_path, command[-1])
        if self.before:
            self.before(request, request_path)
        self.assertTrue(unchanged())
        self.calls.append(request)
        if self.interrupt_at == len(self.calls):
            raise KeyboardInterrupt
        output = Path(request["output"])
        replay = request["operation"] == "replay"
        if replay:
            bundle = Path(request["bundle"])
            count = json.loads(bundle.read_text())["count"]
        else:
            count = request.get("steps", request.get("runs"))
            bundle = output / "corpus.json"
            bundle.write_text(json.dumps({"simulation-only": True, "target": request["name"],
                                           "seed": request["seed"], "count": count}))
        result = {"version": 1, "complete": not self.failure, "success": not self.failure,
                  "explored": 0 if replay else count, "replayed": count if replay else 0,
                  "bundle": str(bundle), "engine": {"coverage_schema": "libfuzzer-inline8-log-v1"}}
        (output / "result.json").write_text(json.dumps(result))
        timings.append({"kind": kind, "observed_held_seconds": 0.01})
        if self.after:
            self.after(request)
        return (1 if self.failure else 0), 0.01

    def run_campaign(self, *extra, coverage=False):
        if coverage:
            argv = ["coverage", "--name", "example", "--engine", str(self.binary),
                    "--corpus", str(self.initial), "--runs", "4"]
        else:
            argv = ["differential", "--compiler", str(self.binary), "--zig", str(self.binary),
                    "--components", str(self.components), "--steps", "2"]
        argv += ["--cache-dir", str(self.root / "cache"), *extra]
        with redirect_stdout(io.StringIO()):
            args = campaign.options(argv)
            status = campaign.execute(args)
        return status, json.loads((args.cache_dir / "last-run.json").read_text())

    def test_invalid_work_controls_are_rejected_before_admission(self):
        for flag, value in (("--max-actions", "0"), ("--action-timeout", "nan"), ("--action-timeout", "-1")):
            with self.assertRaises(SystemExit) as failure, patch("sys.stderr", io.StringIO()):
                self.run_campaign(flag, value)
            self.assertEqual(2, failure.exception.code)
        self.assertEqual([], self.calls)

    def test_work_cap_reports_partial_and_preserves_completed_shard_for_resume(self):
        status, partial = self.run_campaign("--target", "incremental", "--shards", "3", "--max-actions", "1")
        self.assertEqual(3, status)
        self.assertFalse(partial["complete"])
        self.assertTrue(partial["work_budget"]["exhausted"])
        self.assertEqual(1, partial["counts"]["executed_shards"])
        self.assertEqual(2, len(partial["outstanding"]))
        self.calls.clear()
        status, resumed = self.run_campaign("--target", "incremental", "--shards", "3")
        self.assertEqual(0, status)
        self.assertEqual(1, resumed["counts"]["reused_shards"])
        self.assertEqual([], resumed["outstanding"])
        self.calls.clear()
        status, warm = self.run_campaign("--target", "incremental", "--shards", "3", "--max-actions", "1")
        self.assertEqual((0, []), (status, self.calls))
        self.assertTrue(warm["complete"])

    def test_cap_names_targets_not_yet_expanded(self):
        status, report = self.run_campaign("--max-actions", "1")
        self.assertEqual(3, status)
        self.assertEqual(["interfaces", "interfaces-generic"], report["unvisited_targets"])
        self.assertEqual("module-projects", report["outstanding"][0]["target"])

    def test_explicit_deadline_is_admitted_and_changes_evidence_identity(self):
        self.run_campaign("--target", "incremental", "--action-timeout", "7")
        self.assertEqual(7, self.limits[-1].timeout_seconds)
        self.calls.clear()
        self.run_campaign("--target", "incremental", "--action-timeout", "8")
        self.assertTrue(self.calls)
        self.assertEqual(8, self.limits[-1].timeout_seconds)

    def test_coverage_whole_action_deadline_uses_same_supervisor(self):
        status, report = self.run_campaign("--hermetic", "--action-timeout", "2", coverage=True)
        self.assertEqual(0, status)
        self.assertEqual(2, self.limits[-1].timeout_seconds)
        self.assertTrue(report["complete"])

    def test_shared_success_reuses_across_private_caches_with_private_corpus_copies(self):
        shared = self.root / "shared-evidence"
        args = ("--target", "incremental", "--shared-cache-dir", str(shared))
        status, cold = self.run_campaign(*args)
        self.assertEqual(status, 0)
        key = cold["actions"][0]["key"]
        backend = evidence.Store(shared)
        corpus = backend.load_success(key)["corpus"]
        self.assertEqual([], list((shared / "corpus").glob("*.json")))
        self.calls.clear()
        other = self.root / "other-private-cache"
        status, warm = self.run_campaign(*args, "--cache-dir", str(other))
        self.assertEqual((status, self.calls, warm["admissions"]), (0, [], []))
        self.assertEqual(warm["counts"]["reused_shards"], 1)
        local = evidence.Store(other / "evidence-v2")
        family = identity.family(self.root, "differential", "incremental")
        self.assertEqual(local.load_corpus(family), [corpus])
        self.assertEqual(local.read_blob(corpus), backend.read_blob(corpus))
        backend._path("blobs", corpus).unlink()
        self.assertIsNotNone(local.read_blob(corpus))
        self.assertIsNone(backend.load_success(key))

    def test_shared_changed_candidate_misses_and_revert_recovers_exact_receipts(self):
        args = ("--target", "incremental", "--shared-cache-dir", str(self.root / "shared-evidence"))
        _, first = self.run_campaign(*args)
        original = self.binary.read_bytes()
        self.binary.write_bytes(original + b"# changed candidate\n")
        self.calls.clear()
        _, changed = self.run_campaign(*args)
        self.assertEqual(changed["counts"]["executed_shards"], 1)
        self.assertEqual(changed["counts"]["executed_replays"], 1)
        self.binary.write_bytes(original)
        self.calls.clear()
        _, reverted = self.run_campaign(*args)
        self.assertEqual((self.calls, reverted["counts"]["reused_shards"]), ([], 1))
        self.assertEqual(first["actions"][0]["key"], reverted["actions"][-1]["key"])

    def test_evicted_shared_corpus_republishes_changed_candidate_replay_for_warm_reuse(self):
        shared = self.root / "shared-evidence"
        args = ("--target", "incremental", "--shared-cache-dir", str(shared))
        _, cold = self.run_campaign(*args)
        backend = evidence.Store(shared)
        corpus = backend.load_success(cold["actions"][0]["key"])["corpus"]
        backend._path("blobs", corpus).unlink()
        self.binary.write_bytes(self.binary.read_bytes() + b"# changed candidate\n")
        self.calls.clear()
        status, changed = self.run_campaign(*args)
        self.assertEqual((status, changed["counts"]["executed_replays"]), (0, 1))
        replay = next(row for row in changed["actions"] if row["operation"] == "replay")
        self.assertEqual(backend.load_success(replay["key"]), {"corpus": corpus})
        self.assertIsNotNone(backend.read_blob(corpus))
        self.calls.clear()
        status, warm = self.run_campaign(*args)
        self.assertEqual((status, self.calls, warm["admissions"]), (0, [], []))

    def test_forced_different_corpus_conflicts_with_previous_deterministic_success(self):
        shared = self.root / "shared-evidence"
        args = ("--target", "incremental", "--shared-cache-dir", str(shared))
        _, cold = self.run_campaign(*args)
        key = cold["actions"][0]["key"]
        self.failure = True
        status, failed = self.run_campaign(*args, "--force")
        self.assertEqual((status, failed["success"]), (1, False))
        self.assertIsNone(evidence.Store(shared).load_success(key))
        self.failure = False
        def change(request):
            if request["operation"] == "explore":
                bundle = Path(request["output"]) / "corpus.json"
                payload = json.loads(bundle.read_text())
                payload["different-output"] = True
                bundle.write_text(json.dumps(payload))
        self.after = change
        with self.assertRaises(evidence.DeterminismError):
            self.run_campaign(*args, "--force")
        self.assertIsNone(evidence.Store(shared).load_success(key))
        self.assertFalse(json.loads((self.root / "cache/last-run.json").read_text())["success"])

    def test_rejected_success_publication_cannot_report_completed_campaign(self):
        with patch.object(evidence.Store, "publish_success", return_value=False):
            with self.assertRaisesRegex(ValueError, "could not publish qualified success"):
                self.run_campaign("--target", "incremental")
        self.assertFalse(json.loads((self.root / "cache/last-run.json").read_text())["complete"])

    def test_shared_evidence_lease_prevents_gc_during_worker_consumption(self):
        shared = self.root / "shared-evidence"
        observed = []
        self.before = lambda *_: observed.append(evidence.Store(shared).gc(dry_run=False))
        status, result = self.run_campaign("--target", "incremental", "--shared-cache-dir", str(shared))
        self.assertEqual(status, 0)
        self.assertTrue(observed)
        self.assertTrue(all(row["skipped_active"] for row in observed))
        self.assertGreater(result["snapshot_statistics"]["files_hashed"], 0)

    def lock_process(self, private, shared, family):
        context = multiprocessing.get_context('spawn')
        channel, child = context.Pipe()
        process = context.Process(target=campaign_lock_process, args=(private, shared, family, child))
        process.start()
        child.close()
        def cleanup():
            if process.is_alive():
                process.kill()
            process.join(timeout=5)
            channel.close()
        self.addCleanup(cleanup)
        self.assertTrue(channel.poll(5), 'lock process did not start')
        self.assertEqual(channel.recv(), 'waiting')
        return process, channel

    def test_shared_family_workflow_blocks_other_private_cache_and_releases_after_crash(self):
        for crashed in (False, True):
            with self.subTest(crashed=crashed):
                shared = self.root / ('shared-lock-' + str(crashed))
                family = hashlib.sha256(b'same campaign').hexdigest()
                first, active = self.lock_process(self.root / ('private-first-' + str(crashed)), shared, family)
                self.assertTrue(active.poll(5))
                self.assertEqual(active.recv(), ('entered', True))
                second, waiting = self.lock_process(self.root / ('private-second-' + str(crashed)), shared, family)
                self.assertFalse(waiting.poll(0.2), 'shared refresh lock failed to block another private cache')
                if crashed:
                    first.kill()
                else:
                    active.send('release')
                first.join(timeout=5)
                self.assertFalse(first.is_alive())
                self.assertTrue(waiting.poll(5), 'shared workflow lock was not released')
                self.assertEqual(waiting.recv(), ('entered', True))
                waiting.send('release')
                second.join(timeout=5)
                self.assertEqual(second.exitcode, 0)

    def test_aliased_private_and_shared_store_lock_is_acquired_once(self):
        private = self.root / 'aliased-store'
        private.mkdir()
        alias = self.root / 'aliased-path'
        alias.symlink_to(private, target_is_directory=True)
        store = campaign.CampaignStore(private, alias)
        self.assertIs(store.local, store.success)
        process, channel = self.lock_process(private, alias, hashlib.sha256(b'alias').hexdigest())
        self.assertTrue(channel.poll(5), 'alias attempted to lock the same flock twice')
        self.assertEqual(channel.recv(), ('entered', True))
        channel.send('release')
        process.join(timeout=5)
        self.assertEqual(process.exitcode, 0)

    def test_identical_binary_bytes_at_changed_path_do_not_share_action_success(self):
        args = ("--target", "incremental", "--shared-cache-dir", str(self.root / "shared-evidence"))
        _, cold = self.run_campaign(*args)
        other = self.root / "candidate-at-other-path"
        other.write_bytes(self.binary.read_bytes())
        other.chmod(self.binary.stat().st_mode & 0o7777)
        self.calls.clear()
        _, changed = self.run_campaign(*args, "--compiler", str(other))
        self.assertEqual(changed["counts"]["executed_shards"], 1)
        self.assertNotEqual(cold["actions"][0]["key"], changed["actions"][-1]["key"])

    def test_completed_shards_reuse_before_admission_and_extension_only_adds_one(self):
        status, cold = self.run_campaign("--target", "incremental", "--shards", "2")
        self.assertEqual(0, status)
        self.assertEqual(2, cold["counts"]["executed_shards"])
        self.calls.clear()
        with patch.object(evidence.Store, "retain_corpus", side_effect=AssertionError("warm catalog rewrite")):
            status, warm = self.run_campaign("--target", "incremental", "--shards", "2")
        self.assertEqual((0, []), (status, self.calls))
        self.assertEqual(2, warm["counts"]["reused_shards"])
        self.assertEqual([], warm["admissions"])
        status, extended = self.run_campaign("--target", "incremental", "--shards", "3")
        self.assertEqual(0, status)
        self.assertEqual(1, len(self.calls))
        self.assertEqual(identity.seed(1, 2), self.calls[0]["seed"])
        self.assertEqual(2, extended["counts"]["reused_shards"])

    def test_worker_request_digest_is_checked_before_decode_or_dispatch(self):
        path = self.root / "request.json"
        original = b'{"kind":"differential","output":"unused"}\n'
        path.write_bytes(original)
        digest = hashlib.sha256(original).hexdigest()
        self.assertEqual(campaign.worker_request(path, digest),
                         {"kind": "differential", "output": "unused"})
        path.write_bytes(b'not even valid JSON')
        with patch.object(campaign, "differential_worker") as dispatch:
            with self.assertRaisesRegex(ValueError, "request SHA256 mismatch"):
                campaign.worker(path, digest)
            dispatch.assert_not_called()
        path.write_bytes(original)
        with self.assertRaisesRegex(ValueError, "invalid expected"):
            campaign.worker_request(path, "../bad-digest")

    def test_worker_request_rejects_nonregular_and_oversized_bytes(self):
        path = self.root / "request.json"
        path.write_bytes(b'{}\n')
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        with patch.object(evidence, "METADATA_MAX_BYTES", 2):
            with self.assertRaisesRegex(ValueError, "bounded regular"):
                campaign.worker_request(path, digest)
        path.unlink()
        os.mkfifo(path)
        with self.assertRaisesRegex(ValueError, "bounded regular"):
            campaign.worker_request(path, digest)

    def test_request_aba_while_queued_prevents_execution_and_publication(self):
        def change(_request, path):
            original = path.read_bytes()
            path.write_bytes(b'{"different":"request"}\n')
            path.write_bytes(original)
        self.before = change
        with self.assertRaises(evidence.InputsChanged):
            self.run_campaign("--target", "incremental")
        self.assertEqual(self.calls, [])
        self.assertEqual([], list((self.store.root / "success").glob("*.json")))

    def test_staged_replay_bundle_aba_prevents_new_target_success(self):
        self.run_campaign("--target", "incremental")
        prior = set((self.store.root / "success").iterdir())
        self.binary.write_text("#!/bin/sh\nexit 1\n")
        def change(request):
            self.assertEqual(request["operation"], "replay")
            path = Path(request["bundle"])
            original = path.read_bytes()
            path.write_bytes(b'different retained bytes')
            path.write_bytes(original)
        self.after = change
        with self.assertRaises(evidence.InputsChanged):
            self.run_campaign("--target", "incremental")
        self.assertEqual(prior, set((self.store.root / "success").iterdir()))
        self.assertFalse(json.loads((self.root / "cache/last-run.json").read_text())["success"])

    def test_staged_initial_corpus_aba_prevents_hermetic_coverage_success(self):
        def change(request):
            path = next(Path(request["initial_corpus"]).iterdir())
            original = path.read_bytes()
            path.write_bytes(b'different initial input')
            path.write_bytes(original)
        self.after = change
        with self.assertRaises(evidence.InputsChanged):
            self.run_campaign("--hermetic", coverage=True)
        self.assertEqual([], list((self.store.root / "success").glob("*.json")))

    def test_coverage_request_binds_only_the_staged_initial_digests(self):
        self.run_campaign("--hermetic", coverage=True)
        request = self.calls[0]
        digest = hashlib.sha256(b"seed").hexdigest()
        self.assertEqual(request["initial_digests"], [digest])
        self.assertEqual((Path(request["initial_corpus"]) / digest).read_bytes(), b"seed")

    def test_initial_copy_edit_before_watch_cannot_replace_original_input_identity(self):
        stage = campaign.initial_corpus
        def corrupt(*args):
            expected = stage(*args)
            next(iter(expected)).write_bytes(b'different staged bytes')
            return expected
        with patch.object(campaign, "initial_corpus", side_effect=corrupt):
            with self.assertRaisesRegex(evidence.InputsChanged, "during capture"):
                self.run_campaign("--hermetic", coverage=True)
        self.assertEqual(self.calls, [])
        self.assertEqual([], list((self.store.root / "success").glob("*.json")))

    def test_staged_request_watch_survives_until_post_publication_guard(self):
        publish = evidence.Store.publish_success
        def changing_guard(store, key, result, blobs, validate):
            checks = []
            def guard():
                checks.append(1)
                if len(checks) == 2:
                    path = Path(self.calls[-1]["output"]) / "request.json"
                    original = path.read_bytes()
                    path.write_bytes(b'different bytes after publication')
                    path.write_bytes(original)
                return validate()
            return publish(store, key, result, blobs, guard)
        with patch.object(evidence.Store, "publish_success", new=changing_guard):
            with self.assertRaises(evidence.InputsChanged):
                self.run_campaign("--target", "incremental")
        self.assertEqual(list((self.store.root / "success").iterdir()), [])
        self.assertFalse(json.loads((self.root / "cache/last-run.json").read_text())["success"])

    def test_staged_initial_directory_new_input_while_queued_prevents_execution(self):
        def change(request, _path):
            (Path(request["initial_corpus"]) / "unbound-input").write_bytes(b'new')
        self.before = change
        with self.assertRaises(evidence.InputsChanged):
            self.run_campaign("--hermetic", coverage=True)
        self.assertEqual(self.calls, [])
        self.assertEqual([], list((self.store.root / "success").glob("*.json")))

    def test_staging_write_to_watch_gap_cannot_bless_modified_request(self):
        atomic = campaign.verification.atomic_record
        def corrupt(path, value):
            atomic(path, value)
            if path.name == "request.json":
                value = dict(value, binary="different compiler")
                atomic(path, value)
        with patch.object(campaign.verification, "atomic_record", side_effect=corrupt):
            with self.assertRaisesRegex(evidence.InputsChanged, "during capture"):
                self.run_campaign("--target", "incremental")
        self.assertEqual(self.calls, [])
        self.assertEqual([], list((self.store.root / "success").glob("*.json")))

    def test_seed_and_execution_settings_change_action_identity(self):
        self.run_campaign("--target", "incremental")
        self.calls.clear()
        _, changed = self.run_campaign("--target", "incremental", "--seed", "2")
        self.assertEqual(["replay", "explore"], [r["operation"] for r in self.calls])
        self.assertEqual(1, changed["counts"]["executed_shards"])
        self.calls.clear()
        self.run_campaign("--target", "incremental", "--seed", "2", "--steps", "3")
        self.assertEqual("explore", self.calls[-1]["operation"])

    def test_target_edit_replays_only_its_corpus_and_keeps_other_target_reuse(self):
        self.run_campaign("--target", "incremental", "--target", "interfaces")
        self.calls.clear()
        (self.root / "tests/fixtures/incremental/main.my").write_text("changed fixture\n")
        _, result = self.run_campaign("--target", "incremental", "--target", "interfaces")
        self.assertEqual([("incremental", "replay"), ("incremental", "explore")],
                         [(r["name"], r["operation"]) for r in self.calls])
        self.assertEqual(1, result["counts"]["reused_shards"])

    def test_candidate_and_hidden_component_bytes_invalidate_completed_actions(self):
        self.run_campaign("--target", "incremental")
        self.calls.clear()
        (self.components / ".cache-plan").write_bytes(b"new component")
        self.run_campaign("--target", "incremental")
        self.assertEqual(["replay", "explore"], [r["operation"] for r in self.calls])
        self.calls.clear()
        self.binary.write_text("#!/bin/sh\nexit 1\n")
        self.run_campaign("--target", "incremental")
        self.assertEqual(["replay", "explore"], [r["operation"] for r in self.calls])

    def test_interruption_keeps_completed_shard_but_no_complete_report(self):
        self.interrupt_at = 2
        with self.assertRaises(KeyboardInterrupt):
            self.run_campaign("--target", "incremental", "--shards", "2")
        report = json.loads((self.root / "cache/last-run.json").read_text())
        self.assertFalse(report["complete"])
        self.interrupt_at = None
        self.calls.clear()
        _, resumed = self.run_campaign("--target", "incremental", "--shards", "2")
        self.assertEqual(1, len(self.calls))
        self.assertEqual(1, resumed["counts"]["reused_shards"])

    def test_failure_repairing_missing_blob_cannot_resurrect_old_success(self):
        _, cold = self.run_campaign("--target", "incremental")
        action = cold["actions"][0]["key"]
        digest = self.store.load_success(action)["corpus"]
        (self.store.root / "blobs" / digest).unlink()
        self.failure = True
        status, failed = self.run_campaign("--target", "incremental", "--discard-corrupt-corpus")
        self.assertEqual(1, status)
        self.assertFalse(failed["complete"])
        self.assertIsNotNone(self.store.read_blob(digest))
        self.assertIsNone(self.store.load_success(action))
        self.failure = False
        self.calls.clear()
        self.run_campaign("--target", "incremental")
        self.assertEqual(["replay", "explore"], [r["operation"] for r in self.calls])

    def test_force_failure_invalidates_requested_old_shard(self):
        _, cold = self.run_campaign("--target", "incremental")
        action = cold["actions"][0]["key"]
        self.failure = True
        status, _ = self.run_campaign("--target", "incremental", "--force")
        self.assertEqual(1, status)
        self.assertIsNone(self.store.load_success(action))

    def test_input_aba_during_worker_prevents_publication(self):
        source = self.root / "tests/fixtures/incremental/main.my"
        original = source.read_bytes()
        def change(_request):
            source.write_bytes(b"changed\n")
            source.write_bytes(original)
        self.after = change
        with self.assertRaises(evidence.InputsChanged):
            self.run_campaign("--target", "incremental")
        self.assertEqual([], list((self.store.root / "success").glob("*.json")))
        self.assertFalse(json.loads((self.root / "cache/last-run.json").read_text())["success"])

    def test_completed_target_remains_watched_during_later_target(self):
        source = self.root / "tests/fixtures/incremental/main.my"
        def change(request):
            if request["name"] == "interfaces":
                source.write_text("edit after first target completed\n")
        self.after = change
        with self.assertRaises(evidence.InputsChanged):
            self.run_campaign("--target", "incremental", "--target", "interfaces")
        self.assertFalse(json.loads((self.root / "cache/last-run.json").read_text())["success"])

    def test_valid_envelope_with_wrong_result_shape_is_a_miss(self):
        self.run_campaign("--target", "incremental")
        self.calls.clear()
        with patch.object(evidence.Store, "load_success", return_value={}):
            self.run_campaign("--target", "incremental")
        self.assertEqual(["replay", "explore"], [r["operation"] for r in self.calls])

    def test_corrupt_catalog_recovers_from_qualified_shard_without_execution(self):
        self.run_campaign("--target", "incremental")
        family = identity.family(self.root, "differential", "incremental")
        (self.store.root / "corpus" / (family + ".json")).write_bytes(b"truncated")
        self.calls.clear()
        with self.assertRaises(evidence.CorpusError):
            self.run_campaign("--target", "incremental")
        _, result = self.run_campaign("--target", "incremental", "--discard-corrupt-corpus")
        self.assertEqual([], self.calls)
        self.assertEqual(1, len(result["corpus_recovery"]))
        self.assertEqual(1, len(self.store.load_corpus(family)))

    def test_coverage_unknown_inputs_stay_fresh_and_hermetic_contract_can_reuse(self):
        _, first = self.run_campaign(coverage=True)
        self.assertTrue(first["freshness_reasons"])
        self.calls.clear()
        self.run_campaign(coverage=True)
        self.assertEqual(["replay", "explore"], [r["operation"] for r in self.calls])
        self.run_campaign("--hermetic", coverage=True)
        self.calls.clear()
        _, warm = self.run_campaign("--hermetic", coverage=True)
        self.assertEqual([], self.calls)
        self.assertEqual(1, warm["counts"]["reused_shards"])

    def test_unsupported_loader_override_prevents_all_evidence_reuse(self):
        self.run_campaign("--target", "incremental")
        self.environment["LD_PRELOAD"] = "unknown-provider"
        self.calls.clear()
        _, result = self.run_campaign("--target", "incremental")
        self.assertIn("LD_PRELOAD", result["freshness_reasons"])
        self.assertEqual(["replay", "explore"], [r["operation"] for r in self.calls])

    def test_leak_qualification_stays_fresh(self):
        self.run_campaign("--target", "incremental")
        self.environment["MYL_CORE_LEAKCHECK"] = "1"
        _, result = self.run_campaign("--target", "incremental")
        self.assertIn("MYL_CORE_LEAKCHECK", result["freshness_reasons"])
        self.assertEqual(1, result["counts"]["executed_shards"])

    def test_component_manifest_refuses_escaping_artifact(self):
        (self.components / "cache-plan.json").write_text('{"artifact":"../outside"}')
        with self.assertRaises(campaign.verification.VerificationError):
            identity.components(self.components)

    def test_seed_shards_are_stable_and_nonzero(self):
        seeds = [identity.seed(1, ordinal) for ordinal in range(64)]
        self.assertEqual(seeds, [identity.seed(1, ordinal) for ordinal in range(64)])
        self.assertEqual(64, len(set(seeds)))
        self.assertTrue(all(0 < seed <= 0xffffffff for seed in seeds))
        self.assertNotEqual(seeds[0], identity.seed(2, 0))


if __name__ == "__main__":
    unittest.main()

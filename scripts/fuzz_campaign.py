#!/usr/bin/env python3
"""Resume qualified differential or libFuzzer campaigns by independent seed shard.

This developer command owns admission. Cache lookup, input hashing and publication
run outside the server gate; only missing replay/exploration actions acquire it.
The installed compiler and source-build install graph do not invoke this script.
"""
from __future__ import annotations

import argparse
import math
from contextlib import ExitStack
import hashlib
import json
import marshal
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import sys
import tempfile

import fuzz_campaign_identity as identity
import fuzz_campaign_store as evidence
import verification_snapshot
from verification_snapshot import Snapshot, SnapshotError
import verify_cache as verification

ROOT = Path(__file__).resolve().parents[1]
LOADED_CODE_SHA256 = hashlib.sha256(marshal.dumps(sys._getframe().f_code)).hexdigest()
DIFFERENTIAL = {
    "incremental": ("tests/incremental_diff.py", "tests/fixtures/incremental", "incremental-v1", "main.my"),
    "module-projects": ("tests/incremental_diff.py", "tests/fixtures/module_projects", "incremental-v1", "main.my"),
    "interfaces": ("tests/interface_diff.py", "tests/fixtures/interfaces", "interfaces-v1", "main.my"),
    "interfaces-generic": ("tests/interface_diff.py", "tests/fixtures/interfaces_generic", "interfaces-v1", "main.my"),
}


def bounded_json(path: Path) -> dict:
    value = verification.read_record(path)
    if value is None:
        raise ValueError("missing or malformed worker result: " + str(path))
    return value


def bounded_bundle(path: Path, maximum: int = evidence.BLOB_MAX_BYTES) -> bytes:
    fd = os.open(path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as stream:
        metadata = os.fstat(stream.fileno())
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > maximum:
            raise ValueError("worker bundle is not a bounded regular file")
        data = stream.read(maximum + 1)
    if len(data) > maximum:
        raise ValueError("worker bundle grew beyond its size bound")
    return data


def run_differential(command: list[str], log, deadline: int) -> tuple[int, bool]:
    """Cancel the owned driver and its compiler children together."""
    def interrupted(signum, _frame):
        raise SystemExit(128 + signum)
    handlers = {signum: signal.signal(signum, interrupted)
                for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)}
    child = None
    try:
        child = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                 start_new_session=True)
        try:
            return child.wait(timeout=deadline), False
        except subprocess.TimeoutExpired:
            return 2, True
    finally:
        if child is not None:
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            child.wait()
        for signum, handler in handlers.items():
            signal.signal(signum, handler)


def differential_worker(request: dict, output: Path) -> dict:
    """Run the existing strict oracle; require its complete concrete input bundle."""
    script, project, adapter, entry = DIFFERENTIAL[request["name"]]
    command = [sys.executable, str(ROOT / script), "--strict-campaign"]
    replay = request["operation"] == "replay"
    bundle = Path(request["bundle"]) if replay else output / "corpus.json"
    if replay:
        command += ["--steps", "0", "--replay-corpus", str(bundle)]
    else:
        command += ["--steps", str(request["steps"]), "--seed", str(request["seed"]),
                    "--project", str(ROOT / project), "--corpus-out", str(bundle)]
    if adapter == "incremental-v1":
        command += ["--entry", entry]
    command.append(request["binary"])
    status = 2
    failure = None
    with (output / "worker.log").open("wb") as log:
        status, timed_out = run_differential(command, log, request["deadline"])
        if timed_out:
            failure = "differential shard exceeded its deadline"
    # Import only in the worker, after the coordinator installed source watches.
    sys.path.insert(0, str(ROOT / "tests"))
    import differential_corpus
    count = 0
    try:
        document = differential_corpus.load(bundle, adapter)
        count = len(document["cases"])
        if not replay and count != request["steps"]:
            raise ValueError("worker corpus does not cover the requested shard")
    except (OSError, ValueError) as error:
        failure = str(error)
    return {"version": 1, "kind": "differential", "complete": status == 0 and failure is None,
            "success": status == 0 and failure is None, "status": status,
            "explored": 0 if replay else count, "replayed": count if replay else 0,
            "bundle": str(bundle), "failure": failure}


def worker_request(path: Path, expected_sha256: str) -> dict:
    """Decode exactly the bounded bytes selected by the parent coordinator."""
    if re.fullmatch(r"[0-9a-f]{64}", expected_sha256) is None:
        raise ValueError("invalid expected worker request SHA256")
    data = bounded_bundle(path, evidence.METADATA_MAX_BYTES)
    if hashlib.sha256(data).hexdigest() != expected_sha256:
        raise ValueError("worker request SHA256 mismatch")
    request = json.loads(data, object_pairs_hook=verification.unique_object)
    if type(request) is not dict:
        raise ValueError("worker request must be an object")
    return request


def worker(path: Path, expected_sha256: str) -> int:
    """Private child protocol; the parent alone owns reusable evidence."""
    request = worker_request(path, expected_sha256)
    output = Path(request["output"])
    output.mkdir(parents=True, exist_ok=True)
    if request["kind"] == "differential":
        result = differential_worker(request, output)
    else:
        import fuzz_coverage
        coverage_output = output / "coverage"
        if request["operation"] == "replay":
            result = fuzz_coverage.replay(Path(request["binary"]), Path(request["bundle"]), coverage_output,
                                          timeout=request["timeout"])
        else:
            result = fuzz_coverage.explore(Path(request["binary"]), Path(request["initial_corpus"]), coverage_output,
                                           request["seed"], request["runs"], max_len=request["max_len"],
                                           timeout=request["timeout"], initial_digests=request["initial_digests"])
        result["bundle"] = str(coverage_output / result["bundle"])
        for group in result["artifacts"].values():
            group[:] = ["coverage/" + relative for relative in group]
    verification.atomic_record(output / "result.json", result)
    return 0 if result.get("complete") is True and result.get("success") is True else 1


def targets(args) -> list[dict]:
    if args.kind == "coverage":
        return [{"name": args.name, "inputs": ["scripts/fuzz_coverage.py", str(args.corpus.absolute()) + "/",
                                               *args.input],
                 "settings": {"runs": args.runs, "max_len": args.max_len, "timeout": args.timeout,
                              "coverage_schema": args.coverage_schema}}]
    result = []
    for name in args.target or DIFFERENTIAL:
        script, project, adapter, entry = DIFFERENTIAL[name]
        result.append({"name": name,
                       "inputs": [script, "tests/differential_corpus.py", project + "/", "src/stdlib/",
                                  str(args.components.absolute()) + "/", *args.input],
                       "settings": {"steps": args.steps, "adapter": adapter, "entry": entry,
                                    "deadline": args.deadline}})
    return result


def require_stable(snapshots) -> bool:
    if not verification.check_all(snapshots):
        raise evidence.InputsChanged("campaign inputs changed while queued or executing")
    return True


def contract(common: Snapshot, target: Snapshot, host, environment: dict, spec: dict, args) -> dict:
    return {"policy": "independent-seed-shards-v1", "kind": args.kind, "name": spec["name"],
            "master_seed": args.seed, "settings": spec["settings"],
            "execution_limits": verification.ProcessLimits(getattr(args, "action_timeout", None)).execution_identity(),
            "inputs": target.identity, "tools": common.identity, "host": host.identity,
            "environment": verification.key(environment),
            "implementation": [LOADED_CODE_SHA256, identity.LOADED_CODE_SHA256,
                               evidence.LOADED_CODE_SHA256, verification.LOADED_CODE_SHA256,
                               verification_snapshot.LOADED_CODE_SHA256]}


def initial_corpus(snapshot: Snapshot, source: Path, destination: Path) -> dict[Path, str]:
    """Stage only the visible files that were included in the watched identity."""
    destination.mkdir()
    expected = {}
    recipe = str(source.absolute()) + "/"
    for row in snapshot.identity["files"]:
        if verification.matches_recipe(row["path"], recipe, ROOT):
            data = bounded_bundle(ROOT / row["path"])
            if hashlib.sha256(data).hexdigest() != row["sha256"]:
                raise evidence.InputsChanged("initial corpus changed during staging")
            path = destination / row["sha256"]
            path.write_bytes(data)
            expected[path] = row["sha256"]
    return expected


def valid_success(store, result, spec, operation, value, kind) -> bool:
    """Only the coordinator's exact result variant can satisfy an action."""
    fields = {"corpus"} if operation == "replay" else {"corpus", "explored", "replayed"}
    if type(result) is not dict or set(result) != fields:
        return False
    corpus = result["corpus"]
    if not isinstance(corpus, str) or re.fullmatch(r"[0-9a-f]{64}", corpus) is None:
        return False
    if store.read_blob(corpus) is None or (operation == "replay" and corpus != value):
        return False
    if operation == "explore":
        expected = spec["settings"]["steps" if kind == "differential" else "runs"]
        return (type(result["explored"]) is int and result["explored"] == expected
                and type(result["replayed"]) is int and result["replayed"] == 0)
    return True


def retain_corpus(store, family, spec, digest) -> None:
    # The family coordinator lock covers this set. Warm hits need neither
    # rewrite a catalog nor rehash its entire history once per retained shard.
    if digest not in spec["known_corpus"]:
        if not store.retain_corpus(family, [digest]):
            raise evidence.CorpusError("corpus disappeared while retaining its manifest")
        spec["known_corpus"].add(digest)


class CampaignStore:
    """Share immutable evidence while keeping corpus ownership in this checkout."""
    def __init__(self, private: Path, shared: Path | None):
        self.local = evidence.Store(private)
        self.success = self.local if shared is None or Path(shared).resolve() == self.local.root else evidence.Store(shared)

    def lease(self):
        stack = ExitStack()
        try:
            stack.enter_context(self.success.lease())
            if self.local is not self.success:
                stack.enter_context(self.local.lease())
            return stack
        except BaseException:
            stack.close()
            raise

    def __getattr__(self, name):
        return getattr(self.success, name)

    def coordinator_lock(self, family):
        # Both locks span lookup, invalidation, work, and publication. Canonical
        # ordering also handles callers that reverse the two store roles.
        stores = [self.success] if self.success is self.local else sorted(
            [self.success, self.local], key=lambda store: str(store.root))
        stack = ExitStack()
        try:
            for store in stores:
                stack.enter_context(store.coordinator_lock(family))
            return stack
        except BaseException:
            stack.close()
            raise

    def load_corpus(self, family):
        return self.local.load_corpus(family)

    def discard_corpus(self, family):
        return self.local.discard_corpus(family)

    def read_blob(self, digest):
        data = self.success.read_blob(digest)
        return self.local.read_blob(digest) if data is None else data

    def put_blob(self, data):
        digest = self.success.put_blob(data)
        if self.local is not self.success and self.local.put_blob(data) != digest:
            raise evidence.CorpusError("private corpus copy changed identity")
        return digest

    def publish_success(self, key, result, blobs, validate):
        # A shared eviction must not strand the replay proof: the retained
        # private corpus supplies the same checked bytes before publication.
        for digest in blobs:
            if self.success.read_blob(digest) is None:
                data = self.local.read_blob(digest)
                if data is None or self.success.put_blob(data) != digest:
                    raise evidence.CorpusError("referenced corpus unavailable for shared publication")
        if not self.success.publish_success(key, result, blobs, validate):
            raise ValueError("completed fuzz action could not publish qualified success")
        return True

    def retain_corpus(self, family, digests):
        for digest in digests:
            data = self.read_blob(digest)
            if data is None or self.local.put_blob(data) != digest:
                raise evidence.CorpusError("corpus disappeared before its private copy")
        return self.local.retain_corpus(family, digests)


def execute_action(store, campaign: str, bound: dict, spec: dict, operation: str,
                   value: int | str, state: dict, args, environment: dict, snapshots, snapshot: Snapshot) -> bool:
    """Reuse or run one bounded action, then publish only fully observed success."""
    action_key = identity.action(bound, operation, value)
    allowed = not args.force and not state["freshness_reasons"]
    require_stable(snapshots)
    hit = store.load_success(action_key) if allowed else None
    if valid_success(store, hit, spec, operation, value, args.kind):
        require_stable(snapshots)
        if hit.get("corpus"):
            retain_corpus(store, campaign, spec, hit["corpus"])
        state["actions"].append({"target": spec["name"], "operation": operation, "value": value,
                                 "state": "reused", "key": action_key})
        return True
    maximum = getattr(args, "max_actions", None)
    executed = sum(row["state"] == "executed" for row in state["actions"])
    if maximum is not None and executed >= maximum:
        state["work_budget"]["exhausted"] = True
        state["actions"].append({"target": spec["name"], "operation": operation, "value": value,
                                 "state": "skipped", "key": action_key, "reason": "admitted action work ceiling"})
        return False
    # A missing blob can make an old receipt miss. A failed worker may repair
    # the blob, but must never thereby resurrect that older success.
    store.invalidate_success(action_key)
    area = Path(tempfile.mkdtemp(prefix="action-", dir=args.cache_dir / "runs"))
    request = {"kind": args.kind, "name": spec["name"], "binary": str(args.binary),
               "operation": operation, "output": str(area), **spec["settings"]}
    staged_files = {}
    staged_recipes = []
    if operation == "replay":
        data = store.read_blob(value)
        if data is None:
            raise evidence.CorpusError("retained corpus disappeared before replay")
        bundle = area / "input.json"
        bundle.write_bytes(data)
        staged_files[bundle] = value
        request["bundle"] = str(bundle)
    else:
        request["seed"] = identity.seed(args.seed, value)
        if args.kind == "coverage":
            request["initial_corpus"] = str(area / "initial")
            staged_files.update(initial_corpus(snapshot, args.corpus, area / "initial"))
            request["initial_digests"] = sorted(staged_files.values())
            staged_recipes.append(str(area / "initial") + "/")
    request_path = area / "request.json"
    verification.atomic_record(request_path, request)
    request_sha256 = hashlib.sha256(verification.encoded(request) + b"\n").hexdigest()
    staged_files[request_path] = request_sha256
    command = [sys.executable, str(ROOT / "scripts/fuzz_campaign.py"), "--worker",
               str(request_path), request_sha256]
    with Snapshot(ROOT, staged_recipes, list(staged_files)) as staged:
        expected = {str(path.resolve()): digest for path, digest in staged_files.items()}
        captured = {str((ROOT / row["path"]).resolve()): row["sha256"]
                    for row in staged.identity["files"]}
        if captured != expected:
            raise evidence.InputsChanged("staged action inputs changed during capture")
        action_snapshots = [*snapshots, staged]
        require_stable(action_snapshots)
        print(f"fuzz: execute {spec['name']} {operation} {value}", flush=True)
        limits = {} if getattr(args, "action_timeout", None) is None else {
            "limits": verification.ProcessLimits(args.action_timeout)}
        status, _held = verification.run_admitted(ROOT, "gate", command, environment,
            lambda: require_stable(action_snapshots), timings=state["admissions"], **limits)
        require_stable(action_snapshots)
        result = bounded_json(area / "result.json") if (area / "result.json").exists() else {}
        complete = status == 0 and result.get("success") is True and result.get("complete") is True
        if complete:
            expected = spec["settings"]["steps" if args.kind == "differential" else "runs"]
            count = result.get("explored" if operation == "explore" else "replayed")
            complete = (type(count) is int and count >= 0
                        and (operation == "replay" or count == expected))
            if args.kind == "coverage":
                complete = complete and result.get("engine", {}).get("coverage_schema") == args.coverage_schema
        corpus = None
        if operation == "replay":
            corpus = value
        elif result.get("bundle"):
            path = Path(result["bundle"])
            path = path if path.is_absolute() else area / path
            if path.is_file() and path.resolve().is_relative_to(area.resolve()):
                corpus = store.put_blob(bounded_bundle(path))
                retain_corpus(store, campaign, spec, corpus)
        if complete and corpus is None:
            raise ValueError("completed fuzz worker did not retain its input corpus")
        if not complete and corpus is not None:
            store.invalidate_success(identity.action(bound, "replay", corpus))
        row = {"target": spec["name"], "operation": operation, "value": value,
               "state": "executed", "key": action_key, "success": complete,
               "evidence": str(area), "explored": result.get("explored", 0),
               "replayed": result.get("replayed", 0)}
        state["actions"].append(row)
        if complete and not state["freshness_reasons"]:
            saved = {"corpus": corpus}
            if operation == "explore":
                saved.update(explored=result["explored"], replayed=0)
            store.publish_success(action_key, saved, [corpus], lambda: require_stable(action_snapshots))
            # A successful exploration just exercised its exported cases/corpus.
            # This is proof for this exact binary, never coverage for a changed one.
            replay_key = identity.action(bound, "replay", corpus)
            store.publish_success(replay_key, {"corpus": corpus}, [corpus], lambda: require_stable(action_snapshots))
        require_stable(action_snapshots)
        return complete


def run_target(store, spec: dict, common, host, environment, args, state, snapshot, snapshots) -> bool:
    campaign = identity.family(ROOT, args.kind, spec["name"])
    with store.coordinator_lock(campaign):
        require_stable(snapshots)
        bound = contract(common, snapshot, host, environment, spec, args)
        try:
            corpus = store.load_corpus(campaign)
        except evidence.CorpusError as error:
            state["corpus_recovery"].append({"target": spec["name"], "reason": str(error)})
            if not args.discard_corrupt_corpus:
                raise evidence.CorpusError("retained corpus is incomplete; repair it or explicitly use --discard-corrupt-corpus to accept its loss") from error
            store.discard_corpus(campaign)
            corpus = []
        spec["known_corpus"] = set(corpus)
        state["required_actions"][spec["name"]] = [
            {"operation": "replay", "value": digest} for digest in corpus] + [
            {"operation": "explore", "value": ordinal} for ordinal in range(args.shards)]
        if args.force:
            for ordinal in range(args.shards):
                store.invalidate_success(identity.action(bound, "explore", ordinal))
            for digest in corpus:
                store.invalidate_success(identity.action(bound, "replay", digest))
        for digest in corpus:
            if not execute_action(store, campaign, bound, spec, "replay", digest,
                                  state, args, environment, snapshots, snapshot):
                return False
            save_report(args, state)
        for ordinal in range(args.shards):
            if not execute_action(store, campaign, bound, spec, "explore", ordinal,
                                  state, args, environment, snapshots, snapshot):
                return False
            save_report(args, state)
        return require_stable(snapshots)


def save_report(args, state) -> None:
    state["counts"] = {"executed_shards": sum(a["operation"] == "explore" and a["state"] == "executed" for a in state["actions"]),
                       "reused_shards": sum(a["operation"] == "explore" and a["state"] == "reused" for a in state["actions"]),
                       "executed_replays": sum(a["operation"] == "replay" and a["state"] == "executed" for a in state["actions"]),
                       "reused_replays": sum(a["operation"] == "replay" and a["state"] == "reused" for a in state["actions"]),
                       "explored": sum(a.get("explored", 0) for a in state["actions"]),
                       "replayed": sum(a.get("replayed", 0) for a in state["actions"])}
    satisfied = {(row["target"], row["operation"], row["value"]) for row in state["actions"]
                 if row["state"] == "reused" or row.get("success") is True}
    state["outstanding"] = [{"target": name, **action} for name, actions in state["required_actions"].items()
                            for action in actions if (name, action["operation"], action["value"]) not in satisfied]
    state["unvisited_targets"] = [name for name in state["targets"] if name not in state["required_actions"]]
    verification.atomic_record(args.report, state)


def execute(args) -> int:
    environment = verification.normalized_environment(ROOT)
    args.binary = identity.executable(str(args.compiler if args.kind == "differential" else args.engine), environment)
    zig = None
    provider_files, provider_binaries = [], []
    if args.kind == "differential":
        zig = identity.executable(args.zig, environment)
        environment["MYLANG_ZIG"] = str(zig)
        environment["ZIG"] = str(zig)
        args.components = args.components or args.binary.parent.parent / "libexec/mylang/components"
        environment["MYLANG_COMPONENT_DIR"] = str(args.components.absolute())
        provider_files, provider_binaries = identity.components(args.components)
    args.cache_dir = args.cache_dir.absolute()
    args.report = (args.report or args.cache_dir / "last-run.json").absolute()
    (args.cache_dir / "runs").mkdir(parents=True, exist_ok=True)
    specs = targets(args)
    state = {"version": 1, "kind": args.kind, "policy": "independent-seed-shards-v1",
             "requested_shards": args.shards * len(specs), "complete": False, "success": False,
             "actions": [], "admissions": [], "freshness_reasons": identity.unsupported(environment),
             "corpus_recovery": [], "targets": [spec["name"] for spec in specs], "required_actions": {},
             "work_budget": {"max_actions": args.max_actions, "action_timeout_seconds": args.action_timeout,
                             "scope": "admitted missing actions; qualified reuse consumes no work", "exhausted": False}}
    if args.kind == "coverage" and not args.hermetic:
        state["freshness_reasons"].append("external coverage target has no complete input contract (--hermetic)")
    save_report(args, state)
    try:
        shared = getattr(args, "shared_cache_dir", None)
        store = CampaignStore(args.cache_dir / "evidence-v2", shared)
        binaries = [args.binary, *provider_binaries]
        recipes, files = identity.tools(environment, binaries, zig)
        with ExitStack() as stack:
            stack.enter_context(store.lease())
            session = verification_snapshot.DigestSession()
            common = stack.enter_context(Snapshot(ROOT, identity.COMMON_INPUTS + recipes, files + provider_files,
                                                  digest_session=session))
            host = verification.HostContext()
            if identity.tools(environment, binaries, zig) != (recipes, files):
                raise evidence.InputsChanged("tool resolution changed during input capture")
            if args.kind == "differential" and identity.components(args.components) != (provider_files, provider_binaries):
                raise evidence.InputsChanged("component resolution changed during input capture")
            targets_snapshots = [stack.enter_context(Snapshot(ROOT, spec["inputs"], digest_session=session)) for spec in specs]
            snapshots = [common, host, *targets_snapshots]
            success = all(run_target(store, spec, common, host, environment, args, state, snapshot, snapshots)
                          for spec, snapshot in zip(specs, targets_snapshots))
            require_stable(snapshots)
            state.update(complete=success, success=success, inputs_stable=True)
            state["snapshot_statistics"] = verification.snapshot_statistics(snapshots)
            state["evidence_store"] = {"shared": shared is not None, "root": str(store.success.root)}
        return 0 if success else 3 if state["work_budget"]["exhausted"] else 1
    except BaseException as error:
        state["error"] = str(error) or type(error).__name__
        raise
    finally:
        save_report(args, state)
        print(json.dumps({"success": state["success"], "complete": state["complete"],
                          "counts": state["counts"], "report": str(args.report)}, sort_keys=True), flush=True)


def options(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="kind", required=True)
    for kind in ("differential", "coverage"):
        part = sub.add_parser(kind)
        part.add_argument("--seed", type=int, default=1)
        part.add_argument("--shards", type=int, default=1)
        part.add_argument("--cache-dir", type=Path, default=ROOT / ".mylang-cache/fuzz-v1")
        part.add_argument("--shared-cache-dir", type=Path, help="Explicit local shared immutable evidence; runs and corpus catalogs stay private")
        part.add_argument("--report", type=Path)
        part.add_argument("--force", action="store_true")
        part.add_argument("--max-actions", type=int, help="Cap admitted missing actions; exhaustion is partial (exit 3)")
        part.add_argument("--action-timeout", type=float, help="Explicit admitted action deadline in seconds, excluding queue time")
        part.add_argument("--discard-corrupt-corpus", action="store_true", help="Explicitly discard an unreadable retained corpus catalog; recover available inputs from valid receipts")
        part.add_argument("--input", action="append", default=[], help="Additional complete runtime dependency recipe")
        if kind == "differential":
            part.add_argument("--compiler", type=Path, default=ROOT / "zig-out/bin/mylang")
            part.add_argument("--components", type=Path)
            part.add_argument("--zig", default=os.environ.get("MYLANG_ZIG") or os.environ.get("ZIG") or "zig")
            part.add_argument("--target", choices=list(DIFFERENTIAL), action="append")
            part.add_argument("--steps", type=int, default=60)
            part.add_argument("--deadline", type=int, default=600)
        else:
            part.add_argument("--name", required=True, help="Stable identity of this independent target")
            part.add_argument("--engine", type=Path, required=True, help="Instrumented libFuzzer executable")
            part.add_argument("--hermetic", action="store_true", help="Certify the target is deterministic and reads only test bytes, declared --input files, and the captured environment; enable reuse")
            part.add_argument("--corpus", type=Path, required=True, help="Immutable initial visible input files")
            part.add_argument("--runs", type=int, default=1000)
            part.add_argument("--max-len", type=int, default=4096)
            part.add_argument("--timeout", type=int, default=10)
            part.add_argument("--coverage-schema", default="libfuzzer-inline8-log-v1")
    args = parser.parse_args(argv)
    if (args.max_actions is not None and not 1 <= args.max_actions <= 1048576
            or args.action_timeout is not None and (not math.isfinite(args.action_timeout) or args.action_timeout <= 0)):
        parser.error("max-actions must be 1..1048576; action-timeout must be positive finite seconds")
    if not 0 <= args.seed < 1 << 64 or not 1 <= args.shards <= 1024:
        parser.error("seed must be u64; shards must be 1..1024")
    if args.kind == "differential":
        if not 1 <= args.steps <= 4096 or not 1 <= args.deadline <= 86400:
            parser.error("steps must be 1..4096; deadline must be 1..86400 seconds")
        if args.target and len(args.target) != len(set(args.target)):
            parser.error("duplicate target")
    elif (not args.name or args.coverage_schema != "libfuzzer-inline8-log-v1" or not args.corpus.is_dir()
          or not 1 <= args.runs <= 1000000 or not 1 <= args.max_len <= 1048576 or not 1 <= args.timeout <= 60):
        parser.error("coverage requires a corpus directory, positive bounded runs, max-len and timeout")
    return args


def main(argv) -> int:
    if argv[:1] == ["--worker"]:
        if len(argv) != 3:
            raise ValueError("private worker requires request path and exact SHA256")
        return worker(Path(argv[1]), argv[2])
    args = options(argv)
    cancellation = 130
    def cancel(signum, _frame):
        nonlocal cancellation
        cancellation = 128 + signum
        raise KeyboardInterrupt
    previous = {signum: signal.signal(signum, cancel) for signum in (signal.SIGTERM, signal.SIGHUP)}
    try:
        return execute(args)
    except evidence.InputsChanged as error:
        print("fuzz: inputs changed: " + str(error), file=sys.stderr)
        return 75
    except (OSError, ValueError, evidence.CorpusError, evidence.FormatError,
            evidence.DeterminismError, SnapshotError, verification.VerificationError) as error:
        print("fuzz: cannot qualify campaign: " + str(error), file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("fuzz: interrupted; only completed actions can be reused", file=sys.stderr)
        return cancellation
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

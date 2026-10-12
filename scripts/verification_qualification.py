#!/usr/bin/env python3
"""Run approved long obligations and retain request-local, guarded authority.

Serialized diagnostics cannot authorize qualification. Only this request's live
execution handle can qualify its exact context and mandatory obligation set.
Existing fuzz receipts remain the only persisted reusable campaign evidence.
"""
from contextlib import ExitStack, redirect_stdout, redirect_stderr
import hashlib
import io
import json
import marshal
from pathlib import Path
import re
import shutil
import sys
import tempfile

from verification_snapshot import Snapshot, SnapshotError
import verify_cache as verification

OBLIGATIONS = ("fuzz", "scaling", "work-counters", "juice-instructions", "wall-clock-performance", "bootstrap")
SUPPORTED = ("fuzz", "scaling", "work-counters", "juice-instructions")
INPUTS = ("scripts/verification_qualification.py", "scripts/verification_profiles.py",
          "scripts/fuzz_campaign.py", "scripts/fuzz_campaign_identity.py", "scripts/fuzz_campaign_store.py",
          "scripts/verification_process.py", "scripts/verification_snapshot.py", "scripts/verify_cache.py",
          "tests/duplicate_scaling.py", "tests/incremental_diff.py", "tests/differential_corpus.py",
          "tests/fixtures/incremental/", "test/fixtures/long-qualification/", "src/",
          "scripts/juice_cache.py", "scripts/juice_evidence.py", "scripts/juice_provider.py", "scripts/juice_worker.py",
          "scripts/juice_tool/",
          "experiments/development-loop-closeout-20261012/S05/workloads/oracle.py")
MAX_OUTPUT = 4 * 1024 * 1024
_LOADED_CODE_OBJECT = sys._getframe().f_code


def validate_options(targets, max_actions, action_timeout, fuzz_steps):
    """Validate bounded controls before any admitted execution."""
    if (type(targets) not in (list, tuple) or len(targets) != len(set(targets))
            or set(targets) - set(OBLIGATIONS) or type(max_actions) is not int or not 1 <= max_actions <= 64
            or type(fuzz_steps) is not int or not 1 <= fuzz_steps <= 4096):
        raise ValueError("invalid named qualification targets or work limits")
    if action_timeout is None:
        raise ValueError("long qualification requires an explicit positive admitted deadline")
    verification.ProcessLimits(action_timeout)


def _read(path):
    path = Path(path)
    with path.open("rb") as stream:
        data = stream.read(MAX_OUTPUT + 1)
    if len(data) > MAX_OUTPUT:
        raise ValueError("qualification output exceeded bound")
    return data


def _json(data):
    return json.loads(data, object_pairs_hook=verification.unique_object)


def scaling_work(data):
    """Validate all six existing scaling cases and extract actual compiler work."""
    lines = data.decode().splitlines()
    patterns = [r"duplicate header index: ([0-9]+) functions, work=([0-9]+), one distant pair, deterministic; two-run elapsed=[0-9.]+s",
                r"duplicate banded distance: ([0-9]+) repeated statements, work=([0-9]+), literal drift retained"]
    expected = [("header-index", size) for size in (128, 512, 1024)] + [("banded-distance", size) for size in (50, 100, 200)]
    if len(lines) != len(expected):
        raise ValueError("scaling did not finish its exact case inventory")
    counters = []
    for line, (family, size) in zip(lines, expected):
        match = re.fullmatch(patterns[0 if family == "header-index" else 1], line)
        if match is None or int(match[1]) != size or not 0 < int(match[2]) <= (4000000 if family == "header-index" else 4100000):
            raise ValueError("missing, partial or corrupt compiler scaling work")
        counters.append({"family": family, "size": size, "work": int(match[2])})
    return {"cases_completed": 6, "compiler_invocations": 9, "counters": counters,
            "scope": "native approximate-duplicate algorithm work; not machine instructions or wall-clock ratios"}


def compiler_work(data):
    """Require actual fresh compiler parsing/body work from its supported report."""
    rows = [_json(line) for line in data.splitlines()]
    work = [row for row in rows if type(row) is dict and row.get("version") == "work-report-v1"]
    if len(work) != 1 or work[0].get("command") != "check":
        raise ValueError("missing unique compiler work report")
    counts = {}
    for name, minimum in (("parsed_modules", 1), ("checked_bodies", 2)):
        cell = work[0].get(name, {})
        performed = cell.get("performed")
        if type(performed) is not int or performed < minimum or cell.get("reused") != 0:
            raise ValueError("compiler did not perform the declared fresh work")
        counts[name] = performed
    return counts


def driver_work(data):
    """Require both forced tests and retain supported key-derivation work once."""
    value = _json(data)
    names = {"cases::test_sum", "cases::test_values"}
    fields = ("passed", "failed", "skipped", "cached", "unsupported")
    rows = value.get("tests") if type(value) is dict else None
    if (type(value) is not dict or value.get("version") != "native-tests-v1"
            or any(type(value.get(name)) is not int for name in fields)
            or [value[name] for name in fields] != [2, 0, 0, 0, 0]
            or type(rows) is not list or len(rows) != 2 or any(type(row) is not dict for row in rows)
            or {row.get("name") for row in rows} != names
            or any(row.get("status") != "passed" or row.get("reason") != ""
                   or row.get("cache", {}).get("action") != "execute" for row in rows)):
        raise ValueError("driver did not complete the exact two fresh passing tests")
    observed = [row["cache"]["work"] for row in rows if row.get("cache", {}).get("work") is not None]
    if len(observed) != 1:
        raise ValueError("driver work observation is missing or double-counted")
    work = observed[0]
    counters = {"facts_fresh": work["producer"]["facts"]["fresh"],
                "lowering_fresh": work["producer"]["lowering"]["fresh"],
                "index_nodes": work["planner"]["index_nodes"],
                "transport_startups": work["transport"]["startups"]}
    if any(type(count) is not int or count < 0 for count in counters.values()):
        raise ValueError("invalid native driver work counters")
    return {"completed_tests": 2, "counters": counters,
            "scope": "once-per-provider key derivation; not guest machine instructions"}


class QualificationRun:
    """Live execution authority; diagnostic rows and JSON are never receipts."""
    def __init__(self, context, area, stack, snapshots):
        self._context = verification.key(context)
        self._stack = stack
        self._snapshots = snapshots
        self._successes = set()
        self._observed_files = {}
        self._closed = False
        self.area = area
        self.additional_snapshots = []
        self.rows = []
        self.admissions = []
        self.execution_contract = {}

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self._closed = True
        self._stack.close()

    def stable(self):
        return not self._closed and verification.check_all(self._snapshots + self.additional_snapshots)

    def authenticated_names(self, context, required):
        if self._closed or self._context != verification.key(context) or tuple(required) != OBLIGATIONS or not self.stable():
            raise ValueError("qualification authority/context/obligation inventory is unavailable or changed")
        return set(self._successes)

    def _freeze(self, directory):
        guard = self._stack.enter_context(Snapshot(directory, ["./"], include_hidden=True))
        self.additional_snapshots.append(guard)
        hashes = {row["path"]: row["sha256"] for row in guard.identity["files"]}
        for path, expected in self._observed_files.items():
            if path.is_relative_to(directory):
                if hashes.get(str(path.relative_to(directory))) != expected:
                    raise ValueError("qualification output changed between parsing and evidence capture")
        return hashes

    def report(self):
        """Return diagnostic data; callers must retain this live handle for authority."""
        return {"version": "long-qualification-v1", "context_sha256": self._context,
                "required": list(OBLIGATIONS), "actions": self.rows, "admissions": self.admissions,
                "execution_contract": self.execution_contract,
                "outstanding": [name for name in OBLIGATIONS if name not in self._successes],
                "authority": "request-local live execution; serialized records cannot authorize completion"}


def qualified_names(run, context, required):
    """Reject fabricated/mismatched/closed results before consulting live authority."""
    if type(run) is not QualificationRun or context is None:
        raise ValueError("qualification requires this request's authenticated execution handle")
    return run.authenticated_names(context, required)


def _admitted(run, root, env, argv, directory, deadline):
    directory.mkdir()
    status, _ = verification.run_admitted(root, "build", argv, env, run.stable,
        timings=run.admissions, limits=verification.ProcessLimits(deadline), log_dir=directory)
    if status != 0 or not run.stable():
        raise ValueError("qualification command failed or inputs changed (exit %d)" % status)
    outputs = []
    for name in ("stdout.log", "stderr.log"):
        path = directory / name
        data = _read(path)
        run._observed_files[path] = hashlib.sha256(data).hexdigest()
        outputs.append(data)
    return tuple(outputs)


def _work(run, root, compiler, env, directory, deadline):
    directory.mkdir()
    fixture = root / "test/fixtures/long-qualification/cases.my"
    trials = []
    for index in range(2):
        stdout, stderr = _admitted(run, root, env, [str(compiler), "check", str(fixture), "--no-cache", "--report"],
                                   directory / ("compiler-%d" % index), deadline)
        if stdout:
            raise ValueError("unexpected compiler-check output")
        checked = compiler_work(stderr)
        stdout, stderr = _admitted(run, root, env, [str(compiler), "test", str(fixture), "--force", "--json",
                                   "--cache-dir", str(directory / "guest-cache")], directory / ("driver-%d" % index), deadline)
        if stderr:
            raise ValueError("unexpected test-driver diagnostics")
        trials.append({"compiler": checked, "driver": driver_work(stdout)})
    if trials[0]["compiler"] != trials[1]["compiler"]:
        raise ValueError("fresh compiler work counts are not repeatable")
    return {"trials": trials, "completed_units": {"compiler_checks": 2, "fresh_guest_tests": 4},
            "regression_policy": "report-only; two trials do not establish performance headroom"}


def _fuzz(run, root, compiler, zig, directory, deadline, steps, campaign_cache):
    import fuzz_campaign
    directory.mkdir()
    args = fuzz_campaign.options(["differential", "--compiler", str(compiler), "--zig", str(zig),
        "--target", "incremental", "--steps", str(steps), "--shards", "1", "--max-actions", "16",
        "--action-timeout", str(deadline), "--cache-dir", str(campaign_cache)])
    output = io.StringIO()
    with redirect_stdout(output), redirect_stderr(output):
        status = fuzz_campaign.execute(args)  # It owns admission; never wrap this coordinator.
    (directory / "coordinator.log").write_text(output.getvalue())
    report_bytes = _read(args.report)
    report = _json(report_bytes)
    if type(report) is dict:
        run.admissions.extend(report.get("admissions", []))
    if (status != 0 or type(report) is not dict or report.get("complete") is not True
            or report.get("success") is not True or report.get("inputs_stable") is not True
            or report.get("outstanding") or report.get("unvisited_targets")
            or report.get("targets") != ["incremental"] or report.get("requested_shards") != 1):
        raise ValueError("fuzz campaign is missing, failed or partial")
    destination = directory / "campaign-report.json"
    destination.write_bytes(report_bytes)
    run._observed_files[destination] = hashlib.sha256(report_bytes).hexdigest()
    guard = run._stack.enter_context(Snapshot(campaign_cache, ["./"], include_hidden=True))
    run.additional_snapshots.append(guard)
    report_name = str(Path(args.report).relative_to(campaign_cache))
    captured = {row["path"]: row["sha256"] for row in guard.identity["files"]}
    if captured.get(report_name) != hashlib.sha256(report_bytes).hexdigest():
        raise ValueError("fuzz report changed between validation and input capture")
    return {"steps_per_shard": steps, "counts": report["counts"], "evidence_report": str(args.report)}


def _juice(run, root, compiler, zig, directory, deadline):
    """Use existing native Juice capture, preserving freshness and raw validation.

    External provider closure stays visibly incomplete. Actual positive counts
    are observations; they cannot authorize a work-regression or wall ratio.
    """
    import juice_cache
    import juice_evidence
    directory.mkdir()
    project = directory / "project"
    project.mkdir()
    shutil.copyfile(root / "test/fixtures/long-qualification/cases.my", project / "cases.my")
    shutil.copyfile(root / "experiments/development-loop-closeout-20261012/S05/workloads/oracle.py", project / "oracle.py")
    workloads = [
        {"name": "compiler-check", "family": "compiler-check", "unit": "checked fixture", "units": 1,
         "args": ["check", "{root}/cases.my", "--no-cache"], "expected_stdout": "", "timeout_seconds": 30},
        {"name": "forced-test-driver", "family": "guest-test-driver", "unit": "fresh passing guest test", "units": 2,
         "args": ["test", "{root}/cases.my", "--force", "--json", "--cache-dir", "{work}/guest-cache"],
         "stdout_regex": '(?:.|\\n)*("passed":2,"failed":0,"skipped":0,"cached":0,"unsupported":0)(?:.|\\n)*',
         "expected_stdout": '"passed":2,"failed":0,"skipped":0,"cached":0,"unsupported":0',
         "check": [sys.executable, "{root}/oracle.py", "{stdout}"], "timeout_seconds": 120}]
    components = compiler.parent.parent / "libexec/mylang/components"
    environment = {"MYLANG_ZIG": str(zig), "ZIG": str(zig)}
    dependencies = [str(compiler), str(zig), str(zig.resolve().parent / "lib")]
    if components.is_dir():
        environment["MYLANG_COMPONENT_DIR"] = str(components)
        dependencies.append(str(components))
    verification.atomic_record(project / "juice.json", {"version": 1, "name": "development-loop-compiler-driver",
        "adapter": "native", "sources": ["cases.my", "oracle.py"], "environment": environment,
        "build": {"compiler": str(compiler), "command": ["cp", "{compiler}", "{binary}"],
                  "tools": ["cp", sys.executable], "dependencies": dependencies, "timeout_seconds": 30},
        "workloads": workloads})
    verification.atomic_record(project / "suite.json", {"version": "juice-suite-v1", "workloads": [
        {"id": work["name"], "manifest": "juice.json", "workload": work["name"],
         "complete": False, "reuse": "fresh"} for work in workloads]})
    args = juice_cache.options(["capture", str(directory / "project/suite.json"), "--compiler", str(compiler),
        "--collector", "perf", "--repeats", "3", "--fresh", "--max-actions", "2",
        "--action-timeout", str(deadline), "--cache-dir", str(directory / "capture")])
    output = io.StringIO()
    with redirect_stdout(output), redirect_stderr(output):
        status = juice_cache.execute(args)  # Owns admission. Never nest a timing slot.
    (directory / "coordinator.log").write_text(output.getvalue())
    data = _read(args.report)
    report = _json(data)
    run._observed_files[Path(args.report)] = hashlib.sha256(data).hexdigest()
    run.admissions.extend(report.get("admissions", []))
    if status != 0 or report.get("complete") is not True or report.get("success") is not True or report.get("outstanding"):
        raise ValueError("native Juice capture failed or is partial")
    observed = []
    for action in report["actions"]:
        if action.get("fresh") is not True or action.get("state") != "executed":
            raise ValueError("fresh instruction request was satisfied by old evidence")
        retained = juice_evidence.validate_record(Path(action["record"]),
            {kind: Path(path) for kind, path in action["artifacts"].items()}, action["expected"])
        if retained.record_digest != action["record_sha256"]:
            raise ValueError("native instruction record changed")
        record_path = Path(action["record"])
        run._observed_files[record_path] = retained.record_digest
        for name, digest in retained.files.items():
            run._observed_files[record_path.parent / name] = digest
        for kind, digest in retained.build_artifacts.items():
            run._observed_files[Path(action["artifacts"][kind])] = digest
        work = retained.record["workloads"][action["expected"]["workload"]["name"]]
        counts = [sample["metrics"]["instructions"] for sample in work["samples"]]
        if len(counts) != 3 or any(type(count) not in (int, float) or count <= 0 for count in counts):
            raise ValueError("native instruction sample inventory is insufficient")
        observed.append({"id": action["id"], "instructions": counts, "units": work["units"],
                         "record_sha256": retained.record_digest, "collector": retained.record["collector"],
                         "freshness_reasons": action["freshness_reasons"]})
    if {row["id"] for row in observed} != {"compiler-check", "forced-test-driver"}:
        raise ValueError("native Juice workload inventory differs")
    return {"qualification_complete": False,
            "qualification_reason": "real fully-counted native samples retained; external provider closure and repeatability regression calibration remain unqualified",
            "workloads": observed, "scope": "physical user instructions, inherited children, selected CPU-specific PMU; not wall-clock ratios",
            "regression_policy": "report-only; no latency or work-regression acceptance from these samples"}


def qualify(root, cache, compiler, zig, context, snapshots, *, targets=None, max_actions=4, action_timeout=300, fuzz_steps=8):
    """Execute approved bounded obligations; unsupported obligations remain visible."""
    targets = list(OBLIGATIONS if targets is None else targets)
    validate_options(targets, max_actions, action_timeout, fuzz_steps)
    root, compiler, zig = Path(root), Path(compiler), Path(zig)
    cache = Path(cache)
    cache.mkdir(parents=True, exist_ok=True)
    area = Path(tempfile.mkdtemp(prefix="qualification-", dir=cache))
    stack = ExitStack()
    run = QualificationRun(context, area, stack, list(snapshots))
    run.execution_contract = {"targets": targets, "max_obligations": max_actions,
        "admitted_command_timeout_seconds": action_timeout, "fuzz_steps_per_shard": fuzz_steps,
        "fuzz_shards": 1, "fuzz_max_admitted_actions": 16, "juice_repeats": 3,
        "measurement_policy": "fresh physical captures; report-only; no wall-clock qualification"}
    try:
        recipes = list(INPUTS) + [str(zig.resolve().parent / "lib") + "/"]
        components = compiler.parent.parent / "libexec/mylang/components"
        if components.is_dir():
            recipes.append(str(components) + "/")
        guard = stack.enter_context(Snapshot(root, recipes, [compiler, zig]))
        run.additional_snapshots.append(guard)
        env = verification.normalized_environment(root)
        env.update(ZIG=str(zig), MYLANG_ZIG=str(zig))
        if components.is_dir():
            env["MYLANG_COMPONENT_DIR"] = str(components)
        executed = 0
        for name in OBLIGATIONS:
            row = {"id": name, "complete": False, "success": False, "qualified": False}
            run.rows.append(row)
            if name not in targets:
                row.update(state="deferred", reason="not selected; obligation remains required")
                continue
            if name not in SUPPORTED:
                row.update(state="unsupported", reason={
                    "juice-instructions": "no qualified machine instruction collector; source counts cannot substitute",
                    "wall-clock-performance": "requires S10 scheduled matched timing qualification",
                    "bootstrap": "requires current authenticated stages, parity and per-workload ratios"}[name])
                continue
            if executed >= max_actions:
                row.update(state="partial", reason="configured obligation work ceiling exhausted")
                continue
            executed += 1
            directory = area / name
            try:
                if not run.stable():
                    raise ValueError("qualification input authority changed")
                if name == "fuzz":
                    observed = _fuzz(run, root, compiler, zig, directory, action_timeout, fuzz_steps, cache / "fuzz-campaign")
                elif name == "scaling":
                    stdout, stderr = _admitted(run, root, env,
                        [sys.executable, str(root / "tests/duplicate_scaling.py"), "--compiler", str(compiler)], directory, action_timeout)
                    if stderr:
                        raise ValueError("scaling emitted unexpected diagnostics")
                    observed = scaling_work(stdout)
                elif name == "juice-instructions":
                    observed = _juice(run, root, compiler, zig, directory, action_timeout)
                else:
                    observed = _work(run, root, compiler, env, directory, action_timeout)
                hashes = run._freeze(directory)
                if not run.stable():
                    raise ValueError("qualification evidence/input authority changed")
                row.update(observed=observed, evidence_sha256=hashes)
                if observed.get("qualification_complete", True) is not True:
                    row.update(state="partial", reason=observed["qualification_reason"])
                else:
                    row.update(state="executed", complete=True, success=True, qualified=True)
                    run._successes.add(name)
            except (OSError, ValueError, KeyError, TypeError, SnapshotError, verification.VerificationError) as error:
                row.update(state="partial", reason=str(error)[:1024])
        verification.atomic_record(area / "report.json", run.report())
        return run
    except BaseException:
        run.__exit__()
        raise


LOADED_CODE_SHA256 = hashlib.sha256(marshal.dumps(_LOADED_CODE_OBJECT)).hexdigest()

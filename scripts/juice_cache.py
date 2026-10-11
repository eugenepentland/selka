#!/usr/bin/env python3
"""Reuse qualified native Juice measurements before requesting server admission.

This developer coordinator owns admission. Installed Juice commands remain native.
Suite declarations close external dependencies; they are attestations, not a sandbox.
"""
from __future__ import annotations

import argparse
from contextlib import ExitStack
import hashlib
import json
import marshal
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile

import fuzz_campaign_identity as identity
import fuzz_campaign_store
import juice_evidence
import juice_provider
import juice_worker
import verification_snapshot
from verification_snapshot import Snapshot, SnapshotError
import verify_cache as verification

ROOT = Path(__file__).resolve().parents[1]
LOADED_CODE_SHA256 = hashlib.sha256(marshal.dumps(sys._getframe().f_code)).hexdigest()
IMPLEMENTATION_INPUTS = ["scripts/juice_cache.py", "scripts/juice_evidence.py",
    "scripts/juice_worker.py", "scripts/juice_provider.py",
    "scripts/fuzz_campaign_identity.py", "scripts/fuzz_campaign_store.py",
    "scripts/verification_snapshot.py", "scripts/cache_session.py", "scripts/verify_cache.py", "scripts/build-slot.sh",
    "scripts/juice_tool/__init__.py", "scripts/juice_tool/collectors.py", "scripts/juice_tool/common.py"]


def document(path: Path) -> dict:
    value = verification.read_record(path)
    if value is None:
        raise ValueError("missing or malformed JSON object: " + str(path))
    return value


def suite(path: Path, selected: list[str]) -> list[dict]:
    """Load bounded explicit workload contracts; unknown dependency sets stay fresh."""
    value = document(path)
    if set(value) != {"version", "workloads"} or value["version"] != "juice-suite-v1":
        raise ValueError("expected juice-suite-v1 with version and workloads")
    rows = value["workloads"]
    if type(rows) is not list or not 1 <= len(rows) <= 256:
        raise ValueError("suite requires 1..256 workloads")
    result, names = [], set()
    for row in rows:
        allowed = {"id", "manifest", "workload", "dependencies", "complete", "reuse"}
        if type(row) is not dict or set(row) - allowed or not {"id", "manifest", "workload"} <= set(row):
            raise ValueError("invalid workload declaration")
        name = row["id"]
        if not isinstance(name, str) or re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,63}", name) is None or name in names:
            raise ValueError("workload IDs must be unique simple names")
        names.add(name)
        for field in ("manifest", "workload"):
            if not isinstance(row[field], str) or not row[field] or "\0" in row[field]:
                raise ValueError("manifest and workload must be nonempty strings")
        deps = row.get("dependencies", [])
        if type(deps) is not list or any(not isinstance(p, str) or not p or "\0" in p for p in deps):
            raise ValueError("dependencies must contain literal files or recursive directories")
        if type(row.get("complete", False)) is not bool or row.get("reuse", "fresh") not in ("fresh", "deterministic", "historical"):
            raise ValueError("invalid complete/reuse policy")
        result.append({**row, "manifest": str((path.parent / row["manifest"]).absolute()),
                       "dependencies": [str((path.parent / p).absolute()) + ("/" if p.endswith("/") else "") for p in deps],
                       "complete": row.get("complete", False), "reuse": row.get("reuse", "fresh")})
    if len(selected) != len(set(selected)) or set(selected) - names:
        raise ValueError("duplicate or unknown selected workload")
    return [row for row in result if not selected or row["id"] in selected]


def command(args, spec: dict, operation: str, *, cpu: int | None = None) -> list[str]:
    argv = [str(args.compiler), "juice", operation, spec["manifest"],
            "--cache-dir", str(args.cache_dir / "native"), "--tier", "all",
            "--workload", spec["workload"], "--repeats", str(args.repeats),
            "--collector", args.collector, "--profile", args.profile,
            "--perf", args.perf, "--valgrind", args.valgrind]
    chosen = cpu if cpu is not None else args.cpu
    if chosen is not None:
        argv += ["--cpu", str(chosen)]
    if args.build_compiler:
        argv += ["--compiler", args.build_compiler]
    if args.static:
        argv.append("--static")
    return argv


def plan(args, spec: dict, env: dict) -> dict:
    result = subprocess.run(command(args, spec, "plan"), cwd=ROOT, env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180)
    if result.returncode:
        raise ValueError("native Juice plan failed: " + result.stderr.decode(errors="replace"))
    if len(result.stdout) > verification.MAX_RECORD:
        raise ValueError("native Juice plan exceeded its size bound")
    value = json.loads(result.stdout, object_pairs_hook=verification.unique_object)
    if (type(value) is not dict or value.get("version") != "juice-plan-v1"
            or len(value.get("selected_workloads", [])) != 1
            or value["selected_workloads"][0]["name"] != spec["workload"]):
        raise ValueError("native plan does not identify the requested workload")
    return value


def require_stable(snapshots) -> bool:
    if not verification.check_all(snapshots):
        raise fuzz_campaign_store.InputsChanged("Juice inputs changed while planning, queued or executing")
    return True


def target_inputs(spec: dict, native: dict, cache: Path, report: Path) -> tuple[list[str], list[Path]]:
    """Watch complete glob bases rather than duplicate native glob semantics."""
    recipes = list(spec["dependencies"])
    recipes += [path.rstrip("/") + "/" for path in native["input_scopes"]["directories"]]
    if native["manifest"]["adapter"] == "mylang":
        zig = Path(native["build_config"]["tools"]["zig"]["path"])
        recipes.append(str(zig.resolve().parent / "lib") + "/")
    for recipe in recipes:
        if any(char in recipe for char in "*?["):
            raise ValueError("external dependencies must be literal paths; use a directory ending in /")
        path = Path(recipe)
        if path.is_dir() != recipe.endswith("/"):
            raise ValueError("directory dependencies need a trailing /; file dependencies must be regular files")
        resolved = path.resolve()
        if recipe.endswith("/") and (cache.resolve().is_relative_to(resolved) or report.resolve().is_relative_to(resolved)):
            raise ValueError("cache and report must be outside every watched dependency/glob directory")
    return sorted(set(recipes)), [Path(p) for p in native["input_scopes"]["files"]]


def tool_paths(args, native: dict, env: dict) -> list[Path]:
    """Retain lexical lookup aliases as well as native canonical tool identities."""
    configuration = native["build_config"]
    build = native["manifest"]["build"]
    compiler = args.build_compiler or build.get("compiler") or build.get("command", [configuration["compiler"]["path"]])[0]
    if native["manifest"]["adapter"] == "mylang" and compiler == "mylang":
        compiler = str(args.compiler)
    selected = [compiler, *build.get("tools", []), args.perf if args.collector == "perf" else args.valgrind]
    if native["manifest"]["adapter"] == "mylang":
        selected.append(env.get("ZIG") or env.get("MYLANG_ZIG") or "zig")
    return [identity.executable(name, env) for name in selected]


def expected(native: dict, args) -> dict:
    return {"workload": native["selected_workloads"][0], "repeats": args.repeats,
            "collector": native["measurement"]["collector"], "profile": args.profile,
            "sources": native["sources"], "build_config": native["build_config"],
            "source_root": native["root"], "tool_id": native["implementation"]["embedded_identity"],
            "contract": {"name": native["manifest"]["name"], "inputs": native["inputs"],
                         "environment": native["manifest"]["environment"],
                         "workloads": native["selected_workloads"]}}


def reasons(spec: dict, args, env: dict, native: dict) -> list[str]:
    result = identity.unsupported(env)
    if not spec["complete"]:
        result.append("external execution/provider dependencies are not declared complete")
    if spec["reuse"] == "fresh":
        result.append("fresh-only workload policy")
    if spec["reuse"] == "deterministic" and args.collector == "perf":
        result.append("physical perf samples require historical policy; they are not deterministic counts")
    if args.collector != "perf" and not env.get("VALGRIND_LIB"):
        result.append("software counting requires an explicit watched VALGRIND_LIB provider scope")
    if native["manifest"]["adapter"] == "mylang":
        entry = Path(native["manifest"]["build"]["entry"])
        configs = {(parent / "mylang.json").as_posix() for parent in entry.parents}
        if not configs.intersection(native["sources"]):
            result.append("Selka harness requires a declared enclosing mylang.json to exclude ancestor configuration")
    return result


def file_hashes(snapshots) -> dict[str, str]:
    result = {}
    for snapshot in snapshots:
        if not isinstance(snapshot, Snapshot):
            continue
        for row in snapshot.identity["files"]:
            for label in (row["path"], row.get("resolved", row["path"])):
                result[str((snapshot._requested_root / label).absolute())] = row["sha256"]
    return result


def covered_libraries(record: dict, snapshots) -> bool:
    """Dynamically discovered libraries are evidence only if watched before work."""
    captured = file_hashes(snapshots)
    libraries = record.get("context", {}).get("libraries")
    return type(libraries) is dict and all(captured.get(path) == digest for path, digest in libraries.items())


def provider_tools(env):
    """Select the bound Linux loader inspection tools, or leave evidence fresh."""
    try:
        selected = juice_provider.Tools(identity.executable("readelf", env), identity.executable("ldd", env))
        if not selected.loader.is_file() or not selected.ldconfig.is_file():
            return None
        return selected
    except verification.VerificationError:
        return None


def provider_qualified(artifacts, record, native, env, tools, scopes, snapshots) -> bool:
    """Prove current resolution against providers and search paths guarded before work."""
    if tools is None:
        return False
    runtime = juice_provider.environment(native)
    resolved = juice_provider.resolve(artifacts, runtime, env, tools)
    if resolved is None or resolved.get("plain") != record.get("context", {}).get("libraries"):
        return False
    if any(resolved.values()):
        if scopes is None or juice_provider.search_scopes(runtime, env, tools) != scopes:
            return False
    captured = file_hashes(snapshots)
    return all(captured.get(path) == digest for providers in resolved.values() for path, digest in providers.items())


def context_matches(record: dict, native: dict) -> bool:
    actual = dict(record.get("context", {}))
    actual["libraries"] = {}
    return actual == native["measurement"]["context"]


def artifact_paths(record: dict, native: dict) -> dict[str, Path]:
    return {kind: Path(native["paths"]["cache"]) / "builds" / record["build"]["key"] / kind
            for kind in record["build"]["artifacts"]}


def action_key(spec, native, common, target, host, env) -> str:
    return verification.key({"domain": "juice-measurement-v1", "workload": spec,
        "plan": native, "common": common.identity, "dependencies": target.identity,
        "host": host.identity, "environment": verification.key(env),
        "implementation": [LOADED_CODE_SHA256, identity.LOADED_CODE_SHA256,
                           verification.LOADED_CODE_SHA256, verification_snapshot.LOADED_CODE_SHA256,
                           fuzz_campaign_store.LOADED_CODE_SHA256,
                           juice_evidence.LOADED_CODE_SHA256, juice_evidence.PARSER_CODE_SHA256,
                           juice_worker.LOADED_CODE_SHA256, juice_provider.LOADED_CODE_SHA256]})


def run_target(store, spec, native, args, env, bound, snapshots, bound_snapshots, state, tools, scopes, stack) -> bool:
    want = expected(native, args)
    fresh_reasons = reasons(spec, args, env, native)
    family = verification.key({"domain": "juice-workload-v1", "cache": native["paths"]["cache"]})
    with store.coordinator_lock(family):
        require_stable(snapshots)
        if args.fresh:
            store.discard(bound)
        hit = None if args.fresh or fresh_reasons else store.lookup(bound, want)
        area = Path(tempfile.mkdtemp(prefix="capture-", dir=args.cache_dir / "runs"))
        row = {"id": spec["id"], "key": bound, "policy": spec["reuse"],
               "expected": want, "state": "incomplete", "fresh": False,
               "freshness_reasons": fresh_reasons, "success": False, "qualified": False}
        state["actions"].append(row)
        if hit is not None and covered_libraries(hit.record, bound_snapshots) and context_matches(hit.record, native):
            path = store.materialize(hit, area / "retained")
            artifacts = {kind: area / "retained/build" / kind for kind in hit.build_artifacts}
            snapshots.append(stack.enter_context(Snapshot(ROOT, [str(area / "retained") + "/"], include_hidden=True)))
            checked = juice_evidence.validate_record(path, artifacts, want)
            valid = checked.record_digest == hit.record_digest and provider_qualified(
                artifacts, hit.record, native, env, tools, scopes, bound_snapshots)
            require_stable(snapshots)
            if valid:
                row.update(state="reused", success=True, qualified=True, record=str(path), record_sha256=hit.record_digest,
                           artifacts={kind: str(value) for kind, value in artifacts.items()})
                print("juice-cache: reuse " + spec["id"] + " (" + spec["reuse"] + " evidence)", flush=True)
                return True
        # A failing fresh capture must not revive a prior receipt by repairing a blob.
        store.discard(bound)
        argv = command(args, spec, "record", cpu=native["measurement"]["collector"]["cpu"])
        argv += ["--name", area.name]
        path = Path(native["paths"]["cache"]) / "records" / area.name / "record.json"
        row.update(state="executed", record=str(path), fresh=True)
        print("juice-cache: capture " + spec["id"], flush=True)
        worker = [sys.executable, str(ROOT / "scripts/juice_worker.py"), *argv]
        status, _held = verification.run_admitted(ROOT, "gate", worker, env,
            lambda: require_stable(snapshots), timings=state["admissions"])
        require_stable(snapshots)
        if status:
            row["status"] = status
            return False
        artifacts = juice_evidence.artifact_paths(path)
        # Freeze the exact native outputs before provider inspection, and retain
        # this guard through receipt and final run-report publication. Restoring
        # an artifact after tracing different bytes cannot certify the original.
        snapshots.append(stack.enter_context(Snapshot(ROOT, [str(path.parent) + "/"],
                                                       list(artifacts.values()), include_hidden=True)))
        retained = juice_evidence.validate_record(path, artifacts, want)
        record = retained.record
        # Native CPU/scheduling configuration is read again outside the server lock.
        if plan(args, spec, env) != native or not context_matches(record, native):
            raise fuzz_campaign_store.InputsChanged("native measurement context changed during capture")
        if not provider_qualified(artifacts, record, native, env, tools, scopes, bound_snapshots):
            fresh_reasons.append("runtime provider resolution is unsupported or not fully guarded before capture")
        row.update(success=True, record_sha256=retained.record_digest,
                   artifacts={kind: str(path) for kind, path in artifacts.items()})
        if not fresh_reasons:
            row["qualified"] = store.publish(bound, path, artifacts, want, lambda: require_stable(snapshots))
            if not row["qualified"]:
                fresh_reasons.append("measurement publication conflicted with an existing action contract")
        require_stable(snapshots)
        return True


def save_report(args, state):
    state["counts"] = {"executed": sum(row["state"] == "executed" for row in state["actions"]),
                       "reused": sum(row["state"] == "reused" for row in state["actions"]),
                       "admissions": len(state["admissions"])}
    verification.atomic_record(args.report, state)


def protect_outputs(args, snapshots) -> None:
    """Reject input/output overlap before the first destructive report write."""
    outputs = [args.report.resolve(), (args.cache_dir / "runs").resolve(),
               (args.cache_dir / "native").resolve(), (args.cache_dir / "evidence-v2").resolve()]
    if getattr(args, "shared_cache_dir", None) is not None:
        outputs.append(args.shared_cache_dir.resolve())
    for snapshot in snapshots:
        if not isinstance(snapshot, Snapshot):
            continue
        for recipe in snapshot.recipes:
            path, suffix, _recursive = snapshot._recipe(recipe)
            resolved = path.resolve()
            if any(output == resolved or suffix is not None and output.is_relative_to(resolved) for output in outputs):
                raise ValueError("output overlaps a declared input scope: " + str(resolved))
        for row in snapshot.identity["files"]:
            resolved = (snapshot._requested_root / row["path"]).resolve()
            if any(output == resolved or resolved.is_relative_to(output) for output in outputs):
                raise ValueError("output overlaps a declared input file: " + str(resolved))
        for directory in snapshot.directory_membership:
            resolved = directory.resolve()
            if any(output == resolved or output.is_relative_to(resolved) or resolved.is_relative_to(output)
                   for output in outputs):
                raise ValueError("output overlaps a provider search directory: " + str(resolved))


def execute(args) -> int:
    env = verification.normalized_environment(ROOT)
    args.compiler = identity.executable(str(args.compiler), env)
    args.cache_dir = args.cache_dir.absolute()
    args.report = (args.report or args.cache_dir / "last-run.json").absolute()
    args.suite = args.suite.absolute()
    state = {"version": "juice-run-v1", "complete": False, "success": False,
             "actions": [], "admissions": [], "counts": {"executed": 0, "reused": 0, "admissions": 0}}
    initialized = False
    published = False
    try:
        shared = getattr(args, "shared_cache_dir", None)
        store = juice_evidence.EvidenceStore(shared or args.cache_dir / "evidence-v2")
        with ExitStack() as stack:
            stack.enter_context(store.lease())
            session = verification_snapshot.DigestSession()
            declaration = stack.enter_context(Snapshot(ROOT, [], [args.suite], digest_session=session))
            specs = suite(args.suite, args.target)
            preliminary = [plan(args, spec, env) for spec in specs]
            binaries = [args.compiler]
            tools = provider_tools(env)
            if tools is not None:
                binaries += [tools.readelf, tools.ldd, tools.loader, tools.ldconfig]
            for native in preliminary:
                binaries += [Path(native["build_config"]["compiler"]["path"]),
                             Path(native["measurement"]["collector"]["tool"]["path"])]
                binaries += [Path(value["path"]) for value in native["build_config"]["tools"].values()]
                binaries += tool_paths(args, native, env)
            recipes, files = identity.tools(env, sorted(set(binaries)), None)
            # A preload file appearing and disappearing must invalidate even an
            # initially empty loader contract. The unmatched suffix also guards
            # visible /etc membership; normal tool identity binds ld.so.cache.
            recipes.append("/etc/*.so.preload")
            common = stack.enter_context(Snapshot(ROOT, IMPLEMENTATION_INPUTS + recipes, files,
                                                  digest_session=session))
            host = verification.HostContext()
            targets = []
            scopes = []
            for spec, native in zip(specs, preliminary):
                recipes, files = target_inputs(spec, native, args.cache_dir, args.report)
                if args.collector != "perf" and env.get("VALGRIND_LIB"):
                    recipes.append(str(Path(env["VALGRIND_LIB"]).absolute()) + "/")
                search = None if tools is None else juice_provider.search_scopes(juice_provider.environment(native), env, tools)
                scopes.append(search)
                targets.append(stack.enter_context(Snapshot(ROOT, recipes, files, include_hidden=True,
                                                            directory_membership=search or [], digest_session=session)))
                if tools is not None and juice_provider.search_scopes(juice_provider.environment(native), env, tools) != search:
                    raise fuzz_campaign_store.InputsChanged("runtime provider search paths changed during planning")
            snapshots = [declaration, common, host, *targets]
            protect_outputs(args, snapshots)
            (args.cache_dir / "runs").mkdir(parents=True, exist_ok=True)
            save_report(args, state)
            initialized = True
            native_plans = [plan(args, spec, env) for spec in specs]
            if native_plans != preliminary:
                raise fuzz_campaign_store.InputsChanged("native inputs changed during planning")
            require_stable(snapshots)
            success = True
            for spec, native, target, search in zip(specs, native_plans, targets, scopes):
                bound = action_key(spec, native, common, target, host, env)
                if not run_target(store, spec, native, args, env, bound, snapshots, [common, target], state, tools, search, stack):
                    success = False
                    break
                save_report(args, state)
            require_stable(snapshots)
            state.update(complete=success, success=success, inputs_stable=True)
            state["snapshot_statistics"] = verification.snapshot_statistics(snapshots)
            state["evidence_store"] = {"shared": shared is not None, "root": str(store.backend.root)}
            save_report(args, state)
            require_stable(snapshots)
            published = True
        return 0 if success else 1
    except BaseException as error:
        state.update(complete=False, success=False)
        state["error"] = str(error) or type(error).__name__
        raise
    finally:
        if initialized and not published:
            save_report(args, state)
        print(json.dumps({"success": state["success"], "complete": state["complete"],
                          "counts": state["counts"], "report": str(args.report)}, sort_keys=True), flush=True)


def comparison_rows(path: Path) -> dict[str, dict]:
    value = document(path)
    if value.get("version") != "juice-run-v1" or value.get("complete") is not True or value.get("success") is not True:
        raise ValueError("comparison requires completed successful juice-run-v1 reports")
    result = {}
    actions = value.get("actions")
    if type(actions) is not list or not 1 <= len(actions) <= 256:
        raise ValueError("comparison requires 1..256 workload actions")
    for row in actions:
        if (type(row) is not dict or type(row.get("id")) is not str
                or re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,63}", row["id"]) is None
                or row["id"] in result or row.get("success") is not True):
            raise ValueError("invalid comparison workload set")
        result[row["id"]] = row
    if not result:
        raise ValueError("comparison has no workloads")
    return result


def compare(args) -> int:
    """Reevaluate thresholds against exact retained samples, without capture admission."""
    env = verification.normalized_environment(ROOT)
    if identity.unsupported(env):
        raise ValueError("comparison runtime has unsupported injection environment")
    compiler = identity.executable(str(args.compiler), env)
    declarations = [compiler, args.baseline.absolute(), args.candidate.absolute()]
    if args.model:
        declarations.append(args.model.absolute())
    # Check the coordinator destination before even reading report declarations.
    if (args.output / "decisions.json").resolve() in {path.resolve() for path in declarations}:
        raise ValueError("comparison output overlaps an input")
    recipes, tools = identity.tools(env, [compiler], None)
    state = {"version": "juice-decisions-v1", "complete": False, "success": False,
             "measurements_executed": 0, "admissions": 0, "decisions": [],
             "policy": {"mode": args.mode, "max_spread": args.max_spread,
                        "min_change": args.min_change, "fail_above": args.fail_above}}
    status = 0
    with ExitStack() as stack:
        session = verification_snapshot.DigestSession()
        runtime = stack.enter_context(Snapshot(ROOT, IMPLEMENTATION_INPUTS + recipes, declarations + tools,
                                               digest_session=session))
        inputs = [runtime]
        before, after = comparison_rows(args.baseline), comparison_rows(args.candidate)
        if before.keys() != after.keys():
            raise ValueError("comparison reports select different workloads")
        if "decisions" in before:
            raise ValueError("reserved comparison workload ID: decisions")
        originals, retained_rows = [], {}
        for name in sorted(before):
            retained_rows[name] = []
            for row in (before[name], after[name]):
                path = Path(row["record"])
                artifacts = {k: Path(v) for k, v in row["artifacts"].items()}
                retained = juice_evidence.validate_record(path, artifacts, row["expected"])
                if retained.record_digest != row["record_sha256"]:
                    raise ValueError("missing or changed retained evidence for " + name)
                originals += [path, *artifacts.values(), *(path.parent / file for file in retained.files)]
                retained_rows[name].append((row, retained))
        protected = declarations + tools + originals
        protected += [ROOT / path for path in IMPLEMENTATION_INPUTS]
        output = args.output.resolve()
        destinations = [args.output / "decisions.json"]
        destinations += [args.output / (name + suffix) for name in before for suffix in (".json", ".md")]
        # Every output is disjoint from source reports, model, runtime and retained
        # records. Raw evidence directories must also retain their exact inventory.
        for path in protected:
            resolved = path.resolve()
            if output == resolved or output in resolved.parents:
                raise ValueError("comparison output overlaps an input")
            for destination in destinations:
                if (destination.resolve() == resolved or
                        destination.exists() and path.exists() and os.path.samefile(destination, path)):
                    raise ValueError("comparison output overlaps an input")
        for entries in retained_rows.values():
            for row, _retained in entries:
                raw = Path(row["record"]).parent.resolve()
                if output == raw or raw in output.parents:
                    raise ValueError("comparison output overlaps retained evidence")
        inputs.append(stack.enter_context(Snapshot(ROOT, [], originals, digest_session=session)))
        state["inputs"] = runtime.identity
        state["runtime"] = {"environment_sha256": verification.key(env), "loaded_code": LOADED_CODE_SHA256}
        args.output.mkdir(parents=True, exist_ok=True)
        require_stable(inputs)
        verification.atomic_record(args.output / "decisions.json", state)
        try:
            for name in sorted(before):
                paths = []
                for row, retained in retained_rows[name]:
                    area = Path(tempfile.mkdtemp(prefix="input-", dir=args.output))
                    materialized = juice_evidence.materialize(retained, area / "retained")
                    watched = stack.enter_context(Snapshot(ROOT, [str(area / "retained") + "/"], include_hidden=True,
                                                           digest_session=session))
                    inputs.append(watched)
                    checked = juice_evidence.validate_record(materialized,
                        {kind: area / "retained/build" / kind for kind in retained.build_artifacts}, row["expected"])
                    if checked.record_digest != row["record_sha256"]:
                        raise ValueError("materialized comparison input changed")
                    paths.append(materialized)
                destination = args.output / (name + ".json")
                argv = [str(compiler), "juice", "compare", *map(str, paths), "--output", str(destination),
                        "--mode", args.mode, "--max-spread", str(args.max_spread), "--min-change", str(args.min_change)]
                if args.fail_above is not None:
                    argv += ["--fail-above", str(args.fail_above)]
                if args.model:
                    argv += ["--model", str(args.model)]
                require_stable(inputs)
                result = subprocess.run(argv, cwd=ROOT, env=env)
                require_stable(inputs)
                state["decisions"].append({"id": name, "status": result.returncode, "report": str(destination),
                                           "baseline": before[name]["record_sha256"], "candidate": after[name]["record_sha256"]})
                status = max(status, result.returncode if result.returncode >= 0 else 128 - result.returncode)
            require_stable(inputs)
            state.update(complete=status in (0, 1), success=status == 0)
            state["snapshot_statistics"] = verification.snapshot_statistics(inputs)
            return status
        finally:
            try:
                if state["complete"]:
                    require_stable(inputs)
                verification.atomic_record(args.output / "decisions.json", state)
                if state["complete"]:
                    require_stable(inputs)
            except BaseException:
                state.update(complete=False, success=False)
                verification.atomic_record(args.output / "decisions.json", state)
                raise


def options(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    capture = sub.add_parser("capture")
    capture.add_argument("suite", type=Path)
    capture.add_argument("--cache-dir", type=Path, default=ROOT / ".mylang-cache/juice-v1")
    capture.add_argument("--shared-cache-dir", type=Path, help="Explicit local shared immutable evidence; captures and reports stay private")
    capture.add_argument("--report", type=Path)
    capture.add_argument("--target", action="append", default=[])
    capture.add_argument("--fresh", action="store_true")
    capture.add_argument("--build-compiler")
    capture.add_argument("--collector", choices=("perf", "cachegrind", "callgrind"), default="perf")
    capture.add_argument("--profile", choices=("work", "runtime"), default="work")
    capture.add_argument("--cpu", type=int)
    capture.add_argument("--repeats", type=int, default=3)
    capture.add_argument("--perf", default="perf")
    capture.add_argument("--valgrind", default=os.environ.get("JUICE_VALGRIND", "valgrind"))
    capture.add_argument("--static", action="store_true")
    decision = sub.add_parser("compare")
    decision.add_argument("baseline", type=Path)
    decision.add_argument("candidate", type=Path)
    decision.add_argument("--output", type=Path, required=True)
    decision.add_argument("--mode", choices=("application", "backend", "combined"), default="combined")
    decision.add_argument("--max-spread", type=float, default=0.005)
    decision.add_argument("--min-change", type=float, default=0.001)
    decision.add_argument("--fail-above", type=float)
    decision.add_argument("--model", type=Path)
    for part in (capture, decision):
        part.add_argument("--compiler", type=Path, default=ROOT / "zig-out/bin/mylang")
    args = parser.parse_args(argv)
    if args.command == "capture" and (not 2 <= args.repeats <= 30 or args.cpu is not None and not 0 <= args.cpu <= 1023):
        parser.error("repeats must be 2..30 and CPU must be 0..1023")
    return args


def main(argv) -> int:
    args = options(argv)
    cancellation = 130
    def cancel(signum, _frame):
        nonlocal cancellation
        cancellation = 128 + signum
        raise KeyboardInterrupt
    previous = {signum: signal.signal(signum, cancel) for signum in (signal.SIGTERM, signal.SIGHUP)}
    try:
        return execute(args) if args.command == "capture" else compare(args)
    except fuzz_campaign_store.InputsChanged as error:
        print("juice-cache: inputs changed: " + str(error), file=sys.stderr)
        return 75
    except (OSError, ValueError, fuzz_campaign_store.FormatError, fuzz_campaign_store.DeterminismError,
            SnapshotError, verification.VerificationError, subprocess.TimeoutExpired) as error:
        print("juice-cache: cannot qualify evidence: " + str(error), file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("juice-cache: interrupted; incomplete captures cannot be reused", file=sys.stderr)
        return cancellation
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

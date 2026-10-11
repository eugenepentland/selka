#!/usr/bin/env python3
"""Run the complete verification inventory, reusing qualified successes before admission.

    python3 scripts/verify_cache.py --zig /path/to/pinned/zig
    python3 scripts/verify_cache.py --force -- -j3 --maxrss 8589934592

This developer entry point owns build/gate admission; do not wrap it in another
build-slot invocation. Normal `zig build test fmt-check` remains supported.
Receipts are local evidence, never a replacement for an unregistered gate action.
"""
from __future__ import annotations

import argparse
from contextlib import ExitStack
import fcntl
import hashlib
import json
import marshal
import os
from pathlib import Path
import platform
import re
import resource
import shutil
import signal
import socket
import subprocess
import sys
import sysconfig
import tempfile
import time

from verification_snapshot import Snapshot, SnapshotError
import verification_snapshot
import fuzz_campaign_store

ROOT = Path(__file__).resolve().parents[1]
VERSION = 1
RETRY = 75
MAX_RECORD = 32 * 1024 * 1024
CONFIG_INPUTS = ["./*.zig", "build.zig.zon", ".zigversion", "guardian.toml",
                 "src/user_docs.zig", "selfhost/*.zig", "../guardian-zig/build.zig",
                 "../guardian-zig/build.zig.zon", "../guardian-zig/src/"]
PREPARE_INPUTS = ["src/", "test/", "tests/", "selfhost/",
                  "docs/", "README.md", "SPEC.md", "benchmarks/runtime/ports/native_clock.c"]
COORDINATOR_INPUTS = ["scripts/verify_cache.py", "scripts/verification_snapshot.py",
                      "scripts/cache_session.py",
                      "scripts/verification_artifacts.py", "scripts/fuzz_campaign_store.py", "scripts/build-slot.sh"]
# These are the host tools used by the registered test adapters and admission.
# An adapter needing another external provider must declare it here or stay fresh.
HOST_TOOLS = ("python3", "sh", "bash", "env", "grep", "sort", "mktemp", "rm",
              "sleep", "git", "find", "dirname", "readlink", "realpath", "cp",
              "mv", "chmod", "uname", "ln", "head", "tail", "wc", "timeout",
              "taskset", "flock", "awk", "seq", "date", "cat", "touch", "sha256sum")
UNTRACKED_ENV = ("LD_PRELOAD", "LD_LIBRARY_PATH", "LD_AUDIT", "PYTHONPATH",
                 "PYTHONHOME", "ZIG_LIB_DIR", "CC", "CXX", "CPATH",
                 "C_INCLUDE_PATH", "CPLUS_INCLUDE_PATH", "LIBRARY_PATH")


class VerificationError(RuntimeError):
    """The requested verification cannot be certified."""


def encoded(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=True).encode()


def key(value: object) -> str:
    return hashlib.sha256(encoded(value)).hexdigest()


def read_record(path: Path) -> dict | None:
    try:
        with path.open("rb") as handle:
            data = handle.read(MAX_RECORD + 1)
        if len(data) > MAX_RECORD:
            return None
        result = json.loads(data, object_pairs_hook=unique_object)
        return result if isinstance(result, dict) else None
    except (OSError, ValueError, UnicodeError):
        return None


def unique_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for name, value in pairs:
        if name in result:
            raise ValueError("duplicate JSON member: " + name)
        result[name] = value
    return result


def atomic_record(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".receipt-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(encoded(value) + b"\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def valid_receipt(path: Path, action_key: str) -> bool:
    record = read_record(path)
    return (record is not None and type(record.get("version")) is int and
            record == {"version": VERSION, "kind": "verification-success", "key": action_key})


def save_receipt(path: Path, action_key: str) -> None:
    atomic_record(path, {"version": VERSION, "kind": "verification-success", "key": action_key})


def inventory(path: Path) -> dict:
    value = read_record(path)
    if (not value or type(value.get("version")) is not int or value["version"] != VERSION
            or value.get("required_targets") != ["test", "fmt-check"]):
        raise VerificationError("invalid or unsupported verification inventory")
    groups = value.get("groups")
    if not isinstance(groups, list) or not groups:
        raise VerificationError("verification inventory has no required actions")
    ids, targets = set(), set()
    for group in groups:
        required_fields = {"id", "target", "label", "inputs", "cacheable", "reason"}
        if (not isinstance(group, dict) or not required_fields <= group.keys()
                or group.keys() - required_fields - {"artifacts"}):
            raise VerificationError("invalid action contract")
        if (not all(isinstance(group[x], str) for x in ("id", "target", "label", "reason"))
                or not re.fullmatch(r"[a-zA-Z0-9_-]+", group["id"])
                or group["target"] != "verification-" + group["id"]
                or type(group["cacheable"]) is not bool
                or not isinstance(group["inputs"], list)
                or not all(isinstance(x, str) and x for x in group["inputs"])
                or group["id"] in ids or group["target"] in targets):
            raise VerificationError("invalid or duplicate action in inventory")
        providers = group.get("artifacts")
        if (providers is not None and (not isinstance(providers, list)
                or not all(isinstance(name, str) and name for name in providers)
                or len(set(providers)) != len(providers))):
            raise VerificationError("invalid artifact dependency selector")
        ids.add(group["id"])
        targets.add(group["target"])
    coverage = value.get("coverage", {})
    required, registered = coverage.get("required_actions"), coverage.get("registered_actions")
    unknown = coverage.get("unknown_actions")
    if (type(required) is not int or type(registered) is not int or required < 1
            or registered < 0 or not isinstance(unknown, list)
            or not all(isinstance(name, str) for name in unknown)
            or required != registered + len(unknown)
            or (unknown and "unclassified" not in ids)):
        raise VerificationError("inventory does not cover the original gate")
    if any(group["id"] == "unclassified" and group["cacheable"] for group in groups):
        raise VerificationError("unclassified actions must always execute the original gate")
    if any(group["id"] == "coverage" and group["cacheable"] for group in groups):
        raise VerificationError("fixture membership coverage must always execute")
    return value


def normalized_environment(root: Path) -> dict[str, str]:
    env = dict(os.environ)
    # Deliberately normalize these in the worker too, rather than omit live inputs.
    env.pop("_", None)
    env["SHLVL"] = "0"
    env["PWD"] = str(root)
    env["PYTHONNOUSERSITE"] = "1"
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    # -B alone still reads timestamp-based .pyc files. A non-directory prefix
    # makes workers load the hashed source even after same-size/mtime edits.
    env["PYTHONPYCACHEPREFIX"] = "/dev/null"
    # Non-interactive shells may otherwise read an arbitrary startup file, and
    # exported Bash functions can replace the host tools identified below.
    for name in list(env):
        if name in ("BASH_ENV", "ENV") or name.startswith("BASH_FUNC_"):
            del env[name]
    # Execute with the same existing PATH directories we can watch. A missing
    # earlier entry must not acquire a shadow executable while admission waits.
    env["PATH"] = os.pathsep.join(str(directory) for entry in env.get("PATH", os.defpath).split(os.pathsep)
                               if (directory := Path(os.path.abspath(root / entry))).is_dir())
    if not env["PATH"]:
        raise VerificationError("verification PATH has no existing directories")
    # Fixture git repositories must not inherit signing, hooks, includes,
    # external diff drivers, alternate object stores, or user templates.
    for name in list(env):
        if name.startswith("GIT_"):
            del env[name]
    env.update(GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_SYSTEM="/dev/null",
               GIT_CONFIG_NOSYSTEM="1", GIT_TEMPLATE_DIR="",
               GIT_AUTHOR_NAME="Selka verification", GIT_AUTHOR_EMAIL="verification@example.invalid",
               GIT_COMMITTER_NAME="Selka verification", GIT_COMMITTER_EMAIL="verification@example.invalid")
    return env


def host_contract() -> dict:
    """Stable native CPU and inherited process inputs, excluding live load/clock."""
    cpu_fields = {"vendor_id", "cpu family", "model", "model name", "stepping", "microcode", "flags"}
    cpu = sorted({line.strip() for line in Path("/proc/cpuinfo").read_text().splitlines()
                  if line.split(":", 1)[0].strip() in cpu_fields})
    limits = {name: resource.getrlimit(getattr(resource, name)) for name in dir(resource)
              if name.startswith("RLIMIT_")}
    mask = os.umask(0)
    os.umask(mask)
    return {"system": platform.uname()._asdict(), "cpu": cpu, "limits": limits,
            "umask": mask, "affinity": sorted(os.sched_getaffinity(0))}


class HostContext:
    """Revalidate inherited process settings alongside watched file inputs."""

    def __init__(self):
        self.identity = host_contract()

    def unchanged(self):
        return host_contract() == self.identity


def shared_libraries(paths: list[Path], env: dict[str, str]) -> list[Path]:
    """Resolve the actual ELF loader/library contents, not package versions."""
    libraries = set()
    for path in paths:
        with path.open("rb") as handle:
            if handle.read(4) != b"\x7fELF":
                continue
        result = subprocess.run(["ldd", str(path)], env=env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if "not found" in result.stdout:
            raise VerificationError("unresolved host library for " + str(path))
        if result.returncode and not any(x in result.stdout for x in ("not a dynamic executable", "statically linked")):
            raise VerificationError("cannot identify host libraries for " + str(path))
        for line in result.stdout.splitlines():
            for token in line.split():
                if token.startswith("/"):
                    libraries.add(Path(token))
    return sorted(libraries)


def tool_contract(zig: Path, env: dict[str, str]) -> tuple[list[str], list[Path]]:
    tools = {zig, Path(sys.executable)}
    for name in (*HOST_TOOLS, "ldd"):
        found = shutil.which(name, path=env.get("PATH"))
        if not found:
            raise VerificationError("required verification tool is absent: " + name)
        tools.add(Path(found))
    stdlib = Path(sysconfig.get_path("stdlib"))
    recipes = [str(zig.resolve().parent / "lib") + "/", str(stdlib / "*.py")]
    for child in sorted(stdlib.iterdir()):
        if child.is_dir() and child.name not in ("site-packages", "dist-packages", "__pycache__") and not child.name.startswith("."):
            recipes.append(str(child) + "/")
    # Directory membership watches catch a tool appearing earlier on PATH while
    # a request waits. Resolution is performed again for every new invocation.
    for directory in env.get("PATH", "").split(os.pathsep):
        if not directory or not Path(directory).is_dir():
            raise VerificationError("verification PATH directory disappeared: " + directory)
        recipes.append(str(Path(directory).absolute()) + "/*.verification-tool-membership")
    extensions = list((stdlib / "lib-dynload").glob("*.so"))
    libraries = shared_libraries(sorted(tools) + extensions, env)
    for path in ("/etc/ld.so.cache", "/etc/ld.so.conf", "/etc/os-release"):
        if Path(path).is_file():
            tools.add(Path(path))
    return recipes, sorted(tools | set(libraries))


def admitted_child(fd: int) -> int:
    """Handshake after FIFO admission; execute only after the parent revalidates."""
    with socket.socket(fileno=fd) as channel:
        channel.sendall(b"admitted\n")
        chunks = []
        while data := channel.recv(65536):
            chunks.append(data)
        if not chunks:
            return RETRY
        request = json.loads(b"".join(chunks))
    os.chdir(request["cwd"])
    os.execve(request["argv"][0], request["argv"], request["env"])
    return 2


def run_admitted(root: Path, kind: str, argv: list[str], env: dict[str, str], unchanged,
                 timings: list[dict] | None = None) -> tuple[int, float]:
    """Hold the normal slot only for selected work, checking again after queueing."""
    parent, child = socket.socketpair()
    # build-slot reserves descriptors 7/8/9. Keep this handshake out of its range.
    fd = fcntl.fcntl(child.fileno(), fcntl.F_DUPFD_CLOEXEC, 32)
    child.close()
    command = [str(root / "scripts/build-slot.sh"), kind, sys.executable,
               str(Path(__file__).resolve()), "--admitted", str(fd)]
    submitted_at = time.monotonic()
    process = subprocess.Popen(command, cwd=root, env=env, pass_fds=(fd,), start_new_session=True)
    os.close(fd)
    admitted_at = None
    validation_seconds = 0.0
    worker_at = None
    try:
        parent.settimeout(1)
        greeting = b""
        while b"\n" not in greeting:
            try:
                data = parent.recv(256)
                if not data:
                    break
                greeting += data
            except TimeoutError:
                if process.poll() is not None:
                    break
        if greeting == b"admitted\n":
            admitted_at = time.monotonic()
            valid = unchanged()
            validation_seconds = time.monotonic() - admitted_at
            if valid:
                parent.sendall(encoded({"argv": argv, "env": env, "cwd": str(root)}))
                worker_at = time.monotonic()
            parent.shutdown(socket.SHUT_WR)
        parent.close()
        status = process.wait()
        ended_at = time.monotonic()
        held = 0.0 if admitted_at is None else ended_at - admitted_at
        if timings is not None:
            timings.append({"kind": kind, "status": status, "admitted": admitted_at is not None,
                            "admission_wait_seconds": (admitted_at or ended_at) - submitted_at,
                            "validation_seconds": validation_seconds,
                            "worker_seconds": 0.0 if worker_at is None else ended_at - worker_at,
                            "observed_held_seconds": held, "elapsed_seconds": ended_at - submitted_at})
        return status, held
    except BaseException:
        parent.close()
        try:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        except ProcessLookupError:
            pass
        raise


def artifact_paths(root: Path) -> list[Path]:
    record = read_record(root / "zig-out/verification/artifacts.json")
    if not record or record.get("version") != 1 or not isinstance(record.get("artifacts"), dict):
        raise VerificationError("missing or malformed prepared artifact inventory")
    artifacts = record["artifacts"]
    if not {"mylang", "units", "cli", "core"} <= artifacts.keys():
        raise VerificationError("prepared inventory omits native test executables")
    if not all(isinstance(p, str) and Path(p).is_absolute() for p in artifacts.values()):
        raise VerificationError("prepared artifacts must have exact absolute paths")
    paths = [Path(p) for p in artifacts.values()]
    paths.extend([root / "zig-out/bin/mylang", root / "zig-out/verification/artifacts.json"])
    for name in ("test-index", "cache-plan"):
        path = root / "zig-out/libexec/mylang/components" / (name + ".json")
        manifest = read_record(path)
        if not manifest or not isinstance(manifest.get("artifact"), str) or Path(manifest["artifact"]).name != manifest["artifact"]:
            raise VerificationError("invalid component manifest: " + name)
        paths.extend([path, path.parent / manifest["artifact"]])
    return sorted(set(paths))


def artifact_providers(root: Path, snapshot: Snapshot) -> dict[str, list[dict]]:
    """Project only declared providers; retain the complete snapshot for ABA checks."""
    record = read_record(root / "zig-out/verification/artifacts.json")
    if not record or not isinstance(record.get("artifacts"), dict):
        raise VerificationError("prepared artifact inventory changed during provider selection")
    paths = {name: [Path(path)] for name, path in record["artifacts"].items()}
    paths["mylang"].append(root / "zig-out/bin/mylang")
    paths["components"] = []
    for name in ("test-index", "cache-plan"):
        manifest_path = root / "zig-out/libexec/mylang/components" / (name + ".json")
        manifest = read_record(manifest_path)
        if not manifest or not isinstance(manifest.get("artifact"), str):
            raise VerificationError("component manifest changed during provider selection")
        paths["components"].extend([manifest_path, manifest_path.parent / manifest["artifact"]])
    files = {os.path.abspath(root / item["path"]): item for item in snapshot.identity["files"]}
    providers = {}
    for name, members in paths.items():
        try:
            providers[name] = [files[path] for path in sorted({os.path.abspath(path) for path in members})]
        except KeyError as error:
            raise VerificationError("artifact provider is outside the prepared snapshot: " + name) from error
    return providers


def matches_recipe(path: str, recipe: str, root: Path) -> bool:
    """Select a cohort's members from the single watched, hashed union."""
    normalized = os.path.normpath(os.path.join(root, path))
    value = os.path.normpath(os.path.join(root, recipe))
    if recipe.endswith("/"):
        return normalized.startswith(value + os.sep)
    for marker, recursive in (("/**/*", True), ("/*", False)):
        if marker in recipe:
            base, suffix = recipe.split(marker, 1)
            prefix = os.path.normpath(os.path.join(root, base)) + os.sep
            if not normalized.startswith(prefix) or not normalized.endswith(suffix):
                return False
            return recursive or os.sep not in normalized[len(prefix):]
    return normalized == value


def action_identity(group: dict, snapshot: Snapshot, common: dict, root: Path,
                    providers: dict[str, list[dict]] | None = None) -> str:
    files = [item for item in snapshot.identity["files"]
             if any(matches_recipe(item["path"], recipe, root) for recipe in group["inputs"])]
    selected = group.get("artifacts")
    if selected is not None:
        if providers is None or any(name not in providers for name in selected):
            raise VerificationError("action names an unavailable artifact provider: " + group["id"])
        common = dict(common, artifacts={name: providers[name] for name in selected})
    return key({"domain": "selka-verification-action-v2", "contract": group, "common": common, "files": files})


def check_all(snapshots: list[Snapshot]) -> bool:
    return all(snapshot.unchanged() for snapshot in snapshots)


def snapshot_statistics(snapshots) -> dict[str, int]:
    """Sum observed filesystem work, counting each live snapshot only once."""
    result, seen = {}, set()
    for snapshot in snapshots:
        if id(snapshot) in seen:
            continue
        seen.add(id(snapshot))
        for name, value in getattr(snapshot, "statistics", {}).items():
            result[name] = result.get(name, 0) + value
    return result


def publish_checked(path: Path, value: dict, snapshots: list[Snapshot]) -> None:
    published = False
    try:
        atomic_record(path, value)
        if not check_all(snapshots):
            raise VerificationError("inputs changed while publishing preparation evidence")
        published = True
    finally:
        if not published:
            path.unlink(missing_ok=True)


def zig_command(zig: Path, targets: list[str], options: list[str], rerun: bool = False) -> list[str]:
    options = [arg for arg in options if not (rerun and arg.startswith("-Dtest-rerun="))]
    args = [str(zig), "build", *targets, *options]
    if rerun and "-Dtest-rerun=true" not in args:
        args.append("-Dtest-rerun=true")
    if not any(arg.startswith("--seed=") for arg in args):
        args.append("--seed=0")
    return args


def prepare(root: Path, cache: Path, zig: Path, options: list[str], env: dict[str, str],
            common: dict, snapshots: list[Snapshot], stack: ExitStack,
            timings: list[dict] | None = None, phases: dict | None = None,
            digest_session=None) -> tuple[dict, Snapshot, float]:
    config = stack.enter_context(Snapshot(root, CONFIG_INPUTS + COORDINATOR_INPUTS, digest_session=digest_session))
    snapshots.append(config)
    common["build_configuration"] = key(config.identity)
    config_key = key({"common": common, "configuration": config.identity})
    plan_path = root / "zig-out/verification/inventory.json"
    plan_receipt = cache / "inventory.json"
    saved = read_record(plan_receipt)
    plan = None
    if saved and saved.get("key") == config_key:
        try:
            plan = inventory(plan_path)
            if saved.get("inventory") != key(plan):
                plan = None
        except VerificationError:
            pass
    held = 0.0
    if plan is None:
        status, seconds = run_admitted(root, "build", zig_command(zig, ["verification-plan"], options),
                                       env, lambda: check_all(snapshots), timings=timings)
        held += seconds
        if status or not check_all(snapshots):
            raise VerificationError("inventory preparation failed or its inputs changed (exit %d)" % status)
        plan = inventory(plan_path)
        publish_checked(plan_receipt, {"key": config_key, "inventory": key(plan)}, snapshots)
    source_started = time.monotonic()
    sources = stack.enter_context(Snapshot(root, PREPARE_INPUTS, digest_session=digest_session))
    if phases is not None:
        phases["source_snapshot_seconds"] = time.monotonic() - source_started
    snapshots.append(sources)
    preparation_key = key({"configuration": config_key, "sources": sources.identity})
    saved = read_record(cache / "preparation.json")
    artifacts = None
    if saved and saved.get("key") == preparation_key:
        try:
            candidate = stack.enter_context(Snapshot(root, [], artifact_paths(root), digest_session=digest_session))
            if saved.get("artifacts") == candidate.identity:
                artifacts = candidate
            else:
                candidate.close()
        except (SnapshotError, VerificationError):
            pass
    if artifacts is None:
        status, seconds = run_admitted(root, "build", zig_command(zig, ["verification-prepare"], options),
                                       env, lambda: check_all(snapshots), timings=timings)
        held += seconds
        if status or not check_all(snapshots):
            raise VerificationError("artifact preparation failed or its inputs changed (exit %d)" % status)
        artifacts = stack.enter_context(Snapshot(root, [], artifact_paths(root), digest_session=digest_session))
        publish_checked(cache / "preparation.json", {"key": preparation_key, "artifacts": artifacts.identity},
                        snapshots + [artifacts])
    snapshots.append(artifacts)
    return plan, artifacts, held


def execute(root: Path, cache: Path, zig: Path, options: list[str], force: bool = False,
            shared_cache_dir: Path | None = None) -> int:
    started = time.monotonic()
    admissions, phases = [], {}
    (root / "zig-out/verification").mkdir(parents=True, exist_ok=True)
    env = normalized_environment(root)
    env["ZIG"] = str(zig)
    env["MYLANG_ZIG"] = str(zig)
    tool_recipes, tool_files = tool_contract(zig, env)
    with ExitStack() as stack:
        shared = None if shared_cache_dir is None else fuzz_campaign_store.Store(shared_cache_dir)
        if shared is not None:
            stack.enter_context(shared.lease())
            coordinator = key({"domain": "verification-coordinator-v1", "root": str(root)})
            stack.enter_context(shared.coordinator_lock(coordinator))
        session = verification_snapshot.DigestSession()
        tools = stack.enter_context(Snapshot(root, tool_recipes, tool_files, digest_session=session))
        if tool_contract(zig, env) != (tool_recipes, tool_files) or not tools.unchanged():
            raise VerificationError("tool resolution changed while installing input watches")
        host = HostContext()
        snapshots = [tools, host]
        common = {"version": VERSION, "root": str(root), "options": options,
                  "environment": key(env), "platform": host.identity,
                  "tools": key(tools.identity),
                  "implementation": [LOADED_CODE_SHA256, verification_snapshot.LOADED_CODE_SHA256,
                                     fuzz_campaign_store.LOADED_CODE_SHA256]}
        plan, artifacts, build_seconds = prepare(root, cache, zig, options, env, common, snapshots, stack, admissions, phases, session)
        common["artifacts"] = key(artifacts.identity)
        common["inventory"] = key(plan)
        providers = artifact_providers(root, artifacts)
        groups = plan["groups"]
        recipes = sorted({entry for group in groups for entry in group["inputs"]})
        input_started = time.monotonic()
        inputs = stack.enter_context(Snapshot(root, recipes, digest_session=session))
        phases["action_input_snapshot_seconds"] = time.monotonic() - input_started
        snapshots.append(inputs)
        unsupported = [name for name in UNTRACKED_ENV if env.get(name)]
        force = force or "-Dtest-rerun=true" in options or bool(plan.get("configuration", {}).get("filtered"))
        if force:
            # A failed explicit rerun must not leave an older success available.
            # This is a local evidence store; deleting evidence only causes work.
            for path in (cache / "actions").glob("*.json"):
                path.unlink(missing_ok=True)
        results, selected, keys = [], [], {}
        for group in groups:
            action_key = action_identity(group, inputs, common, root, providers)
            keys[group["id"]] = action_key
            reusable = group["cacheable"] and not force and not unsupported
            expected_receipt = {"version": VERSION, "kind": "verification-success", "key": action_key}
            saved = shared.load_success(action_key) if reusable and shared is not None else None
            hit = reusable and (saved == expected_receipt if shared is not None else
                                valid_receipt(cache / "actions" / (action_key + ".json"), action_key))
            state = "reused" if hit else "execute" if reusable else "fresh"
            reason = "valid prior success" if hit else "no valid receipt" if reusable else group["reason"]
            if unsupported:
                reason = "untracked environment override: " + ", ".join(unsupported)
            elif force:
                reason = "explicit rerun or filtered request"
            results.append({"id": group["id"], "state": state, "reason": reason})
            print("verification: %s %s (%s)" % (state, group["id"], reason), flush=True)
            if not hit:
                if shared is not None:
                    shared.invalidate_success(action_key)
                selected.append(group)
        if not check_all(snapshots):
            raise VerificationError("inputs changed during cache lookup; rerun verification")
        phases["prepare_lookup_outside_admission_seconds"] = (time.monotonic() - started
                                                              - sum(event["elapsed_seconds"] for event in admissions))
        status, gate_seconds = 0, 0.0
        if selected:
            # Force chosen Run steps: an outer miss (tool/environment/ABA) must not
            # be accidentally satisfied by a weaker, older inner Zig verdict.
            targets = (plan["required_targets"] if len(selected) == len(groups)
                       else [group["target"] for group in selected])
            status, gate_seconds = run_admitted(root, "gate",
                zig_command(zig, targets, options, rerun=True),
                env, lambda: check_all(snapshots), timings=admissions)
        validation_started = time.monotonic()
        stable = check_all(snapshots)
        phases["final_validation_seconds"] = time.monotonic() - validation_started
        if status == 0 and not stable:
            status = RETRY
        publication_started = time.monotonic()
        if status == 0:
            published = []
            publication_valid = False
            try:
                for group in selected:
                    if group["cacheable"] and not unsupported and not plan.get("configuration", {}).get("filtered"):
                        action_key = keys[group["id"]]
                        path = cache / "actions" / (action_key + ".json")
                        published.append(path)
                        save_receipt(path, action_key)
                        if shared is not None:
                            value = {"version": VERSION, "kind": "verification-success", "key": action_key}
                            try:
                                if not shared.publish_success(action_key, value, [], lambda: check_all(snapshots)):
                                    raise VerificationError("shared verification success publication rejected")
                            except fuzz_campaign_store.InputsChanged:
                                status = RETRY
                                break
                if not check_all(snapshots):
                    status = RETRY
                publication_valid = status == 0
            finally:
                if not publication_valid:
                    for path in published:
                        path.unlink(missing_ok=True)
                        if shared is not None:
                            shared.invalidate_success(path.stem)
        phases["publication_seconds"] = time.monotonic() - publication_started
        report = {"version": VERSION, "success": status == 0, "status": status,
                  "actions": results, "inputs_stable": stable,
                  "build_admitted_seconds": build_seconds, "gate_admitted_seconds": gate_seconds,
                  "admissions": admissions, "timings": phases,
                  "snapshot_statistics": snapshot_statistics(snapshots),
                  "evidence_store": {"shared": shared is not None,
                                     "root": str(shared.root if shared is not None else cache / "actions")},
                  "elapsed_seconds": time.monotonic() - started}
        atomic_record(cache / "last-run.json", report)
        print("verification: %s; %d reused, %d selected; build admitted %.3fs, gate admitted %.3fs" %
              ("PASS" if status == 0 else "FAIL", len(groups) - len(selected), len(selected), build_seconds, gate_seconds), flush=True)
        if status == RETRY:
            print("verification: inputs changed while queued or running; no new success receipts retained", file=sys.stderr)
        return status if status >= 0 else 128 - status


def parse_options(options: list[str]) -> list[str]:
    """Only full-gate build controls; no target, prefix, cache-root or runner overrides."""
    if options[:1] == ["--"]:
        options = options[1:]
    allowed_values = {"--maxrss", "--summary"}
    index = 0
    while index < len(options):
        arg = options[index]
        if arg in allowed_values:
            index += 1
            if index >= len(options) or options[index].startswith("-"):
                raise VerificationError("missing value for " + arg)
        elif not (re.fullmatch(r"-j[1-9][0-9]*", arg)
                  or re.fullmatch(r"--seed=(0x[0-9a-fA-F]+|[0-9]+)", arg) or re.fullmatch(
                r"-D(optimize|test-shards|core-shards|test-rerun|test-filter)=[^\x00]+", arg)):
            raise VerificationError("unsupported verification build option: " + arg)
        index += 1
    if not any(x.startswith("-j") for x in options):
        options += ["-j3"]
    if "--maxrss" not in options:
        options += ["--maxrss", "8589934592"]
    if "--summary" not in options:
        options += ["--summary", "all"]
    if not any(arg.startswith("--seed=") for arg in options):
        options += ["--seed=0"]
    return options


def main(argv: list[str]) -> int:
    if argv[:1] == ["--admitted"]:
        return admitted_child(int(argv[1]))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zig", default=os.environ.get("MYLANG_ZIG") or os.environ.get("ZIG") or "zig")
    parser.add_argument("--force", action="store_true", help="execute every required action, retaining fresh successful evidence")
    parser.add_argument("--shared-cache-dir", type=Path, help="Explicit local shared success evidence; inventory and runs stay private")
    parser.add_argument("options", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    cancellation = 130
    def cancel(signum, _frame):
        nonlocal cancellation
        cancellation = 128 + signum
        raise KeyboardInterrupt
    previous = {signum: signal.signal(signum, cancel) for signum in (signal.SIGTERM, signal.SIGHUP)}
    try:
        resolved = shutil.which(args.zig)
        if resolved is None:
            raise VerificationError("cannot find Zig: " + args.zig)
        cache = ROOT / ".mylang-cache/verification-v1"
        cache.mkdir(parents=True, exist_ok=True)
        # Serialize coordinators for this checkout, outside the shared server
        # slots, so preparation and forced invalidation cannot race one another.
        with (cache / "coordinator.lock").open("a") as lock:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
            return execute(ROOT, cache, Path(resolved).absolute(), parse_options(args.options), args.force, args.shared_cache_dir)
    except (VerificationError, SnapshotError, OSError, ValueError,
            fuzz_campaign_store.FormatError, fuzz_campaign_store.DeterminismError) as error:
        print("verification: FAIL: " + str(error), file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("verification: cancelled; no new success receipts", file=sys.stderr)
        return cancellation
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)


# Bind evidence to the code actually loaded, even if the files change before
# filesystem watches are installed. Next invocation's new code has another key.
LOADED_CODE_SHA256 = hashlib.sha256(marshal.dumps(sys._getframe().f_code)).hexdigest()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

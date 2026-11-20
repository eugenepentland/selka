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
from contextlib import ExitStack, contextmanager
import fcntl
import hashlib
import json
import verification_code_identity as code_identity
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
import threading
import time
from typing import Mapping

from verification_snapshot import Snapshot, SnapshotError
import verification_snapshot
import fuzz_campaign_store
import gate_cheap_checks
import gate_summary
import verification_report
import verification_budgets
import verification_profiles
import verification_warm
import verification_git_tree
import verification_qualification
import verification_process
import verification_producers
import verification_environment
import verification_telemetry
import verification_measurement
import worktree_cache_trim
from verification_process import BoundedProcessLogs, ProcessLimits, terminate_owned, wait_owned

ROOT = Path(__file__).resolve().parents[1]
# Receipt schema 3: path-free, projected-environment identities. The directory
# carries the same number, so schema-2 receipts are never opened, let alone misread.
VERSION = 3
DEFAULT_BUILD_TIMEOUT_SECONDS = 20 * 60
DEFAULT_GATE_TIMEOUT_SECONDS = 90 * 60
CACHE_DIRECTORY = Path(".selka-cache/verification-v3")
ACTION_DOMAIN = "selka-verification-action-v6"
# Shared success evidence at the per-user default location (D2: same user, same
# machine). Enabled after R4 default-store qualification. A named variable or
# --shared-cache-dir selects a store explicitly; an empty value disables sharing.
DEFAULT_SHARING = True
SHARED_CACHE_VARIABLE = "SELKA_VERIFICATION_SHARED_CACHE"
REPORT_VERSION = 1
INVENTORY_VERSION = 2
# The declarative list file. `build_test_inputs.zig` is data only (see
# `declared_input_lists`), and an action's configuration identity omits its
# bytes while every use of those lists in the build configuration is one of the
# reviewed consumer sites below: each feeds a list into action registration
# (the inventory's groups and exported `input_lists`), the per-list input
# manifests, or producer recipes (`artifacts.json`), all of which reach the
# action keys by themselves, so an edit to one list re-keys only the actions
# that declare it. A site is one logical line (a statement joined across its
# wrapped lines, comments dropped, whitespace collapsed) of a configuration Zig
# file that names the file or an identifier bound to its import. An added,
# removed or edited site keeps the file in every action's identity until it is
# reviewed here; `DeclarativeConsumers` in verify_cache_test.py fails until
# then, and every report states whether the exclusion applied.
# This replaces DECLARATIVE_CONFIG_SHA256, a digest of the whole configuration
# closure (qualified by coordinator + delegated consumer review, evidence:
# experiments/telemetry-cache-invalidation-20261012/REPORT.md), which went
# stale with the next build-file edit and silently stopped applying (F12).
# None keeps every action conservatively broad.
DECLARATIVE_INPUTS = "build_test_inputs.zig"
DECLARATIVE_CONSUMERS: tuple[tuple[str, str], ...] | None = (
    ("build.zig", 'const test_inputs = @import("build_test_inputs.zig");'),
    ("build.zig", "inline for (comptime std.meta.declarations(test_inputs)) |name| {"),
    ("build.zig", "run.addArgs(&@field(test_inputs, name));"),
    ("build.zig", 'verification_registry.?.register("component-preparation", &component_discovery.step, '
                  '&test_inputs.component_inputs, false, "validated preparation discovery v1");'),
    ("build.zig", 'verification_registry.?.register("component-preparation", &component_build.step, '
                  '&test_inputs.component_inputs, false, "validated preparation discovery v1");'),
    ("build.zig", 'verification_registry.?.register("component-preparation", &component_install.step, '
                  '&test_inputs.component_inputs, false, "validated preparation discovery v1");'),
    ("build.zig", 'verification_registry.?.register("component-support", &run_component_support.step, '
                  '&test_inputs.component_builder, true, "exact native support executable and declared inputs");'),
    ("build.zig", 'verification_registry.?.register("juice", &juice_native_run.step, &test_inputs.juice, false, '
                  '"native performance collectors and host state require fresh execution");'),
    ("build.zig", 'verification_registry.?.register("juice-runtime", &juice_runtime_run.step, &test_inputs.juice_runtime, '
                  'false, "runtime collectors observe CPU, scheduler and current host state");'),
    ("build.zig", 'verification_registry.?.register("coverage", &coverage_run.step, &test_inputs.coverage, true, '
                  '"declared sources and guarded named-path existence");'),
    ("build.zig", 'verification_registry.?.register("doc-coverage", &doc_coverage.step, &test_inputs.doc_coverage, true, '
                  '"complete document and feature-contract scope");'),
    ("build.zig", 'verification_registry.?.register("language", &debug.step, &test_inputs.language, true, '
                  '"compiler, source closure, unsupported policy and projected environment");'),
    ("build.zig", 'verification_registry.?.register("language", &release.step, &test_inputs.language, true, '
                  '"compiler, source closure, unsupported policy and projected environment");'),
    ("build.zig", 'verification_registry.?.register("ownership-proof", &proof_run.step, &test_inputs.ownership_proof, true, '
                  '"compiler, source closure, the Lean model and toolchain, and the certificates the language gate writes");'),
    ("build.zig", 'verification_registry.?.register("verify-ir-proof", &verify_ir_run.step, &test_inputs.verify_ir_proof, true, '
                  '"compiler, source closure, the Lean copy of the IR verifier and toolchain, the IR the language gate writes, and the C '
                  'interop fixtures");'),
    ("build.zig", 'verification_registry.?.register("arith-proof", &arith_run.step, &test_inputs.arith_proof, true, '
                  '"the Lean arithmetic proofs, their rendered templates and toolchain");'),
    ("build.zig", 'verification_registry.?.register("cache-proof", &cache_proof_run.step, &test_inputs.cache_proof, true, '
                  '"compiler, the cache-plan component, the Lean model of the build cache and toolchain");'),
    ("build.zig", 'const fmt = b.addFmt(.{ .paths = &.{ b.path("build.zig"), b.path("build_env.zig"), '
                  'b.path("build_identity.zig"), b.path("build_test_inputs.zig"), b.path("build_verification.zig"), '
                  'b.path("src"), b.path("tests"), b.path("test"), b.path("selfhost") }, .check = true });'),
    ("build.zig", 'verification_registry.?.register("zig-format", &fmt.step, &test_inputs.zig_format, true, '
                  '"exact formatter and complete source-format scope");'),
    ("build_verification.zig", 'const test_inputs = @import("build_test_inputs.zig");'),
    ("build_verification.zig", "inline for (comptime std.meta.declarations(test_inputs)) |name| {"),
    ("build_verification.zig", 'self.register(name, step, &@field(test_inputs, name), true, "complete declared whole-action inputs");'),
    ("build_verification.zig", 'if (std.mem.eql(u8, label, "tooling-units")) return compiled(b, &test_inputs.tooling_unit);'),
    ("build_verification.zig", 'if (std.mem.eql(u8, label, "text-scalar-units")) return compiled(b, &test_inputs.text_scalar_unit);'),
    ("build_verification.zig", "if (listed(entry, &test_inputs.environment_contract)) continue;"),
    ("build_verification.zig", 'const inputs: []const []const u8 = if (std.mem.eql(u8, artifact.label, "tooling-units")) '
                               '&test_inputs.tooling_unit else &test_inputs.text_scalar_unit;'),
    ("build_verification.zig", "inline for (comptime std.meta.declarations(test_inputs)) |name| {"),
    ("build_verification.zig", 'lists.append(a, .{ .name = name, .inputs = &@field(test_inputs, name) }) catch @panic("verification allocation");'),
)
RETRY = 75
# `--integration` (plan D3, D-NIGHTLY-1 in experiments/audit-work-20261111/NIGHTLY.md): the request's status names the step
# that failed. A determinism mismatch logged by the request's own stores is 5; a failing complete request keeps its own status
# (1 a failing test or step, 2 a host or usage error, 6 the stage-store guard, 75 retry, ...); the forced fact/leak run is 7;
# the two-run test step (`zig build test-lang-rerun`, lane FX10) is 8. The per-user stores' logs are a record, never a verdict.
INTEGRATION_MISMATCH_STATUS = 5
INTEGRATION_FORCED_STATUS = 7
INTEGRATION_RERUN_STATUS = 8
# D-NIGHTLY-2: an integration request runs every build against empty compiler and test stores of its own, made under
# `<cache>/integration/stores-*` (`own_stores`), so a mismatch they log was made by this request alone.
OWN_STORE_LEAVES = (("SELKA_COMPILER_SHARED_CACHE", "compiler"), ("SELKA_TEST_SHARED_CACHE", "tests"))
MISMATCH_LINES_KEPT = 20
# GATE3 (the user's decision of 14 November, measured 15 November): an ordinary request runs every build against an empty
# compiler store and an empty test store of its own (`gate-stores`, made for the request and removed when it passes), so what
# it reads and writes is what this request stored, never another worktree's, and a determinism mismatch a store logs is this
# request's alone. A caller that names a store keeps the one it names (`--own-stores off` names none). A build of the request
# that opens one of the user's own default stores anyway holds a shared lease on its `.retention.lock` file, which the request
# samples (`StoreLeaseWatch`); one found fails a green request with the stage store's status. A mismatch the own stores log
# fails it with the integration gate's status.
OWN_STORES_MODES = ("fresh", "off")
GATE_STORES_DIRECTORY = "gate-stores"
LEASE_FILE = ".retention.lock"
LEASE_SAMPLE_SECONDS = 0.25
LEASE_OFFENDERS_KEPT = 20
# The native shared stores whose `<namespace>/mismatches.log` the integration
# check reads; only stores this request's environment selects are "used".
NATIVE_SHARED_VARIABLES = ("SELKA_COMPILER_SHARED_CACHE", "SELKA_TEST_SHARED_CACHE")
# The stage store's shared half is on by default (`~/.cache/selka/stage-artifacts`), and that store belongs to the user's own
# builds. Every worker of a request gets this variable empty unless the caller named a store (`normalized_environment`), and a
# request whose own processes wrote the default store fails with its own status (`stage_store_guard`): a test reached it. A store
# change with no root of this checkout is another process's and only noted: every ordinary build writes the store now.
STAGE_VARIABLE = "SELKA_STAGE_SHARED_CACHE"
STAGE_STORE_STATUS = 6
LIVE_ROOT_MAGIC = b"selka-stage-live-v1\n"
FACT_LEAK_MEMBER = re.compile(r"selka test (\S+) --verify-facts \(leak check\)")
SHARD_PLAN_OPTIONS = {"-Dunit-shard-plan", "-Dcli-shard-plan", "-Dcore-shard-plan"}
MAX_RECORD = 32 * 1024 * 1024
# The build runner's own compile closure: every file `build.zig` imports,
# transitively (`BuildToolIdentity` in verify_cache_test.py names any file
# missing here). `build_env.zig`'s `build-env` host tool wraps every cached test
# step (`withTools`) and `build_identity.zig` keys the compiler build; the build
# graph registers their compile steps as prepared infrastructure, not as
# actions, so their `src/` imports are bound here, in every action's
# `build_configuration`, beside `src/environment_identity.zon` below.
CONFIG_INPUTS = ["tests/shard-plans/core.json", "tests/shard-plans/unit.json", "tests/shard-plans/cli.json",
                 "./*.zig", "build.zig.zon", ".zigversion",
                 "src/user_docs.zig", "src/environment_identity.zig", "src/build_env_rules.zig",
                 "src/build_identity_rules.zig", "src/semantic_cache_format.zig", "src/product.zig",
                 "selfhost/*.zig"]
# `tools/test_runner/` is the test runner every custom test root links (`runner_sources` in
# build_verification.zig): each such artifact's producer recipe names it, and a recipe that
# selects no watched input fails the request in preparation.
PREPARE_INPUTS = ["src/", "test/", "tests/", "selfhost/", "tools/test_runner/",
                  "docs/", "README.md", "SPEC.md", "benchmarks/runtime/ports/native_clock.c"]
COORDINATOR_INPUTS = ["scripts/verification_watch_pool.py", "scripts/verification_git_tree.py", "scripts/verification_warm.py", "scripts/verification_qualification.py", "scripts/verification_code_identity.py", "scripts/verify_cache.py", "scripts/verification_profiles.py", "scripts/verification_snapshot.py",
                      "scripts/verification_process.py",
                      "scripts/cache_session.py",
                      "scripts/verification_artifacts.py", "scripts/verification_producers.py",
                      "scripts/verification_environment.py", "src/environment_identity.zon",
                      "scripts/verification_telemetry.py", "scripts/build_admission.py",
                      "scripts/verification_measurement.py",
                      "scripts/build_slot_legacy.sh", "scripts/verification/__init__.py",
                      "scripts/verification/scheduler.py",
                      "scripts/fuzz_campaign_store.py", "scripts/build-slot.sh"]
# These are the host tools used by the registered test adapters and admission.
# An adapter needing another external provider must declare it here or stay fresh.
HOST_TOOLS = ("python3", "sh", "bash", "env", "grep", "sort", "mktemp", "rm",
              "sleep", "git", "find", "dirname", "readlink", "realpath", "cp",
              "mv", "chmod", "uname", "ln", "head", "tail", "wc", "timeout",
              "taskset", "setsid", "flock", "awk", "seq", "date", "cat", "touch", "sha256sum",
              "du")
UNTRACKED_ENV = ("LD_PRELOAD", "LD_LIBRARY_PATH", "LD_AUDIT", "PYTHONPATH",
                 "PYTHONHOME", "ZIG_LIB_DIR", "CC", "CXX", "CPATH",
                 "C_INCLUDE_PATH", "CPLUS_INCLUDE_PATH", "LIBRARY_PATH")


class VerificationError(RuntimeError):
    """The requested verification cannot be certified."""

    def __init__(self, message, status=2):
        super().__init__(message)
        self.status = status


class InputsChanged(VerificationError):
    """Inputs changed before any gate action started (during preparation, the cache lookup or the queue for the gate):
    `execute_with_restarts` takes a new snapshot and starts the request again (item 4c)."""

    def __init__(self, message: str):
        super().__init__(message, RETRY)


class CheapChecksFailed(VerificationError):
    """A cheap check (`gate_cheap_checks.py`) has a finding: the gate ends before any test action, with status 1."""

    def __init__(self, message: str):
        super().__init__(message, 1)


def prepared_compiler(root: Path) -> Path | None:
    """The compiler the prepared gate steps run (`artifacts.json`, either record version), when it is there."""
    record = read_record(root / "zig-out/verification/artifacts.json") or {}
    entry = (record.get("artifacts") or {}).get("selka")
    path = entry.get("path") if isinstance(entry, dict) else entry
    return Path(path) if isinstance(path, str) and Path(path).is_file() else None


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


def diagnostic_record(path: Path, value: dict) -> None:
    """Diagnostic storage must not mask execution status or authorize a success."""
    try:
        atomic_record(path, value)
    except (OSError, ValueError, TypeError):
        print("verification: diagnostic report unavailable: " + str(path), file=sys.stderr)


def valid_receipt(path: Path, action_key: str) -> bool:
    record = read_record(path)
    expected = {"version": VERSION, "kind": "verification-success", "key": action_key}
    if record is None or type(record.get("version")) is not int:
        return False
    if record == expected:
        return True
    commit = record.get("commit_blob")
    if (not isinstance(commit, str) or re.fullmatch(r"[0-9a-f]{64}", commit) is None
            or record != dict(expected, commit_blob=commit)):
        return False
    marker = read_record(path.parent.parent / "commits" / (commit + ".json"))
    return marker is not None and key(marker) == commit


def prior_success(shared, cache: Path, action_key: str) -> bool:
    """Whether a valid success for exactly this action key exists.

    With a shared evidence store open, only its validated success counts (an
    invalidation marker or a conflict is a miss); without one, the local receipt.
    """
    if shared is not None:
        return shared.load_success(action_key) == {"version": VERSION, "kind": "verification-success", "key": action_key}
    return valid_receipt(cache / "actions" / (action_key + ".json"), action_key)


def save_receipt(path: Path, action_key: str, commit_blob: str | None = None) -> None:
    value = {"version": VERSION, "kind": "verification-success", "key": action_key}
    if commit_blob is not None:
        value["commit_blob"] = commit_blob
    atomic_record(path, value)


def inventory(path: Path) -> dict:
    value = read_record(path)
    if (not value or type(value.get("version")) is not int or value["version"] != INVENTORY_VERSION
            or value.get("required_targets") != ["test", "fmt-check"]):
        raise VerificationError("invalid or unsupported verification inventory")
    if set(value) != {"version", "required_targets", "groups", "input_lists", "configuration", "coverage", "action_metadata"}:
        raise VerificationError("unsupported inventory fields")
    controls = value.get("configuration")
    if (not isinstance(controls, dict) or set(controls) != {"filtered", "rerun", "optimize", "proofs"}
            or type(controls["filtered"]) is not bool or type(controls["rerun"]) is not bool
            or type(controls["proofs"]) is not bool
            or not isinstance(controls["optimize"], str) or not controls["optimize"]):
        raise VerificationError("invalid inventory configuration")
    if not controls["proofs"]:
        # `-Dproofs` off makes the four Lean proof actions steps that print "skipped" and exit 0 (GH-D10): a receipt for one
        # would claim a proof ran. `zig_command` always passes the flag, so this is a build graph that ignored it.
        raise VerificationError("the verification inventory was exported without -Dproofs=true: its Lean proof actions would be "
                                "skipped, and a skipped proof is not a pass")
    lists = value.get("input_lists")
    if not isinstance(lists, list):
        raise VerificationError("invalid inventory input lists")
    list_names = set()
    for item in lists:
        if (not isinstance(item, dict) or set(item) != {"name", "inputs"}
                or not isinstance(item.get("name"), str) or not item["name"]
                or item["name"] in list_names or not isinstance(item.get("inputs"), list)
                or not all(isinstance(recipe, str) and recipe for recipe in item["inputs"])):
            raise VerificationError("invalid or duplicate inventory input list")
        list_names.add(item["name"])
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
    if not isinstance(coverage, dict):
        raise VerificationError("invalid inventory coverage")
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
    coverage_contract = {"tests/test_inputs_coverage.py", "build_test_inputs.zig", "src/**/*.zig", "test/**/*.zig"}
    if any(group["id"] == "coverage" and group["cacheable"]
           and not coverage_contract <= set(group["inputs"]) for group in groups):
        raise VerificationError("fixture membership coverage must always execute")
    metadata = value.get("action_metadata")
    if not isinstance(metadata, list) or len(metadata) != len(groups):
        raise VerificationError("inventory action metadata is incomplete")
    seen_ids, labels, members = set(), set(), 0
    for action in metadata:
        if (not isinstance(action, dict) or set(action) != {"id", "steps", "identity_scope"}
                or not isinstance(action.get("id"), str) or action["id"] not in ids or action["id"] in seen_ids
                or action.get("identity_scope") != "group-local-v1"
                or not isinstance(action.get("steps"), list)
                or (not action["steps"] and action["id"] != "unclassified")):
            raise VerificationError("invalid action metadata")
        seen_ids.add(action["id"])
        for step in action["steps"]:
            if (not isinstance(step, dict) or set(step) != {"label", "original_label", "kind"}
                    or not all(isinstance(step.get(field), str) and step[field] for field in step)
                    or not re.fullmatch(r"verification action " + re.escape(action["id"]) + r" member [0-9]+", step["label"])
                    or step["label"] in labels):
                raise VerificationError("invalid or ambiguous action member")
            labels.add(step["label"])
            members += 1
    if members != registered:
        raise VerificationError("inventory member coverage disagrees with original gate")
    return value


def declared_input_lists(path: Path) -> dict | None:
    """Recognize only data-only Zig arrays/references; unknown syntax stays broad."""
    try:
        with path.open("rb") as source:
            raw = source.read(MAX_RECORD + 1)
        if len(raw) > MAX_RECORD:
            return None
        text = raw.decode("utf-8")
        scanner = re.compile(r'\s+|//[^\n]*|"(?:[^"\\]|\\.)*"|\+\+|[A-Za-z_][A-Za-z_0-9]*|[][{}=;,]')
        tokens, end = [], 0
        for match in scanner.finditer(text):
            if match.start() != end:
                return None
            end = match.end()
            token = match.group()
            if not token.isspace() and not token.startswith('//'):
                tokens.append(token)
        if end != len(text):
            return None
        result, index = {}, 0
        while index < len(tokens):
            if tokens[index:index + 2] != ['pub', 'const'] or index + 4 > len(tokens):
                return None
            name = tokens[index + 2]
            if not re.fullmatch('[A-Za-z_][A-Za-z_0-9]*', name) or name in result or tokens[index + 3] != '=':
                return None
            index += 4
            recipes = []
            while True:
                if tokens[index:index + 8] == ['[', '_', ']', '[', ']', 'const', 'u8', '{']:
                    index += 8
                    while tokens[index] != '}':
                        recipes.append(json.loads(tokens[index]))
                        index += 1
                        if tokens[index] == ',':
                            index += 1
                        elif tokens[index] != '}':
                            return None
                    index += 1
                elif tokens[index] in result:
                    recipes.extend(result[tokens[index]])
                    index += 1
                else:
                    return None
                if tokens[index] != '++':
                    break
                index += 1
            if tokens[index] != ';' or not all(isinstance(recipe, str) and recipe for recipe in recipes):
                return None
            index += 1
            result[name] = recipes
        return result
    except (OSError, ValueError, IndexError, TypeError):
        return None


_ZIG_TOKEN = re.compile(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'|//.*|[^"\'/]+|.')


def zig_logical_lines(text: str) -> list[str]:
    """Statements of a Zig file joined across wrapped lines, comments dropped and
    whitespace collapsed; a logical line ends where its (), [] nesting closes."""
    lines, pending, depth = [], [], 0
    for line in text.splitlines():
        kept, code = [], []
        if line.lstrip().startswith("\\\\"):
            kept = [line]  # A multiline string line: no comments, no nesting.
        else:
            for token in _ZIG_TOKEN.findall(line):
                if token.startswith("//"):
                    break
                kept.append(token)
                if token[0] not in "\"'":
                    code.append(token)
        text_line = " ".join("".join(kept).split())
        if not text_line:
            continue
        pending.append(text_line)
        code_text = "".join(code)
        depth += sum(map(code_text.count, "([")) - sum(map(code_text.count, ")]"))
        if depth <= 0:
            lines.append(" ".join(pending))
            pending, depth = [], 0
    if pending:
        lines.append(" ".join(pending))
    return lines


def declarative_consumers(root: Path, configuration_identity: dict) -> list[tuple[str, str]] | None:
    """Every logical line of a configuration Zig file that names the declarative
    list file or an identifier bound to its import, in snapshot order; None when
    a file's bytes are no longer the watched ones."""
    found = []
    for item in configuration_identity.get("files", []):
        path = item["path"]
        if not path.endswith(".zig") or path == DECLARATIVE_INPUTS:
            continue
        try:
            raw = (root / path).read_bytes()
        except OSError:
            return None
        if hashlib.sha256(raw).hexdigest() != item.get("sha256"):
            return None
        if DECLARATIVE_INPUTS.encode() not in raw:
            continue
        lines = zig_logical_lines(raw.decode("utf-8", "replace"))
        names = set()
        for line in lines:
            names.update(re.findall(r'\bconst\s+([A-Za-z_]\w*)\s*(?::[^=]*)?=\s*@import\("(?:[^"]*/)?'
                                    + re.escape(DECLARATIVE_INPUTS) + r'"\)', line))
        pattern = re.compile("|".join([re.escape(DECLARATIVE_INPUTS)] + [r"\b%s\b" % name for name in sorted(names)]))
        found.extend((path, line) for line in lines if pattern.search(line))
    return found


def declarative_exclusion(identity: dict, plan: dict, root: Path, configuration_identity: dict | None) -> str | None:
    """Why the declarative list file must stay in the action configuration, or
    None when every consumer is reviewed and its lists are the exported ones."""
    if DECLARATIVE_CONSUMERS is None or configuration_identity is None:
        return "no reviewed consumer sites"
    consumers = declarative_consumers(root, configuration_identity)
    if consumers is None:
        return "configuration changed while its consumers were read"
    if sorted(consumers) != sorted(DECLARATIVE_CONSUMERS):
        return "unreviewed consumer sites of %s" % DECLARATIVE_INPUTS
    lists = declared_input_lists(root / DECLARATIVE_INPUTS)
    exported = plan.get("input_lists")
    if lists is None:
        return "%s is not data-only" % DECLARATIVE_INPUTS
    if not isinstance(exported, list):
        return "the inventory exports no input lists"
    try:
        expected = {entry["name"]: entry["inputs"] for entry in exported}
        if len(expected) != len(exported) or expected != lists:
            return "the inventory's input lists differ from %s" % DECLARATIVE_INPUTS
    except (KeyError, TypeError):
        return "the inventory's input lists are malformed"
    if not any(item["path"] == DECLARATIVE_INPUTS and "resolved" not in item for item in identity.get("files", [])):
        return "%s is absent or a symbolic link" % DECLARATIVE_INPUTS
    return None


def action_configuration(identity: dict, plan: dict, root: Path, configuration_identity: dict | None = None,
                         notes: dict | None = None) -> dict:
    """Exclude a proven declarative list file; retain all unfamiliar semantics.

    `notes["declarative_configuration"]` records "excluded" or why not."""
    reason = declarative_exclusion(identity, plan, root, configuration_identity)
    if notes is not None:
        notes["declarative_configuration"] = reason or "excluded"
    if reason is not None:
        return identity
    # All snapshots still watch this file; only action reuse omits its data bytes.
    return dict(identity, files=[item for item in identity["files"] if item["path"] != DECLARATIVE_INPUTS])


def normalized_environment(root: Path, source: Mapping[str, str] | None = None) -> dict[str, str]:
    """The environment every worker runs in: the projected launcher plus fixed settings.

    The live environment (or `source`) is projected through the environment
    identity contract, so workers receive only keyed, host and placement
    variables; a dropped one (PWD, TERM, CODEX_*, GIT_*, BASH_FUNC_*, ...) can
    neither reach a test nor enter a key. The coordinator then applies its own
    constant settings, which the coordinator's implementation identity covers.
    Workers take their working directory from the process, never from PWD.
    """
    env = verification_environment.project(os.environ if source is None else source)
    # Diagnostic placement must not enter native test receipt settings. Scrub
    # legacy callers too; only the private per-request channel is forwarded.
    env.pop("SELKA_TEST_TELEMETRY_DIR", None)
    env.pop("SELKA_VERIFICATION_TELEMETRY_DIR", None)
    # The process-local measurement capability controls admission. Transport
    # markers are installed only on admitted children, never trusted as proof.
    for marker in ("SELKA_ADMISSION_DIR", "SELKA_ADMISSION_KIND"):
        env.pop(marker, None)
    # A test that starts a compiler must not write into the user's own stage store: an unset variable would select it.
    env.setdefault(STAGE_VARIABLE, "")
    env["PYTHONNOUSERSITE"] = "1"
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    # -B alone still reads timestamp-based .pyc files. A non-directory prefix
    # makes workers load the hashed source even after same-size/mtime edits.
    env["PYTHONPYCACHEPREFIX"] = "/dev/null"
    # Execute with the same existing PATH directories we can watch. A missing
    # earlier entry must not acquire a shadow executable while admission waits.
    env["PATH"] = os.pathsep.join(str(directory) for entry in env.get("PATH", os.defpath).split(os.pathsep)
                               if (directory := Path(os.path.abspath(root / entry))).is_dir())
    if not env["PATH"]:
        raise VerificationError("verification PATH has no existing directories")
    # Fixture git repositories must not inherit signing, hooks, includes,
    # external diff drivers, alternate object stores, or user templates. The
    # projection removed every inherited GIT_* variable; these are constants.
    env.update(GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_SYSTEM="/dev/null",
               GIT_CONFIG_NOSYSTEM="1", GIT_TEMPLATE_DIR="",
               GIT_AUTHOR_NAME="Selka verification", GIT_AUTHOR_EMAIL="verification@example.invalid",
               GIT_COMMITTER_NAME="Selka verification", GIT_COMMITTER_EMAIL="verification@example.invalid")
    return env


def identity_variables(env: Mapping[str, str]) -> list[str]:
    """Sorted names of the keyed and host variables the host-scope digest takes."""
    return sorted(name for name in env if verification_environment.host_keyed(name))


def environment_identity(env: Mapping[str, str], tools: Snapshot | None, tool_files: list[Path], root: Path,
                         logical: dict | None = None) -> str:
    """Host-scope digest of the worker environment and the content of each resolved tool.

    Tools are named by their snapshot label (absolute for host tools, relative
    for anything inside the checkout) and identified by the digest the tools
    snapshot already computed; nothing is hashed twice.
    """
    if logical is not None:
        return verification_environment.digest(env, {"declared-closure": key(logical)}, scope="host")
    wanted = {os.path.abspath(path) for path in tool_files}
    digests = {} if tools is None else {
        item["path"]: item["sha256"] for item in tools.identity["files"]
        if os.path.abspath(root / item["path"]) in wanted}
    return verification_environment.digest(env, digests, scope="host")


def logical_tools(root: Path, zig: Path, env: dict, tools: Snapshot, tool_files: list[Path]) -> tuple[dict, dict]:
    """Declare logical roles without weakening the original snapshot authority.

    The exact extra files come from tool_contract's executable/loader closure;
    directory roles cover only its pinned Zig and Python library scopes.
    Unknown paths keep the conservative identity instead of being stripped.
    """
    labels = {}
    for path in tool_files:
        roles = {"native-input/" + path.name}
        for alias in (path.absolute(), path.resolve()):
            labels.setdefault(alias, set()).update(roles)
    commands = {"zig": zig, "python-runtime": Path(sys.executable)}
    for name in (*HOST_TOOLS, "ldd"):
        found = shutil.which(name, path=env.get("PATH"))
        if found is not None:
            commands[name] = Path(found)
    for name, path in commands.items():
        for alias in (path.absolute(), path.resolve()):
            if alias in labels:
                labels[alias].add("command/" + name)
    # Some Python installations expose their runtime through a stdlib symlink
    # into LIBDIR; declare only the configured library names, never that whole
    # system directory. Snapshot already watches and hashes the resolved target.
    python_libdir = sysconfig.get_config_var("LIBDIR")
    for variable in ("LDLIBRARY", "INSTSONAME"):
        library = sysconfig.get_config_var(variable)
        if python_libdir and library:
            path = Path(python_libdir) / library
            for alias in (path.absolute(), path.resolve()):
                labels.setdefault(alias, set()).add("python/runtime-library")
    customization = Path(sysconfig.get_path("stdlib")) / "sitecustomize.py"
    for alias in (customization.absolute(), customization.resolve()):
        labels.setdefault(alias, set()).add("python/sitecustomize")
    libraries = {zig.resolve().parent / "lib": "zig/lib",
                 Path(sysconfig.get_path("stdlib")): "python/stdlib"}
    try:
        document = verification_producers.logical_tool_identity(tools.identity, root, labels, libraries)
    except verification_producers.ProducerError:
        return tools.identity, dict(env)
    projected = dict(env)
    for name in ("ZIG", "SELKA_ZIG"):
        value = projected.get(name)
        if value and Path(value).resolve() == zig.resolve():
            projected[name] = "command/zig"
    if projected.get("PYTHONPYCACHEPREFIX") == "/dev/null":
        projected["PYTHONPYCACHEPREFIX"] = "fixed/non-directory-pycache-prefix"
    return document, projected


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
        self.changed_facets = []
        self.verification_role = "host"

    def unchanged(self):
        current = host_contract()
        self.changed_facets = sorted(set(self.changed_facets) | {
            name for name in self.identity.keys() | current.keys()
            if self.identity.get(name) != current.get(name)})
        return not self.changed_facets

    def stability_diagnostics(self, role="host"):
        return {"version": 1, "status": "observed" if self.changed_facets else "unknown",
                "reasons": [{"role": role, "facet": "host", "name": name,
                             "reason": "host contract changed"} for name in self.changed_facets[:64]],
                "unknown": not bool(self.changed_facets), "truncated": len(self.changed_facets) > 64}


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


def admitted_build_command(argv: list[str]) -> list[str]:
    """Bound Zig's root concurrency after admission narrows CPU affinity."""
    if len(argv) < 2 or argv[1] != "build":
        return argv
    # Pinned Zig counts async workers in -j, excluding its eager main thread.
    # On one CPU its omitted default is zero workers; -j0 is not valid syntax.
    workers = max(0, len(os.sched_getaffinity(0)) - 1)
    if workers == 0:
        return [arg for arg in argv if not re.fullmatch(r"-j[1-9][0-9]*", arg)]
    bounded = [f"-j{min(int(arg[2:]), workers)}" if re.fullmatch(r"-j[1-9][0-9]*", arg)
               else arg for arg in argv]
    if not any(re.fullmatch(r"-j[1-9][0-9]*", arg) for arg in argv):
        bounded.append(f"-j{workers}")
    return bounded


def admitted_child(fd: int) -> int:
    """Keep admission through the parent's authoritative publication handshake."""
    expected_pid = int(os.environ.get("SELKA_ADMISSION_PARENT_PID", os.getppid()))
    expected_start = int(os.environ.get("SELKA_ADMISSION_PARENT_START",
                                       verification_process._process_starttime(expected_pid) or 0))
    if not verification_process.arm_parent_death(expected_pid, expected_start):
        return 130
    with socket.socket(fileno=fd) as channel, channel.makefile("rb") as incoming:
        channel.sendall(b"admitted\n")
        message = incoming.readline(MAX_RECORD + 1)
        if not message or len(message) > MAX_RECORD:
            return RETRY
        request = json.loads(message)
        os.chdir(request["cwd"])
        status = verification_process.run_supervised(admitted_build_command(request["argv"]), request["env"])
        if not request.get("finalize"):
            return status
        try:
            channel.sendall(encoded({"completed": status}) + b"\n")
            # EOF/parent death cannot certify completion or release early as success.
            message = incoming.readline(128)
        except (BrokenPipeError, ConnectionResetError):
            # The coordinator ended this build (`--fail-fast`) or is gone: no completion can be certified.
            return status or RETRY
        if not message:
            return RETRY
        acknowledgement = json.loads(message)
        return status or acknowledgement["status"]


def mark_action_started(error: BaseException, kind: str, worker_started: bool) -> None:
    """Say on an input watch's `SnapshotError` whether a gate action had started: only a gate command that was sent is
    one. A preparation or inventory build is not an action, so a trip while it runs restarts the request (item 4c)."""
    if isinstance(error, SnapshotError):
        error.verification_action_started = kind == "gate" and worker_started


def run_admitted(root: Path, kind: str, argv: list[str], env: dict[str, str], unchanged,
                 timings: list[dict] | None = None, *, limits: ProcessLimits | None = None,
                 log_dir: Path | None = None, revise=None, finalize=None,
                 heartbeat=None, verbose: bool = True, stop=None) -> tuple[int, float]:
    """Hold the normal slot only for selected work, checking again after queueing.

    `revise`, when given, runs once admission is granted and the inputs are
    revalidated; it returns the command to run instead of `argv`, or None when
    no work remains (evidence published while queueing covers it), which
    releases the slot with status 0 and runs nothing.
    `finalize(status, authority)` publishes while the child still holds its slot.
    The authority includes child liveness and the original execution deadline.
    `heartbeat` drains original event authority while queueing and executing;
    it never replaces full admission or publication validation.
    `stop` is a `verification_process.FailFast`: once it reports a failed step the build is ended like a timeout, with no
    completion message and so no publication, and `stop.killed` says it was this that ended it.
    """
    measurement = verification_measurement.current()
    if measurement is not None:
        env = verification_measurement.worker_environment(env)
    parent, child = socket.socketpair()
    # build-slot reserves descriptors 7/8/9. Keep this handshake out of its range.
    fd = fcntl.fcntl(child.fileno(), fcntl.F_DUPFD_CLOEXEC, 32)
    child.close()
    command = [str(root / "scripts/build-slot.sh"), kind, sys.executable,
               str(Path(__file__).resolve()), "--admitted", str(fd)]
    if measurement is not None:
        # Our timing holder already drained all cooperating jobs. Keep the same
        # supervised command protocol, source revalidation and cleanup.
        command = command[2:]
    limits = limits or ProcessLimits()
    logs = None
    if log_dir is not None:
        try:
            log_dir.mkdir(parents=True, exist_ok=True)
            logs = BoundedProcessLogs(log_dir / "stdout.log", log_dir / "stderr.log",
                stdout_tee=getattr(sys.stdout, "buffer", None) if verbose else None,
                stderr_tee=getattr(sys.stderr, "buffer", None) if verbose else None)
        except OSError:
            pass  # Diagnostic storage never authorizes or prevents verification.
    submitted_at = time.monotonic()
    try:
        wrapper_environment = dict(env, SELKA_ADMISSION_PARENT_PID=str(os.getpid()),
                                   SELKA_ADMISSION_PARENT_START=str(verification_process._process_starttime(os.getpid())))
        process = subprocess.Popen(command, cwd=root, env=wrapper_environment, pass_fds=(fd,), start_new_session=True,
                                   stdout=subprocess.PIPE if logs else None,
                                   stderr=subprocess.PIPE if logs else None)
    except BaseException:
        parent.close()
        raise
    finally:
        os.close(fd)
    admitted_at = None
    validation_seconds = 0.0
    worker_at = None
    withdrawn = False
    finalized = False
    try:
        if logs is not None:
            logs.start(process)
        parent.settimeout(.05)
        greeting = b""
        while b"\n" not in greeting:
            if heartbeat is not None:
                heartbeat()
            if stop is not None and stop():
                break  # wait_owned below ends the queued wrapper and reports `stopped`
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
            if valid and revise is not None:
                argv = revise()
                withdrawn = argv is None
            if valid and not withdrawn:
                parent.sendall(encoded({"argv": argv, "env": env, "cwd": str(root),
                                        "finalize": finalize is not None}) + b"\n")
                worker_at = time.monotonic()
            if worker_at is not None and finalize is not None:
                def authority():
                    return (process.poll() is None and (limits.timeout_seconds is None
                            or time.monotonic() - worker_at < limits.timeout_seconds))
                completion = b""
                parent.settimeout(.05)
                while authority() and b"\n" not in completion:
                    if heartbeat is not None:
                        heartbeat()
                    if stop is not None and stop():
                        break
                    try:
                        data = parent.recv(128)
                        if not data:
                            break
                        completion += data
                    except TimeoutError:
                        pass
                if completion.endswith(b"\n") and authority():
                    status = json.loads(completion)["completed"]
                    status = finalize(status, authority)
                    finalized = True
                    if authority():
                        parent.sendall(encoded({"status": status}) + b"\n")
            parent.shutdown(socket.SHUT_WR)
        parent.close()
        outcome = wait_owned(process, limits=limits if worker_at is not None else ProcessLimits(),
                             execution_started=worker_at, logs=logs, heartbeat=heartbeat,
                             stop=stop if worker_at is not None or (stop is not None and stop()) else None)
        if stop is not None and outcome.stopped:
            stop.killed = True
        # A withdrawn request sent the admitted child nothing to run; its
        # empty-handshake exit status describes no work.
        status = 0 if withdrawn else outcome.returncode
        if status == 0 and finalize is not None and not withdrawn and not finalized:
            status = RETRY
        ended_at = time.monotonic()
        held = 0.0 if admitted_at is None else ended_at - admitted_at
        if timings is not None:
            timings.append({"kind": kind, "status": status, "admitted": admitted_at is not None,
                            "admission_scope": "request-timing-window" if measurement else "command",
                            "admission_wait_seconds": (admitted_at or ended_at) - submitted_at,
                            "validation_seconds": validation_seconds,
                            "worker_seconds": 0.0 if worker_at is None else ended_at - worker_at,
                            "observed_held_seconds": held, "elapsed_seconds": ended_at - submitted_at,
                            "withdrawn": withdrawn, "worker_started": worker_at is not None,
                            "timed_out": outcome.timed_out, "cancelled": outcome.cancelled,
                            "incomplete": outcome.incomplete, "stopped": outcome.stopped,
                            "execution_limits": limits.execution_identity(),
                            "logs": [] if logs is None else [
                                {"path": str(path), "truncated": logs.truncated[index],
                                 "bytes_seen": logs.bytes_seen[index],
                                 "capture_complete": logs.capture_complete,
                                 "capture_available": logs.capture_available[index],
                                 "observed_steps": verification_report.execution_timings(
                                     path, capture_available=logs.capture_available[index])}
                                for index, path in enumerate(logs.paths)],
                            "log_errors": [] if logs is None else logs.capture_errors})
        return status, held
    except BaseException as error:
        mark_action_started(error, kind, worker_at is not None)
        parent.close()
        terminate_owned(process)
        if logs is not None:
            logs.close()
        raise
    finally:
        for stream in (process.stdout, process.stderr):
            if stream is not None:
                stream.close()


def run_proof_profile(root: Path, cache: Path, artifacts: dict | None, env: dict[str, str], unchanged,
                      admissions: list, limits: ProcessLimits, verbose: bool = False) -> int:
    """The second half of the `proofs` profile (docs/tooling/ownership-certificates.md): once the complete gate has passed,
    run the `ownership-proof` driver again, under the gate's admission, over the certificates that gate wrote, with the Lean
    checker's size cap lifted. The gate action keeps its capped verdict as evidence; this run keeps its verdicts in the same
    store, so a later `complete` request compares them too. Returns the driver's status (0, 1 for a disagreement, 2 for a
    tool that cannot run)."""
    try:
        compiler = Path(artifacts["artifacts"]["selka"]["path"])
    except (KeyError, TypeError):
        raise VerificationError("the proofs profile needs the compiler artifact the gate built (zig-out/verification/artifacts.json)") from None
    if not compiler.is_file():
        raise VerificationError("the proofs profile cannot find the compiler the gate built: " + str(compiler))
    argv = [sys.executable, "scripts/ownership_proof.py", "--compiler", str(compiler), "--certificates", ".selka-cache/ownership-certificates",
            "--lean-cap-bytes", "0"]
    step_environment = dict(env)
    step_environment.setdefault("HOME", os.environ.get("HOME", ""))
    log_dir = cache / "last-logs/proofs"
    status, _ = run_admitted(root, "gate", argv, step_environment, unchanged, timings=admissions, limits=limits,
                             log_dir=log_dir, verbose=verbose)
    lines = []
    for name in ("stdout.log", "stderr.log"):
        try:
            lines += (log_dir / name).read_text(errors="replace").splitlines()
        except OSError:
            pass  # Diagnostic storage never decides the verdict.
    summary = [line for line in lines if line.startswith("ownership-proof: lake build ok")]
    problems = [line for line in lines if "DISAGREEMENT" in line or line.startswith("ownership-proof:") and "lake build ok" not in line and ": known:" not in line]
    if not verbose:
        print("verification: proofs: " + (summary[-1] if summary else "the ownership-proof driver printed no summary"), flush=True)
        if status != 0:
            for line in problems[:10]:
                print("verification: proofs: " + line[:400], flush=True)
    return status


def run_keyed_request(path: Path) -> int:
    """Own snapshots and admission in a detached, cacheable-subset coordinator."""
    request = read_record(path)
    if not request or request.get("version") != 1:
        raise VerificationError("invalid keyed verification request")
    root, cache = Path(request["root"]), Path(request["cache"])
    shared_path = Path(request["shared"])
    wanted = request["action_keys"]
    def cancelled(_signum, _frame):
        raise KeyboardInterrupt
    previous = {sig: signal.signal(sig, cancelled) for sig in (signal.SIGTERM, signal.SIGHUP)}
    try:
        status = execute(root, cache, Path(request["zig"]), request["options"], False, shared_path,
                         build_timeout=request["build_timeout"], gate_timeout=request["gate_timeout"],
                         _action_keys=wanted)
        report = read_record(cache / "last-run.json") or {}
        shared = fuzz_campaign_store.Store(shared_path)
        # Partial coverage is expected: this worker only owes the named subset.
        if (status in (0, 3) and report.get("selected_success") is True
                and report.get("inputs_stable") is True
                and all(prior_success(shared, cache, action_key) for action_key in wanted)):
            evidence = {"actions": [{name: row[name] for name in ("id", "action_key", "state")}
                                    for row in report["actions"] if row["action_key"] in wanted],
                        "admissions": report["admissions"], "timings": report["timings"]}
            print("verification-keyed-result:" + json.dumps(evidence, sort_keys=True), flush=True)
            return 0
        return status if status not in (0, 3) else RETRY
    except (SnapshotError, fuzz_campaign_store.InputsChanged):
        return RETRY
    except VerificationError as error:
        print("verification: keyed request failed: " + str(error), file=sys.stderr)
        return error.status
    except KeyboardInterrupt:
        return 130
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def subscription_diagnostics(cache: Path, bundle: str, result: dict) -> dict:
    """Keep nested output in failure reports as well as bounded sidecar logs."""
    diagnostics = {}
    for name in ("stdout", "stderr"):
        output = result.get(name, "").encode("utf-8", errors="replace")
        path = cache / "last-logs" / "subscriptions" / bundle / (name + ".log")
        record = {"bytes_seen": len(output), "tail": output[-16384:].decode("utf-8", errors="replace"),
                  "tail_truncated": len(output) > 16384, "path": str(path),
                  "capture_available": False, "truncated": len(output) > 8 * 1024 * 1024}
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(output[:8 * 1024 * 1024])
            record["capture_available"] = True
        except OSError as error:
            record["capture_error"] = str(error)
        diagnostics[name] = record
    return diagnostics


def subscribe_gate(request: dict, environment: dict) -> dict:
    """Subscribe without admission; the detached command owns its live snapshots."""
    bundle = key({"domain": "verification-keyed-bundle-v1", "actions": sorted(request["action_keys"]),
                  "store": str(Path(request["shared"]).resolve())})
    path = Path(request["cache"]) / "keyed-requests" / (bundle + ".json")
    # Keep the request after subscriber cancellation: the detached worker may
    # still need it for peers. The per-worktree disposable cache owns retention.
    atomic_record(path, request)
    started = time.monotonic()
    result = verification_measurement.build_admission.subscribe(bundle,
        [sys.executable, str(Path(__file__).resolve()), "--keyed-request", str(path)],
        cwd=Path(request["root"]), env=environment, kind=None)
    evidence = None
    for line in result.get("stdout", "").splitlines():
        if line.startswith("verification-keyed-result:"):
            try:
                evidence = json.loads(line.partition(":")[2])
            except ValueError:
                pass  # Diagnostic data never authorizes receipt reuse.
        else:
            print(line, flush=True)
    if result.get("stderr"):
        print(result["stderr"], file=sys.stderr, end="", flush=True)
    return {"bundle": bundle, "action_keys": request["action_keys"],
            "status": result["returncode"], "executed": result["executed"],
            "coalesced": result["coalesced"], "elapsed_seconds": time.monotonic() - started,
            "worker_evidence": evidence,
            "worker_output": subscription_diagnostics(Path(request["cache"]), bundle, result)}


def artifact_locations(record: dict | None) -> dict[str, str]:
    """Map each prepared label to its exact absolute path, for inventory versions 1 to 3.

    Version 3 may write an artifact as {"path": ..., "producer": {...}}; the
    producer is read separately by verification_producers.native_producer.
    """
    if (not record or type(record.get("version")) is not int or record["version"] not in (1, 2, 3)
            or not isinstance(record.get("artifacts"), dict)):
        raise VerificationError("missing or malformed prepared artifact inventory")
    locations = {}
    for label, entry in record["artifacts"].items():
        path = entry.get("path") if record["version"] == 3 and isinstance(entry, dict) else entry
        if not isinstance(path, str) or not Path(path).is_absolute():
            raise VerificationError("prepared artifacts must have exact absolute paths")
        locations[label] = path
    return locations


def artifact_paths(root: Path) -> list[Path]:
    artifacts = artifact_locations(read_record(root / "zig-out/verification/artifacts.json"))
    if not {"selka", "units", "cli", "core"} <= artifacts.keys():
        raise VerificationError("prepared inventory omits native test executables")
    paths = [Path(p) for p in artifacts.values()]
    paths.extend([root / "zig-out/bin/selka", root / "zig-out/verification/artifacts.json"])
    for name in ("test-index", "cache-plan"):
        path = root / "zig-out/libexec/selka/components" / (name + ".json")
        manifest = read_record(path)
        if not manifest or not isinstance(manifest.get("artifact"), str) or Path(manifest["artifact"]).name != manifest["artifact"]:
            raise VerificationError("invalid component manifest: " + name)
        paths.extend([path, path.parent / manifest["artifact"]])
    return sorted(set(paths))


def artifact_providers(root: Path, snapshot: Snapshot) -> dict[str, list[dict]]:
    """Project only declared providers; retain the complete snapshot for ABA checks."""
    try:
        locations = artifact_locations(read_record(root / "zig-out/verification/artifacts.json"))
    except VerificationError as error:
        raise VerificationError("prepared artifact inventory changed during provider selection") from error
    paths = {name: [Path(path)] for name, path in locations.items()}
    paths["selka"].append(root / "zig-out/bin/selka")
    paths["components"] = []
    for name in ("test-index", "cache-plan"):
        manifest_path = root / "zig-out/libexec/selka/components" / (name + ".json")
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


def recipe_predicate(recipe: str, root: Path):
    """Compile one input recipe into a test of a normalized absolute path (see matches_recipe)."""
    value = os.path.normpath(os.path.join(root, recipe))
    if recipe.endswith("/"):
        return lambda normalized: normalized.startswith(value + os.sep)
    for marker, recursive in (("/**/*", True), ("/*", False)):
        if marker in recipe:
            base, suffix = recipe.split(marker, 1)
            prefix = os.path.normpath(os.path.join(root, base)) + os.sep
            return lambda normalized: (normalized.startswith(prefix) and normalized.endswith(suffix)
                                       and (recursive or os.sep not in normalized[len(prefix):]))
    return lambda normalized: normalized == value


def matches_recipe(path: str, recipe: str, root: Path) -> bool:
    """Select a cohort's members from the single watched, hashed union."""
    return recipe_predicate(recipe, root)(os.path.normpath(os.path.join(root, path)))


def recipe_selector(files: list[dict], root: Path):
    """Return select(recipe) over watched records, normalizing each path once and caching per recipe."""
    normalized = [(os.path.normpath(os.path.join(root, item["path"])), item) for item in files]
    cache: dict[str, list[dict]] = {}

    def select(recipe: str) -> list[dict]:
        if recipe not in cache:
            matches = recipe_predicate(recipe, root)
            cache[recipe] = [item for path, item in normalized if matches(path)]
        return cache[recipe]
    return select


# Providers whose files are several distinct outputs of one producer.
MULTI_OUTPUT_PROVIDERS = frozenset({"components"})


def artifact_identities(record: dict | None, providers: dict[str, list[dict]],
                        sources: list[dict], root: Path) -> tuple[dict, dict]:
    """Identify every prepared provider, by producer where declared, else by bytes.

    Returns (identities, report). A producer identity replaces the bytes, which
    embed the checkout path in their debug information, so two worktrees at one
    commit agree. An installed copy (zig-out/bin/selka) must equal the produced
    bytes, or the provider falls back to bytes. The report names, per label,
    which identity was used and why a fallback happened.
    """
    select = recipe_selector(sources, root)
    identities, report = {}, {}
    for label in sorted(providers):
        producer, reason = verification_producers.native_producer(record, label)
        # A provider is copies of one artifact (zig-out/bin/selka beside the
        # produced binary), which must agree, except `components`: its two
        # manifests and the two executables they name are distinct outputs.
        if (producer is not None and label not in MULTI_OUTPUT_PROVIDERS
                and len({item["sha256"] for item in providers[label]}) != 1):
            producer, reason = None, "installed copy differs from the produced artifact"
        if producer is None:
            identities[label] = {"identity": "bytes", "artifacts": providers[label]}
            report[label] = {"identity": "bytes", "reason": reason}
            continue
        try:
            identity = verification_producers.native_identity(label, producer, select)
        except verification_producers.ProducerError as error:
            raise VerificationError(str(error)) from error
        identities[label] = {"identity": "producer", "sha256": key(identity)}
        report[label] = {"identity": "producer", "sources": len(identity["sources"]),
                         "path_free": not verification_producers.contains_absolute_path(identity)}
    return identities, report


def located_bytes(providers: dict[str, list[dict]], root: Path, report: dict) -> None:
    """Record, per narrowed provider whose key binds its bytes (a qualified
    producer identity also binds the artifact content), whether those bytes name
    the checkout (`bytes_name_root`), which no search of the key can see."""
    needle = os.fsencode(str(root))
    for label in sorted(set(providers) & set(verification_producers.CLOSURES)):
        named = False
        for item in providers[label]:
            try:
                named = named or needle in (root / item["path"]).read_bytes()
            except OSError:
                named = True
        report.setdefault(label, {})["bytes_name_root"] = named


def mentions(value: object, text: str) -> bool:
    """Whether `text` occurs anywhere in a JSON-serializable value."""
    return json.dumps(text, ensure_ascii=False)[1:-1] in json.dumps(value, sort_keys=True, ensure_ascii=False)


# How `path_free` shows each `common` facet independent of the checkout path.
# "value": the payload holds the value itself, which the root search sees.
# "preimage": a digest whose hashed document is searched (`facets_path_free`).
# "loaded_code": loaded-code digests, which hold no path text; their code
#   objects are rehashed as if loaded from another directory
#   (`location_dependent_code`), which the root search cannot do.
# "artifacts": prepared providers, judged per provider (producer identities).
# A facet missing here cannot be shown path-free, so path_free reports false.
COMMON_FACETS = {"version": "value", "options": "value", "platform": "value", "execution_limits": "value",
                 "shard_plans": "value", "action_controls": "value",
                 "environment": "preimage", "tools": "preimage", "build_configuration": "preimage",
                 "inventory": "preimage", "loaded_code_format": "loaded_code", "implementation": "loaded_code",
                 "artifacts": "artifacts"}


def implementation_code() -> list[tuple[str, str, object]]:
    """(module, bound digest, loaded code) of each coordinator module whose
    digest enters `common["implementation"]`, in key order."""
    modules = [("verification_measurement", verification_measurement),
               ("build_admission", verification_measurement.build_admission),
               ("verification_scheduler", verification_measurement.build_admission.scheduler_backend),
               ("verification_watch_pool", verification_snapshot.verification_watch_pool),
               ("verification_snapshot", verification_snapshot), ("fuzz_campaign_store", fuzz_campaign_store),
               ("verification_process", verification_process), ("verification_producers", verification_producers),
               ("verification_warm", verification_warm),
               ("verification_git_tree", verification_git_tree),
               ("verification_profiles", verification_profiles),
               ("verification_qualification", verification_qualification)]
    return [("verify_cache", LOADED_CODE_SHA256, _LOADED_CODE_OBJECT)] + [
        (name, module.LOADED_CODE_SHA256, module._LOADED_CODE_OBJECT) for name, module in modules]


RELOCATION_PROBE = "/selka-verification-relocation-probe"


def location_dependent_code(code: list[tuple[str, str, object]] | None = None) -> list[str]:
    """Modules whose bound loaded-code digest would differ had the same code been
    loaded from another checkout: the digest is recomputed with every file name
    moved under RELOCATION_PROBE. Includes the identity helper itself."""
    rows = (implementation_code() if code is None else code) + [
        ("verification_code_identity", code_identity.LOADED_CODE_SHA256, code_identity._LOADED_CODE_OBJECT)]
    dependent = []
    for name, digest, loaded in rows:
        try:
            moved = code_identity.loaded_code_sha256(code_identity.relocated(loaded, RELOCATION_PROBE))
        except code_identity.CodeIdentityError:
            moved = None
        if moved != digest:
            dependent.append(name)
    return dependent


def path_free(payload: dict, root: Path, facets_path_free: bool, report: dict) -> bool:
    """Whether no checkout path entered an action key.

    Every `common` facet must be classified in COMMON_FACETS. The worktree path
    must occur neither in the payload nor in the documents hashed into its
    digest facets, and no loaded-code digest may depend on where the code was
    loaded from (`facets_path_free` covers both). Every prepared provider the
    action depends on must have a producer identity: its narrowed selection,
    else all of them; a narrowed identity that also binds artifact bytes needs
    bytes that do not name the checkout (`located_bytes`).
    """
    # Explicit plan options keep their logical execution paths and private evidence.
    if "shard_plans" in payload["common"]:
        return False
    if any(name not in COMMON_FACETS for name in payload["common"]):
        return False
    if not facets_path_free or verification_producers.contains_absolute_path(payload):
        return False
    artifacts = payload["common"].get("artifacts")
    if isinstance(artifacts, dict) and any(
            isinstance(value, dict) and "artifacts" in value and report.get(label, {}).get("bytes_name_root") is not False
            for label, value in artifacts.items()):
        return False  # A narrowed identity binds artifact bytes that name the checkout.
    labels = artifacts.keys() if isinstance(artifacts, dict) else report.keys()
    return all(report.get(label, {}).get("identity") == "producer"
               and report.get(label, {}).get("path_free", True) for label in labels)


def action_payload(group: dict, snapshot: Snapshot, common: dict, root: Path,
                   providers: dict[str, list[dict]] | None = None, membership: dict | None = None,
                   producer_manifest: dict | None = None, labels: dict | None = None) -> dict:
    """The exact document an action key hashes; `labels` are artifact_identities' per-provider identities."""
    predicates = tuple(recipe_predicate(recipe, root) for recipe in group["inputs"])

    def included(path):
        normalized = os.path.normpath(os.path.join(root, path))
        return any(matches(normalized) for matches in predicates)

    files = snapshot.selected_files(included)
    selected = group.get("artifacts")
    if selected is not None:
        if providers is None or any(name not in providers for name in selected):
            raise VerificationError("action names an unavailable artifact provider: " + group["id"])
        legacy = {"selka", "units", "cli", "core", "golden", "memory-budget",
                  "component-support", "component-builder", "components"}
        identities = {}
        for name in selected:
            if (name in verification_producers.CLOSURES and labels is not None
                    and labels.get(name, {}).get("identity") == "producer"):
                # The version-3 recipe was authenticated against watched inputs
                # by artifact_identities. Its bytes contain DWARF locations.
                identities[name] = labels[name]
            elif name in verification_producers.CLOSURES:
                producer = verification_producers.qualified_identity(
                    producer_manifest or {}, name, providers[name], files, common)
                if producer is None:
                    break
                identities[name] = {"producer": producer, "artifacts": providers[name]}
            elif name in legacy:
                identities[name] = labels[name] if labels is not None else providers[name]
            else:
                break  # New narrowing needs an explicit closure review.
        else:
            common = dict(common, artifacts=identities)
    if membership is not None:
        common = {name: value for name, value in common.items() if name != "inventory"}
    return {"domain": ACTION_DOMAIN, "contract": group, "common": common,
            "files": files, "membership": membership}


def action_identity(group: dict, snapshot: Snapshot, common: dict, root: Path,
                    providers: dict[str, list[dict]] | None = None) -> str:
    return key(action_payload(group, snapshot, common, root, providers))


def check_all(snapshots: list[Snapshot]) -> bool:
    verification_measurement.current()  # An expired window cannot certify publication.
    return all(snapshot.unchanged() for snapshot in snapshots)


def drain_events(snapshots: list[Snapshot]) -> None:
    """Keep original event queues serviced without rehashing or rebasing inputs."""
    for snapshot in snapshots:
        check = getattr(snapshot, "events_unchanged", None)
        if check is not None and not check():
            raise SnapshotError("inputs changed while awaiting admitted work")


def snapshot_role(snapshot, role):
    """Attach an advisory name without changing snapshot authority or identity."""
    snapshot.verification_role = role
    return snapshot


def stability_diagnostics(snapshots) -> dict:
    """Read already observed rejection causes without revalidating or clearing them."""
    reasons, unknown, truncated = [], False, False
    for snapshot in snapshots:
        try:
            value = snapshot.stability_diagnostics(getattr(snapshot, "verification_role", "inputs"))
            entries = value.get("reasons", [])
            if not isinstance(entries, list):
                raise ValueError("invalid stability diagnostics")
            for entry in entries:
                if len(reasons) < 64:
                    reasons.append({name: str(entry.get(name, "unknown"))[:512]
                                    for name in ("role", "facet", "name", "reason")})
                else:
                    truncated = True
            # Clean snapshots need not invent a reason for a different snapshot's failure.
            unknown |= bool(value.get("unknown")) and bool(entries)
            truncated |= bool(value.get("truncated"))
        except Exception:
            unknown = True
    return {"version": 1, "status": "observed" if reasons else "unknown", "reasons": reasons,
            "unknown": unknown or not bool(reasons), "truncated": truncated}


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
    """The `zig build` command line of every build this coordinator runs. It always ends with `-Dproofs=true` (any other
    `-Dproofs=` is dropped): the complete gate runs the four Lean proof actions, and a build without the flag would exit 0
    on a skipped proof, which `inventory` refuses to certify."""
    options = [arg for arg in options if not arg.startswith("-Dproofs=") and not (rerun and arg.startswith("-Dtest-rerun="))]
    args = [str(zig), "build", *targets, *options, "-Dproofs=true"]
    if rerun and "-Dtest-rerun=true" not in args:
        args.append("-Dtest-rerun=true")
    if not any(arg.startswith("--seed=") for arg in args):
        args.append("--seed=0")
    return args


_CODE_HELPER_SOURCE_PROOF = None


def authenticate_code_identity(root, watched, snapshots, stack, digest_session=None):
    """Authenticate the loaded helper under a retained, actual-provider watch."""
    global _CODE_HELPER_SOURCE_PROOF
    actual = Path(code_identity.__file__).absolute()

    def matching(snapshot):
        predicate = lambda name: os.path.abspath(root / name) == str(actual)
        selected = getattr(snapshot, "selected_files", None)
        rows = selected(predicate) if selected is not None else [
            row for row in snapshot.identity["files"] if predicate(row["path"])]
        if len(rows) > 1:
            raise code_identity.CodeIdentityError("ambiguous watched helper source")
        return rows[0] if rows else None

    record = matching(watched)
    if record is None:
        watched = stack.enter_context(Snapshot(root, [], [actual], digest_session=digest_session))
        watched.verification_role = "code_identity_helper"
        snapshots.append(watched)
        record = matching(watched)
    if record is None:
        raise code_identity.CodeIdentityError("actual helper provider is not watched")
    source_sha, size = record.get("sha256"), record.get("size")
    if (type(source_sha) is not str or len(source_sha) != 64
            or any(character not in "0123456789abcdef" for character in source_sha)
            or type(size) is not int or not 0 <= size <= code_identity._MAX_AUTH_SOURCE_BYTES):
        raise code_identity.CodeIdentityError("missing or unsupported watched helper source metadata")
    expected = code_identity._LOADED_CODE_OBJECT
    proof = _CODE_HELPER_SOURCE_PROOF
    # CodeType equality/hash can erase distinctions. This cache binds the same
    # immutable object by identity and exact watched content, never metadata.
    if (proof is not None and proof[0] is expected and proof[1] == source_sha
            and proof[2] == code_identity.LOADED_CODE_SHA256):
        return
    if not watched.unchanged():
        raise SnapshotError("helper source changed before bootstrap authentication")
    with actual.open("rb") as stream:
        source = stream.read(code_identity._MAX_AUTH_SOURCE_BYTES + 1)
    if len(source) != size or hashlib.sha256(source).hexdigest() != source_sha:
        raise SnapshotError("helper source changed during bootstrap authentication")
    code_identity.authenticate_code_source(source, expected)
    actual_code_sha = code_identity.loaded_code_sha256(expected)
    if actual_code_sha != code_identity.LOADED_CODE_SHA256:
        raise code_identity.CodeIdentityError("loaded helper identity is detached")
    if not watched.unchanged():
        raise SnapshotError("helper source changed after bootstrap authentication")
    _CODE_HELPER_SOURCE_PROOF = (expected, source_sha, actual_code_sha)


def prepare(root: Path, cache: Path, zig: Path, options: list[str], env: dict[str, str],
            common: dict, snapshots: list[Snapshot], stack: ExitStack,
            timings: list[dict] | None = None, phases: dict | None = None,
            digest_session=None, limits: ProcessLimits | None = None,
            notes: dict | None = None, verbose: bool = False, early=None,
            before_admission=None) -> tuple[dict, Snapshot, float]:
    """Load the inventory, then reuse or build the prepared artifacts.

    `early`, a `gate_cheap_checks.Runner`, starts once the inventory and the source watches are in place, before the
    preparation build: the checks that need no compiler at once, and the compiler's two when the prepared artifacts are
    reused (so the compiler is current). It is the preparation build's `stop`: a finding ends that build, and this
    raises `CheapChecksFailed`.
    """
    configuration = snapshot_role(stack.enter_context(Snapshot(root, CONFIG_INPUTS, digest_session=digest_session)), "configuration")
    snapshots.append(configuration)
    config = snapshot_role(stack.enter_context(Snapshot(root, CONFIG_INPUTS + COORDINATOR_INPUTS, digest_session=digest_session)), "coordinator")
    snapshots.append(config)
    authenticate_code_identity(root, config, snapshots, stack, digest_session)
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
    if plan is not None:
        empty_logs(cache / "last-logs/inventory")  # no inventory build runs: an older one's log is not this run's
    held = 0.0
    if plan is None:
        if before_admission is not None:
            before_admission()
        status, seconds = run_admitted(root, "build", zig_command(zig, ["verification-plan"], options),
                                       env, lambda: check_all(snapshots), timings=timings,
                                       limits=limits, log_dir=cache / "last-logs/inventory", verbose=verbose,
                                       heartbeat=lambda: drain_events(snapshots))
        held += seconds
        if not check_all(snapshots):
            raise InputsChanged("inputs changed while the inventory was prepared")
        if status:
            raise VerificationError("inventory preparation failed or its inputs changed (exit %d)" % status,
                                    124 if status == 124 else 2)
        plan = inventory(plan_path)
        publish_checked(plan_receipt, {"key": config_key, "inventory": key(plan)}, snapshots)
    common["build_configuration"] = key(action_configuration(config.identity, plan, root, configuration.identity, notes))
    common["action_controls"] = plan["configuration"]
    source_started = time.monotonic()
    sources = snapshot_role(stack.enter_context(Snapshot(root, PREPARE_INPUTS, digest_session=digest_session)), "preparation_sources")
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
    if artifacts is not None:
        empty_logs(cache / "last-logs/preparation")  # reused: an older (perhaps failed) build's log is not this run's
    if early is not None:
        early.context.plan = plan
        compiler = prepared_compiler(root) if artifacts is not None else None
        early.context.compiler = compiler
        early.start([name for name in gate_cheap_checks.applicable(plan)
                     if compiler is not None or name not in gate_cheap_checks.COMPILER_CHECKS])
    if artifacts is None:
        if before_admission is not None:
            before_admission()
        status, seconds = run_admitted(root, "build", zig_command(zig, ["verification-prepare"], options),
                                       env, lambda: check_all(snapshots), timings=timings,
                                       limits=limits, log_dir=cache / "last-logs/preparation", verbose=verbose,
                                       heartbeat=lambda: drain_events(snapshots), stop=early)
        held += seconds
        if early is not None and early.killed:
            raise CheapChecksFailed("a cheap check failed while the artifacts were being prepared")
        if not check_all(snapshots):
            raise InputsChanged("inputs changed while the artifacts were prepared")
        if status:
            raise VerificationError("artifact preparation failed or its inputs changed (exit %d)" % status,
                                    124 if status == 124 else 2)
        artifacts = stack.enter_context(Snapshot(root, [], artifact_paths(root), digest_session=digest_session))
        publish_checked(cache / "preparation.json", {"key": preparation_key, "artifacts": artifacts.identity},
                        snapshots + [artifacts])
    snapshots.append(snapshot_role(artifacts, "prepared_artifacts"))
    return plan, artifacts, held


def shared_cache_location(flag: str | None, environ: Mapping[str, str],
                          default_sharing: bool | None = None) -> tuple[Path | None, str]:
    """Resolve the shared evidence store and how it was chosen.

    Precedence: --shared-cache-dir, then SELKA_VERIFICATION_SHARED_CACHE, then,
    only when default sharing is on, $XDG_CACHE_HOME/selka/verification-shared
    or ~/.cache/selka/verification-shared. An explicitly empty value disables
    sharing. The source is "flag", "environment", "default" or "none".
    """
    if flag is not None:
        return (Path(flag) if flag else None), "flag"
    value = environ.get(SHARED_CACHE_VARIABLE)
    if value is not None:
        return (Path(value) if value else None), "environment"
    if not (DEFAULT_SHARING if default_sharing is None else default_sharing):
        return None, "none"
    base = environ.get("XDG_CACHE_HOME", "")
    if not os.path.isabs(base):
        home = environ.get("HOME", "")
        if not os.path.isabs(home):
            return None, "none"
        base = os.path.join(home, ".cache")
    return Path(base) / "selka" / "verification-shared", "default"


def open_shared_store(location: Path | None, source: str, stack: ExitStack):
    """Open and lease the shared evidence store, or None.

    An unusable default store warns once and verification proceeds unshared;
    an unusable store the caller named explicitly stays an error.
    """
    if location is None:
        return None
    try:
        store = fuzz_campaign_store.Store(location)
        stack.enter_context(store.lease())
        return store
    except (OSError, fuzz_campaign_store.FormatError) as error:
        if source != "default":
            raise
        print("verification: warning: default shared evidence store %s is unusable (%s); continuing without sharing"
              % (location, error), file=sys.stderr)
        return None


def shard_plan_files(options: list[str]) -> list[Path]:
    """Declared plan inputs; retain logical paths to watch symlink retargets."""
    files = {}
    for arg in options:
        name, separator, value = arg.partition("=")
        if name not in SHARD_PLAN_OPTIONS:
            continue
        if not separator or not value or "\x00" in value:
            raise VerificationError("missing or invalid shard plan: " + name)
        if name in files:
            raise VerificationError("duplicate shard plan: " + name)
        files[name] = Path(value)
    return list(files.values())


def execute(root: Path, cache: Path, zig: Path, options: list[str], force: bool = False,
            shared_cache_dir: Path | None = None, *, build_timeout: float | None = None,
            gate_timeout: float | None = None, warn_after: float | None = None,
            budget_policy: Path | None = None, profile: str = "complete", quick_actions: int = 3,
            qualification_targets=None, qualification_max_actions=6,
            qualification_timeout=300, qualification_fuzz_steps=8, shared_cache_source: str | None = None,
            dry_run: bool = False, _action_keys: list[str] | None = None,
            verify_digests: bool = False, verbose: bool = False, fail_fast: bool = False,
            restarts: list | None = None, disk_waiter: DiskWaiter | None = None, flaky_rerun: bool = True) -> int:
    if profile not in verification_profiles.PROFILES or type(quick_actions) is not int or not 1 <= quick_actions <= 1024:
        raise ValueError("invalid verification profile or quick action bound")
    if dry_run and force:
        raise ValueError("a dry run cannot force reruns")
    qualification_controls = {"targets": list(verification_qualification.OBLIGATIONS if qualification_targets is None else qualification_targets),
        "max_actions": qualification_max_actions, "action_timeout": qualification_timeout, "fuzz_steps": qualification_fuzz_steps}
    verification_qualification.validate_options(**qualification_controls)
    # `0` is the documented way to turn a deadline off; `None` is unbounded too.
    build_timeout = build_timeout or None
    gate_timeout = gate_timeout or None
    build_limits, gate_limits = ProcessLimits(build_timeout), ProcessLimits(gate_timeout)
    measurement = verification_measurement.current()
    if warn_after is not None:
        ProcessLimits(warn_after)  # Same positive, finite validation; advisory only.
    started = time.monotonic()
    admissions, phases, subscriptions = [], {}, []
    (root / "zig-out/verification").mkdir(parents=True, exist_ok=True)
    if not dry_run:
        # An earlier run's cheap-check findings are no part of this run's logs.
        shutil.rmtree(cache / "last-logs" / "cheap", ignore_errors=True)
    env = normalized_environment(root)
    env["ZIG"] = str(zig)
    env["SELKA_ZIG"] = str(zig)
    tool_recipes, tool_files = tool_contract(zig, env)
    with ExitStack() as stack:
        shared_source = shared_cache_source or ("none" if shared_cache_dir is None else "flag")
        # Plans bind host paths until role/digest normalization is qualified.
        declared_plans = shard_plan_files(options)
        if declared_plans:
            shared_source = "shard-plan-private"
        shared = None if declared_plans else open_shared_store(shared_cache_dir, shared_source, stack)
        session = stack.enter_context(verification_snapshot.DigestSession(
            root=root, record_path=cache / "digests-v1.json",
            verify=verify_digests or force or "-Dtest-rerun=true" in options))
        snapshots = []
        failure_context = {"stage": "preparation", "actions": []}

        def record_failure(error_type, error, _traceback):
            if error_type is not None:
                failure_status = (RETRY if isinstance(error, SnapshotError) else
                                  130 if isinstance(error, KeyboardInterrupt) else getattr(error, "status", 2))
                diagnostic_record(cache / "last-run.json", {"version": REPORT_VERSION, "success": False,
                    "status": failure_status, "stage": failure_context["stage"], "error": str(error)[:1024],
                    "actions": failure_context["actions"], "stability_diagnostics": stability_diagnostics(snapshots),
                    "admissions": admissions, "timings": phases, "subscriptions": subscriptions,
                    "elapsed_seconds": time.monotonic() - started})
            return False

        try:
            tools = snapshot_role(stack.enter_context(Snapshot(root, tool_recipes, tool_files, digest_session=session)), "tools")
            snapshots.append(tools)
            # Recheck lookup membership now. The complete snapshot set is validated
            # before every admitted command, cache verdict and publication below.
            if tool_contract(zig, env) != (tool_recipes, tool_files):
                raise VerificationError("tool resolution changed while installing input watches")
            tool_document, identity_environment = logical_tools(root, zig, env, tools, tool_files)
            host = HostContext()
            snapshots.append(host)
        except BaseException as error:
            # Early watch failures must replace any older successful diagnostic.
            record_failure(type(error), error, None)
            raise

        stack.push(record_failure)
        shard_plans = None
        if declared_plans:
            # Preserve logical symlink watches through publication, including ABA.
            shard_plans = snapshot_role(stack.enter_context(
                Snapshot(root, [], declared_plans, digest_session=session)), "shard_plans")
            snapshots.append(shard_plans)
        common = {"version": VERSION, "options": options,
                  "environment": environment_identity(identity_environment, tools, tool_files, root, tool_document), "platform": host.identity,
                  "tools": key(tool_document),
                  # A timing window schedules the request; it is no input to
                  # any action's result, so it stays out of every key (F14) and
                  # is reported as `measurement_window` in last-run.json.
                  "execution_limits": {"build": build_limits.execution_identity(),
                                       "gate": gate_limits.execution_identity()},
                  "loaded_code_format": [code_identity.FORMAT_VERSION, code_identity.LOADED_CODE_SHA256],
                  "implementation": [digest for _, digest, _ in implementation_code()]}
        if shard_plans is not None:
            common["shard_plans"] = shard_plans.identity
        # The cheap checks (item 4a): the commands of the format, documentation, input-coverage and
        # registry actions, run before any test action. A finding ends the gate before the gate build starts.
        early = None
        if not dry_run and _action_keys is None and profile != "quick":
            early = gate_cheap_checks.Runner(gate_cheap_checks.Context(root=root, zig=str(zig), env=dict(env)))
            stack.callback(early.stop)  # whatever ends this attempt (a verdict, a restart) ends its checks too
        try:
            configuration_notes = {}
            plan, artifacts, build_seconds = prepare(root, cache, zig, options, env, common, snapshots, stack,
                                                    admissions, phases, session, build_limits, configuration_notes,
                                                    verbose=verbose, early=early, before_admission=disk_waiter)
        except CheapChecksFailed:
            return cheap_check_failure(cache, early, snapshots, [], admissions, phases, started, verbose)
        except VerificationError as error:
            diagnostic_record(cache / "last-run.json", {"version": REPORT_VERSION, "success": False,
                "status": error.status, "stage": "preparation", "error": str(error), "actions": [],
                "admissions": admissions, "timings": phases,
                "stability_diagnostics": stability_diagnostics(snapshots),
                "elapsed_seconds": time.monotonic() - started})
            if not isinstance(error, InputsChanged):
                print_preparation_failure(cache, admissions)
            raise
        common["inventory"] = key(plan)
        if early is not None and early.context.compiler is None:
            # Prepared just now: the compiler's two checks run beside the cache lookup below.
            early.context.compiler = prepared_compiler(root)
            if early.context.compiler is not None:
                early.start([name for name in gate_cheap_checks.applicable(plan)
                             if name in gate_cheap_checks.COMPILER_CHECKS])
        providers = artifact_providers(root, artifacts)
        producer_manifest = read_record(root / "zig-out/verification/artifacts.json")
        # Producer identities come from the preparation snapshots, which every
        # recipe must fall inside; artifacts.json's own bytes hold only paths
        # and producer metadata, both represented here without a location.
        recipe_sources = [item for snapshot in snapshots if getattr(snapshot, "verification_role", "")
                          in ("configuration", "preparation_sources") for item in snapshot.identity["files"]]
        labels, artifact_report = artifact_identities(producer_manifest, providers, recipe_sources, root)
        located_bytes(providers, root, artifact_report)
        common["artifacts"] = key({"version": producer_manifest.get("version") if producer_manifest else None,
                                   "providers": labels})
        environment_names = identity_variables(env)
        relocation_dependent = location_dependent_code()
        groups = [dict(group) for group in plan["groups"]]
        recipes = sorted({entry for group in groups for entry in group["inputs"]})
        input_started = time.monotonic()
        inputs = snapshot_role(stack.enter_context(Snapshot(root, recipes, digest_session=session)), "action_inputs")
        phases["action_input_snapshot_seconds"] = time.monotonic() - input_started
        snapshots.append(inputs)
        unsupported = [name for name in UNTRACKED_ENV if env.get(name)]
        force = force or "-Dtest-rerun=true" in options
        if force and not dry_run:
            # A failed explicit rerun must not leave an older success available.
            # This is a local evidence store; deleting evidence only causes work.
            for path in (cache / "actions").glob("*.json"):
                path.unlink(missing_ok=True)
        metadata = {action["id"]: action for action in plan["action_metadata"]}
        warm_identities = verification_warm.identities(root, groups, env, stack, snapshots, session, metadata)
        identity_plan = plan
        identity_metadata = {action["id"]: action for action in identity_plan["action_metadata"]}
        common["inventory"] = key(identity_plan)
        facets_path_free = not relocation_dependent and not verification_producers.contains_absolute_path(
            {"tools": tool_document, "environment": {name: identity_environment[name] for name in environment_names},
             "configuration": [snapshot.identity for snapshot in snapshots
                               if getattr(snapshot, "verification_role", "") == "coordinator"],
             "inventory": identity_plan})
        results, selected, keys, summaries = [], [], {}, {}
        failure_context.update(stage="cache_lookup", actions=results)
        for group in groups:
            if early is not None and early() and cheap_finding_decided(early, results):
                return cheap_check_failure(cache, early, snapshots, results, admissions, phases, started, verbose)
            payload = action_payload(group, inputs, common, root, providers, identity_metadata[group["id"]],
                                     producer_manifest, labels)
            if group["id"] in warm_identities:
                payload["warm_inputs"] = warm_identities[group["id"]]
            action_key = key(payload)
            keys[group["id"]] = action_key
            summary = verification_report.dependency_summary(group, payload["files"], dict(payload["common"], membership=identity_metadata[group["id"]]))
            summary_path = cache / "diagnostics" / (group["id"] + ".json")
            previous = verification_report.read_summary(summary_path)
            summaries[group["id"]] = (summary_path, summary)
            disposition = verification_warm.disposition(group, force=force, unsupported=bool(unsupported),
                filtered=bool(plan.get("configuration", {}).get("filtered")))
            reusable = disposition == "cacheable"
            hit = reusable and prior_success(shared, cache, action_key)
            state = "reused" if hit else "execute" if reusable else "fresh"
            reason = "valid prior success" if hit else "no valid receipt" if reusable else group["reason"]
            if unsupported:
                reason = "untracked environment override: " + ", ".join(unsupported)
            elif force:
                reason = "explicit rerun or filtered request"
            if disposition in ("prepared", "owed"):
                state = disposition
                reason = ("validated current preparation inputs and artifacts" if state == "prepared" else
                          "qualification profile obligation; no success claimed")
            diagnostic = (verification_report.explain_miss(summary, previous) if reusable and not hit
                          else {"status": "policy", "reason": reason, "changes": [], "truncated": False})
            diagnostic["comparison_scope"] = "previous stable request; not necessarily the receipt-producing success"
            results.append({"id": group["id"], "action_key": action_key, "state": state, "reason": reason,
                            "invalidation": diagnostic,
                            "path_free": path_free(payload, root, facets_path_free, artifact_report),
                            "environment_variables": environment_names})
            if verbose:
                print("verification: %s %s (%s)" % (state, group["id"], reason), flush=True)
            if not hit and disposition not in ("prepared", "owed"):
                selected.append(group)
        profile_plan = verification_profiles.schedule(plan, results, profile, quick_actions=quick_actions)
        selected_ids = set(profile_plan["selected"])
        by_id = {group["id"]: group for group in groups}
        selected = [by_id[name] for name in profile_plan["selected"]]
        if _action_keys is not None:
            wanted = set(_action_keys)
            eligible = {keys[group["id"]] for group in groups if group["cacheable"]}
            if (not wanted or not wanted <= eligible or force or unsupported
                    or plan.get("configuration", {}).get("filtered")):
                raise VerificationError("keyed action subset changed or lost reuse authority", RETRY)
            selected = [group for group in selected if keys[group["id"]] in wanted]
            selected_ids = {group["id"] for group in selected}
            profile_plan["selected"] = [group["id"] for group in selected]
            profile_plan["deferred"] = [name for name in profile_plan["pending"] if name not in selected_ids]
        for row in results:
            if row["state"] not in ("reused", "prepared", "owed") and row["id"] not in selected_ids:
                row.update(state="skipped", reason="deferred by partial feedback profile")
        # Where each reuse was found: before the gate queue, or after admission
        # (evidence another request published while this one queued).
        reuse_lookups = {"pre_queue": sum(row["state"] == "reused" for row in results), "post_admission": 0}
        if verbose:
            print("verification: profile %s; %d pending, %d selected, %d deferred%s" %
              (profile, len(profile_plan["pending"]), len(selected), len(profile_plan["deferred"]),
               "; heuristic partial selection" if profile_plan["heuristic"] else ""), flush=True)
        if not check_all(snapshots):
            diagnostic_record(cache / "last-run.json", {"version": REPORT_VERSION, "success": False,
                "status": RETRY, "stage": "cache_lookup", "actions": results,
                "inputs_stable": False, "stability_diagnostics": stability_diagnostics(snapshots),
                "admissions": admissions, "timings": phases,
                "elapsed_seconds": time.monotonic() - started})
            raise InputsChanged("inputs changed during cache lookup")
        if dry_run:
            # The plan export: identities and reuse verdicts after preparation,
            # with no gate admission, publication or advisory summary writes.
            diagnostic_record(cache / "dry-run.json", {"version": REPORT_VERSION, "dry_run": True, "profile": profile,
                "evidence_store": {"shared": shared is not None, "source": shared_source},
                "common": common, "budget_context": key({name: value for name, value in common.items() if name != "inventory"}),
                "actions": results, "profile_plan": profile_plan, "artifact_identities": artifact_report,
                "declarative_configuration": configuration_notes.get("declarative_configuration"),
                "relocation_dependent_code": relocation_dependent,
                "admissions": admissions, "elapsed_seconds": time.monotonic() - started})
            print("verification: dry run; %d reused, %d would run; report %s" %
                  (sum(row["state"] == "reused" for row in results), len(selected), cache / "dry-run.json"), flush=True)
            return 0
        if early is not None:
            waited = time.monotonic()
            early.wait()
            phases["cheap_checks_wait_seconds"] = time.monotonic() - waited
            report_abandoned(early)
            if cheap_findings_that_count(early, results):
                return cheap_check_failure(cache, early, snapshots, results, admissions, phases, started, verbose)
            if verbose:
                print("verification: cheap checks passed (%s)" % ", ".join(
                    "%s %.1f s" % (name, seconds) for name, seconds in early.seconds.items()), flush=True)
        phases["prepare_lookup_outside_admission_seconds"] = (time.monotonic() - started
                                                              - sum(event["elapsed_seconds"] for event in admissions))
        status, gate_seconds = 0, 0.0
        flaky = None
        action_locks = None
        gate_started = False  # whether this attempt sent a gate command: after that, a change fails as before
        failure_context["stage"] = "execution"
        telemetry_directory = None
        fail_fast_watch = None
        published = []
        publication_tokens = {}
        commit_value = {"domain": "verification-publication-v1", "nonce": os.urandom(32).hex()}
        commit_digest = key(commit_value)
        commit_path = cache / "commits" / (commit_digest + ".json")
        def revoke_publications():
            commit_path.unlink(missing_ok=True)
            if shared is not None:
                # Hide the entire owned batch before any fallible per-key
                # invalidation. Later peer generations use their own markers.
                shared.revoke_success_batch(commit_digest)
            for path in published:
                path.unlink(missing_ok=True)
                if shared is not None:
                    shared.invalidate_success(path.stem, publication=publication_tokens[path.stem])
        def revoke_on_failure(error_type, _error, _traceback):
            if error_type is not None:
                revoke_publications()
            return False
        stack.push(revoke_on_failure)
        if measurement is not None:
            # A deadline in later reporting still makes this bounded request
            # incomplete. Retain rollback until its timing holder closes.
            measurement.rollbacks.append(revoke_publications)
        def finalize_gate(status, authority):
            failure_context["stage"] = "publication"
            def publication_guard():
                # Full metadata revalidation brackets the batch. Between those
                # checks and around its commit, retain the original watchers so
                # source mutation (including ABA) still revokes publication.
                # Older/non-event authorities conservatively use their full check.
                verification_measurement.current()
                return (authority() and all(
                    getattr(snapshot, "events_unchanged", snapshot.unchanged)()
                    for snapshot in snapshots) and authority())

            def publication_unchanged():
                stable = authority() and check_all(snapshots)
                verification_measurement.current()
                return stable and authority()
            publication_started = time.monotonic()
            if status == 0:
                publication_valid = False
                try:
                    batch = []
                    for group in selected:
                        if group["cacheable"] and not unsupported and (not plan.get("configuration", {}).get("filtered") or group["id"] not in verification_warm.FILTERED):
                            action_key = keys[group["id"]]
                            publication_tokens[action_key] = hashlib.sha256(os.urandom(32)).hexdigest()
                            value = {"version": VERSION, "kind": "verification-success", "key": action_key}
                            batch.append((action_key, value, [], publication_tokens[action_key]))

                    def stage_local(action_key):
                        if not publication_guard():
                            raise fuzz_campaign_store.InputsChanged("inputs changed while staging local receipt")
                        path = cache / "actions" / (action_key + ".json")
                        published.append(path)
                        save_receipt(path, action_key, commit_digest)

                    try:
                        if shared is not None:
                            if not shared.publish_success_batch(batch, publication_unchanged, commit_digest,
                                                                guard=publication_guard, stage=stage_local):
                                raise VerificationError("shared verification success publication rejected")
                        else:
                            if not publication_unchanged():
                                raise fuzz_campaign_store.InputsChanged("inputs changed before batch publication")
                            for action_key, _, _, _ in batch:
                                stage_local(action_key)
                            if not publication_unchanged():
                                raise fuzz_campaign_store.InputsChanged("inputs changed after batch publication")
                    except fuzz_campaign_store.InputsChanged:
                        status = RETRY
                    if status == 0 and published:
                        # This atomic marker is the publication commit boundary.
                        # SIGKILL before it leaves every staged receipt invisible.
                        if not publication_guard():
                            status = RETRY
                        if shared is not None:
                            if status == 0:
                                shared.put_blob(encoded(commit_value))
                            if not publication_guard():
                                status = RETRY
                        if status == 0:
                            atomic_record(commit_path, commit_value)
                    if not publication_guard():
                        status = RETRY
                    publication_valid = status == 0
                finally:
                    if not publication_valid:
                        revoke_publications()
            phases["publication_seconds"] = time.monotonic() - publication_started
            return status

        if selected:
            if disk_waiter is not None:
                disk_waiter()  # before the shared per-action locks below, which other worktrees' gates may want
            gate_environment = dict(env)
            try:
                telemetry_directory = Path(stack.enter_context(tempfile.TemporaryDirectory(
                    prefix="test-telemetry-", dir=cache)))
                gate_environment["SELKA_VERIFICATION_TELEMETRY_DIR"] = str(telemetry_directory)
            except OSError:
                pass  # Diagnostic storage cannot change test selection or verdict.
            if fail_fast:
                if telemetry_directory is None:
                    print("verification: warning: --fail-fast needs the gate's telemetry directory and has none; "
                          "the whole gate runs", file=sys.stderr)
                else:
                    flaky_on = FLAKY_RERUN and flaky_rerun and _action_keys is None
                    fail_fast_watch = verification_process.FailFast(
                        telemetry_directory, defer=flaky_beacon if flaky_on else None, limit=FLAKY_MAX)
            rows = {row["id"]: row for row in results}

            def gate_command():
                # Force chosen Run steps: an outer miss (tool/environment/ABA) must not
                # be accidentally satisfied by a weaker, older inner Zig verdict.
                targets = (plan["required_targets"] if len(selected) == len(groups)
                           else [group["target"] for group in selected])
                return zig_command(zig, targets, options, rerun=True)

            def recheck_after_admission():
                # The inputs were revalidated just now, so every key still names
                # this request's inputs: a success another request published for
                # one of them while this one queued is this action's evidence.
                late = {group["id"] for group in selected if rows[group["id"]]["state"] == "execute"
                        and prior_success(shared, cache, keys[group["id"]])}
                for name in sorted(late):
                    rows[name].update(state="reused", reason="valid prior success published while queued",
                                      invalidation={"status": "policy", "reason": "valid prior success published while queued",
                                                    "changes": [], "truncated": False,
                                                    "comparison_scope": rows[name]["invalidation"]["comparison_scope"]})
                    if verbose:
                        print("verification: reused %s (published while queued)" % name, flush=True)
                reuse_lookups["post_admission"] += len(late)
                selected[:] = [group for group in selected if group["id"] not in late]
                for field in ("selected", "pending"):
                    profile_plan[field] = [name for name in profile_plan[field] if name not in late]
                return gate_command() if selected else None

            if (shared is not None and _action_keys is None and not force and not verify_digests and not unsupported
                    and not plan.get("configuration", {}).get("filtered") and measurement is None and env.get("SELKA_ADMISSION_BACKEND") == "scheduler"):
                action_keys = sorted(keys[group["id"]] for group in selected
                                     if group["cacheable"] and rows[group["id"]]["state"] == "execute")
                if action_keys:
                    request = {"version": 1, "root": str(root), "cache": str(cache), "zig": str(zig),
                               "shared": str(shared.root), "options": options, "action_keys": action_keys,
                               "build_timeout": build_timeout, "gate_timeout": gate_timeout}
                    subscription = subscribe_gate(request, env)
                    subscriptions.append(subscription)
                    if subscription["status"] != 0:
                        raise VerificationError("keyed verification worker failed", subscription["status"])
                    if not check_all(snapshots) or not all(prior_success(shared, cache, value) for value in action_keys):
                        raise VerificationError("keyed verification evidence is incomplete or inputs changed", RETRY)
                    recheck_after_admission()
            if shared is not None:
                # Same store/action across worktrees. Hold through rollback and
                # publication; a pre-queue miss never invalidates a newer peer.
                phases["action_lock_wait_seconds"] = 0.0
                # Its own stack, so a flaky rerun (which publishes nothing) can release the locks first (item 4d).
                action_locks = stack.enter_context(ExitStack())
                for action_key in sorted(keys[group["id"]] for group in selected):
                    lock_started = time.monotonic()
                    action_locks.enter_context(shared.coordinator_lock(action_key))
                    phases["action_lock_wait_seconds"] += time.monotonic() - lock_started
                stack.push(revoke_on_failure)
                recheck_after_admission()
                for group in selected:
                    shared.invalidate_success(keys[group["id"]], unless_valid=not force)
            if selected:
                before_gate = len(admissions)
                status, gate_seconds = run_admitted(root, "gate", gate_command(),
                    gate_environment, lambda: check_all(snapshots), timings=admissions,
                    limits=gate_limits, log_dir=cache / "last-logs/gate", revise=recheck_after_admission,
                    verbose=verbose, stop=fail_fast_watch,
                    finalize=finalize_gate, heartbeat=lambda: drain_events(snapshots))
                gate_runs = [event for event in admissions[before_gate:] if event.get("kind") == "gate"]
                gate_started = any(event.get("worker_started") for event in gate_runs)
                if restarts is not None and status == RETRY and not any(event.get("worker_started") for event in gate_runs):
                    # Revalidated at admission and found changed: the gate command was never sent.
                    revoke_publications()
                    raise InputsChanged("inputs changed while the gate was queued")
            if fail_fast_watch is not None and fail_fast_watch.killed:
                append_stopped_gate_log(cache / "last-logs/gate/stderr.log", fail_fast_watch.log_text())
            if (FLAKY_RERUN and flaky_rerun and _action_keys is None and gate_started and telemetry_directory is not None
                    and status == 1 and not (fail_fast_watch and fail_fast_watch.killed)):
                # A build that ran to its end with failures exits 1; a killed or crashed build runner (124, 125, 137,
                # 139, ...) is never rerun (D-DL4-19). The rerun publishes nothing, so the per-action locks go first.
                if action_locks is not None:
                    action_locks.close()
                flaky = rerun_flaky(root, cache, telemetry_directory, selected, metadata, env, snapshots, admissions,
                                    verbose)
                if flaky is not None and flaky["passed"]:
                    # Every failure passed alone (D5). No receipt: the build's own verdict was a failure, so nothing
                    # was published, and none is published now (D-DL4-14).
                    status = 0

        validation_started = time.monotonic()
        stable = check_all(snapshots)
        phases["final_validation_seconds"] = time.monotonic() - validation_started
        if status == 0 and not stable:
            status = RETRY
        if status == 0 and stable and flaky is not None and flaky.get("passed"):
            append_flaky_log(root, flaky["tests"])  # only for a verdict that stands (item 4d)
        if status != 0:
            revoke_publications()
        if restarts is not None and status == RETRY and not stable and not gate_started:
            # Everything was reused or nothing was sent, and the inputs moved: no action started (item 4c).
            raise InputsChanged("inputs changed before the verdict, with no gate action started")
        phases.setdefault("publication_seconds", 0.0)
        # Advisory snapshots describe the last stable request, including failures.
        # They are not successes and never participate in cache authorization.
        if stable:
            for path, summary in summaries.values():
                verification_report.write_summary(path, summary)
        qualification_run = None
        qualification_context = {"common": common, "action_keys": keys, "qualification": qualification_controls}
        if profile == "long-qualification" and status == 0 and stable and not plan.get("configuration", {}).get("filtered"):
            compiler = root / "zig-out/bin/selka"
            qualification_run = stack.enter_context(verification_qualification.qualify(
                root, cache / "long-qualification", compiler, zig, qualification_context, snapshots, **qualification_controls))
            snapshots.extend(qualification_run.additional_snapshots)
            stable = check_all(snapshots)
            if not stable:
                status = RETRY
                revoke_publications()
        if profile == "proofs" and status == 0 and stable and not plan.get("configuration", {}).get("filtered"):
            status = run_proof_profile(root, cache, producer_manifest, env, lambda: check_all(snapshots), admissions, gate_limits, verbose)
            stable = check_all(snapshots)
            if status == 0 and not stable:
                status = RETRY
        elapsed = time.monotonic() - started
        observed_work = max(0.0, elapsed - sum(event["admission_wait_seconds"] for event in admissions)
                            - phases.get("action_lock_wait_seconds", 0.0))
        budget_report = {"scope": "coordinator elapsed excluding admission queues",
                         "observed_seconds": observed_work, "warn_after_seconds": warn_after,
                         "exceeded": warn_after is not None and observed_work > warn_after,
                         "enforced": False}
        selected_ids = {group["id"] for group in selected}
        coverage_rows = []
        for row in results:
            executed = row["id"] in selected_ids
            row["test_telemetry"] = [verification_report.test_timings(
                telemetry_directory / (row["id"] + ".member." + str(index) + ".json")
                if executed and telemetry_directory is not None else None,
                action_id=row["id"], member=verification_telemetry.member_id(row["id"], index))
                for index, _ in enumerate(metadata[row["id"]]["steps"])]
            coverage_rows.append({"id": row["id"], "state":
                row["state"] if row["state"] in ("prepared", "owed") and stable else
                "reused" if row["state"] == "reused" and stable else
                "executed" if executed and status == 0 else "partial" if executed else "outstanding"})
        profile_coverage = verification_profiles.coverage(plan, results, profile_plan["selected"], profile,
            status=status, inputs_stable=stable,
            qualification_required=verification_qualification.OBLIGATIONS if profile == "long-qualification" else [],
            qualification_run=qualification_run if stable else None, qualification_context=qualification_context)
        report_status = status if status != 0 else 0 if profile_coverage["status"] == "complete" else 3
        report = {"version": REPORT_VERSION, "success": report_status == 0, "status": report_status,
                  "long_qualification": None if qualification_run is None else qualification_run.report(),
                  "selected_success": status == 0, "profile_plan": profile_plan, "profile_coverage": profile_coverage,
                  "actions": results, "inputs_stable": stable, "reuse_lookups": reuse_lookups,
                  "subscriptions": subscriptions,
                  "stability_diagnostics": stability_diagnostics(snapshots) if not stable or status == RETRY else None,
                  "shard_plans": common.get("shard_plans"),
                  "action_metadata": plan["action_metadata"],
                  "action_coverage": verification_report.action_coverage(groups, coverage_rows),
                  "budget_context": key({name: value for name, value in common.items() if name != "inventory"}),
                  "build_admitted_seconds": build_seconds, "gate_admitted_seconds": gate_seconds,
                  "admissions": admissions, "timings": phases,
                  "loop_budget": budget_report,
                  "measurement_notes": ["Zig summary steps can overlap and must not be summed",
                                        "per-group execution duration is unavailable for the shared gate",
                                        "common identity changes name digest facets, not individual tool/environment members"],
                  "snapshot_statistics": snapshot_statistics(snapshots),
                  "evidence_store": {"shared": shared is not None, "source": shared_source,
                                     "default_sharing": DEFAULT_SHARING,
                                     "root": str(shared.root if shared is not None else cache / "actions")},
                  "artifact_identities": artifact_report,
                  "declarative_configuration": configuration_notes.get("declarative_configuration"),
                  "relocation_dependent_code": relocation_dependent,
                  "measurement_window_seconds": None if measurement is None else measurement.seconds,
                  "fail_fast": {"requested": fail_fast, "stopped": bool(fail_fast_watch and fail_fast_watch.killed),
                                "beacons": [] if fail_fast_watch is None else fail_fast_watch.names},
                  "elapsed_seconds": elapsed}
        if restarts:
            report["restarts"] = list(restarts)
        if flaky is not None:
            report["flaky"] = flaky
        if disk_waiter is not None and disk_waiter.result is not None:
            report["disk_wait"] = dict(disk_waiter.result)
        if measurement is not None:
            report["measurement_window"] = measurement.report()
        try:
            report["action_budgets"] = verification_budgets.calibrate(
                [report], plan, context=report["budget_context"], action_keys=keys)
        except Exception as error:
            # Advisory evaluation cannot mask the gate verdict or revoke evidence.
            report["action_budgets"] = {"status": "unknown", "enforced": False,
                                       "reason": str(error)[:512]}
        report["scoped_policy"] = verification_budgets.evaluate_scoped_policy(budget_policy, report, plan)
        if report["scoped_policy"]["status"] == "unavailable":
            print("verification: advisory budget policy unavailable: " + report["scoped_policy"]["reason"], file=sys.stderr)
        if measurement is not None:
            measurement.check()
            report["measurement_window"] = measurement.report()
        if early is not None:
            report["cheap_checks"] = early.report()
        diagnostic_record(cache / "last-run.json", report)
        for line in gate_summary.summarize(report=report, log_directory=cache / "last-logs", verbose=verbose, plan=plan):
            print(line, flush=True)
        if fail_fast_watch is not None and fail_fast_watch.killed:
            print("verification: stopped at the first failing step (--fail-fast): the build was ended and the other "
                  "actions' results discarded, so no receipt was recorded for any of them", flush=True)
        if status == RETRY:
            print("verification: inputs changed while queued or running; no new success receipts retained", file=sys.stderr)
            causes = report["stability_diagnostics"]["reasons"]
            if causes:
                print("verification: invalidated input " + json.dumps(causes[0], ensure_ascii=True), file=sys.stderr)
        if budget_report["exceeded"]:
            print("verification: advisory loop budget exceeded: %.3fs > %.3fs (queue excluded)" %
                  (observed_work, warn_after), file=sys.stderr)
        return report_status if report_status >= 0 else 128 - report_status


def cheap_finding_decided(early, results: list[dict]) -> bool:
    """During the cache lookup: whether a finding already belongs to an action this request will run (a registry
    finding always does), so the gate can end before the lookup is over."""
    states = {row["id"]: row["state"] for row in results}
    for finding in early.findings():
        actions = finding_actions(finding)
        if not actions or any(states.get(name) not in (None, "reused", "prepared") for name in actions):
            return True
    return False


SHADOW_SECONDS = 180  # the whole detached shadow run, which ends its own process group there (D-DL4-13)
SHADOW_MAX_NAMES = 50  # failed tests passed by name; more are counted, and the record then leaves `covered` undecided
# Failures the shadow records: only named failing tests, which the edit check's selection could hold or miss. Not a
# cheap finding (no test), an incomplete action (125), changed inputs (75), a gate deadline (124), a cancellation, or a
# failed build or driver that names no test.
SHADOW_STATUSES = (1,)


def failed_test_ids(report: dict, text: str) -> list[str]:
    """The tests a failed gate names: failed or timed-out rows of its telemetry, and failed guest tests of its log."""
    names = [test for _action, test, _state in gate_summary.report_failures(report)]
    for line in gate_summary.guest_test_findings(text):
        match = re.match(r"test (\S+) (?:failed|timed_out|crashed)", line)
        if match:
            names.append(match.group(1))
    return sorted(set(names))


# Decision D5 (the user, 13 November: "Yeah I confirm the flakey test can pass"): a gate whose only failures are a few
# named tests reruns each once, alone, after the build; when all pass alone, the gate passes and names them. False
# restores the strict verdict for every request; `--no-flaky-rerun` does so for one.
FLAKY_RERUN = True
FLAKY_MAX = 5  # more failing tests than this is a broken change, not a flake: no rerun


def flaky_beacon(text: str) -> bool:
    """Whether a `--fail-fast` beacon reports a named test (which the flaky rerun may take up), not a failure that names
    none: a native test's `error: 'NAME' failed|timed out`, or a Python test launcher's driver beacon."""
    first = text.lstrip().splitlines()[0] if text.strip() else ""
    if re.match(r"error: '.+' (?:failed|timed out)", first):
        return True
    return "verification_telemetry" in text and "--action-id" in text and "failed command:" in text


GUEST_SUITE = re.compile(r"selka test (\S+) ")
SUMMARY_LINE = re.compile(r"^Build Summary: ([0-9]+)/([0-9]+) steps succeeded(?: \(([0-9]+) failed\))?(.*)$", re.M)
TROUBLE = re.compile(r"\b[1-9][0-9]* (?:crash|crashed|timeout|timed out|leak|leaked)\b|crash|timed out|leak")
GUEST_OUTCOMES = ("passed", "cached", "skipped", "unsupported", "failed")


def failed_members(text: str) -> tuple[set, list[str]]:
    """The (action, member) pairs the build's tree marks failed (a memory overshoot alone is no failure), and the mark
    lines that report a crash, a timeout or a leak."""
    overshot = {(action, member) for action, member, _peak, _bound in gate_summary.memory_overshoots(text)}
    members, trouble = set(), []
    for line in text.splitlines():
        mark = gate_summary.MEMBER_MARK.search(line)
        if not mark or not gate_summary.FAILED_MEMBER.search(line):
            continue
        pair = (mark.group(1), int(mark.group(2)))
        if pair in overshot:
            continue
        members.add(pair)
        if re.search(r"\b[1-9][0-9]* (?:crash|crashed|timeout|timed out|leak|leaked)\b", line):
            trouble.append(line.strip())
    return members, trouble


def guest_reports(text: str) -> list[list[dict]]:
    """Each `selka test --json` report in the log: its tests."""
    reports = []
    for line in text.splitlines():
        if line.startswith('{"version":"native-tests-v1"'):
            try:
                tests = json.loads(line).get("tests", [])
            except ValueError:
                return reports + [[{"name": "?", "status": "malformed"}]]
            reports.append([test for test in tests if isinstance(test, dict)])
    return reports


def eligible_failures(root: Path, telemetry: Path, selected: list, metadata: dict,
                      text: str) -> tuple[list[dict] | None, str | None]:
    """Item 4d's eligibility, proven and never assumed (D-DL4-19): the failed tests of a gate whose build ran to its
    summary, where every failed member reported every test it ran and the only outcomes that are not passes are those
    named failures. Returns (tests, None), or (None, reason) for a gate that fails as today; the reason is None when
    the gate failed on nothing a rerun could take up."""
    candidates = bool(any(test.get("status") == "failed" for report in guest_reports(text) for test in report))
    for group in selected:
        for index, _step in enumerate(metadata[group["id"]]["steps"]):
            timings = verification_report.test_timings(telemetry / (group["id"] + ".member." + str(index) + ".json"),
                                                       action_id=group["id"],
                                                       member=verification_telemetry.member_id(group["id"], index))
            candidates = candidates or any(test.get("state") in ("failed", "timed_out") for test in timings.get("tests", []))
    if not candidates:
        return None, None  # no test failed: nothing a rerun could take up
    summary = SUMMARY_LINE.findall(text)
    if not summary:
        return None, "the build printed no summary, so it did not run to its end"
    _done, _total, failed_count, tests_line = summary[-1]
    if TROUBLE.search(tests_line):
        return None, "the build's summary counts a crash, a timeout or a leak"
    if "test deadline:" in text or "step deadline:" in text:
        return None, "a deadline killed a test or a step"
    if gate_summary.failed_steps(text):
        return None, "a build step that runs no test failed"
    leftovers = gate_summary.leftover_report(text)
    if leftovers:
        # A failure that came with a process its test left running may be a leak, which a lone rerun would pass over and
        # hide, so there is no rerun; the reason names the process and the test file whose scratch directory it runs in.
        found = next((line for line in leftovers if line.startswith("supervisor: leftover")), leftovers[0])
        owner = gate_summary.leftover_owner(root, leftovers)
        return None, "a process outlived its action (%s)%s" % (
            found[len("supervisor: "):][:260], "; its directory belongs to " + owner if owner else "")
    members, trouble = failed_members(text)
    if trouble:
        return None, "a failed member reports a crash, a timeout or a leak: " + trouble[0][:200]
    if int(failed_count or 0) != len(members):
        return None, "the build counts %s failed steps and its tree marks %d" % (failed_count or 0, len(members))
    found = []
    reports = guest_reports(text)
    for group in selected:
        for index, _step in enumerate(metadata[group["id"]]["steps"]):
            if group["id"] == "language":
                continue
            path = telemetry / (group["id"] + ".member." + str(index) + ".json")
            timings = verification_report.test_timings(path, action_id=group["id"],
                                                       member=verification_telemetry.member_id(group["id"], index))
            rows = [test for test in timings.get("tests", []) if test.get("state") in ("failed", "timed_out")]
            if (group["id"], index) not in members:
                if rows:
                    return None, "%s member %d has failed tests but the build did not mark it" % (group["id"], index)
                continue
            if timings.get("status") != "observed" or not timings.get("complete"):
                return None, "%s member %d did not report every test it ran" % (group["id"], index)
            if any(test.get("state") == "timed_out" for test in rows):
                return None, "%s member %d has a test that timed out" % (group["id"], index)
            if not rows:
                return None, "%s member %d failed with no failed test" % (group["id"], index)
            found += [{"action": group["id"], "member": index, "test": test["test_id"], "state": test["state"]}
                      for test in rows]
    language = sorted(member for action, member in members if action == "language")
    if language:
        if "test-lang guard:" in text:
            return None, "the language guard reported an error"
        steps = (metadata.get("language") or {}).get("steps") or []
        for member in language:
            match = GUEST_SUITE.search(steps[member].get("original_label", "")) if member < len(steps) else None
            if not match:
                return None, "language member %d names no suite" % member
            suite = root / match.group(1)
            owned = [report for report in reports if report and all(
                "::" in test.get("name", "") and any(suite.rglob(test["name"].split("::")[0] + ".selka"))
                for test in report)]
            if len(owned) != 1:
                return None, "language member %d (%s) has %d test reports, not one" % (member, match.group(1), len(owned))
            if any(test.get("status") not in GUEST_OUTCOMES for test in owned[0]):
                return None, "language member %d has a test that neither passed nor failed" % member
            failed = [test for test in owned[0] if test.get("status") == "failed"]
            if not failed:
                return None, "language member %d failed with no failed test" % member
            found += [{"action": "language", "member": member, "test": test["name"], "state": "failed"}
                      for test in failed]
    if not found:
        return None, None
    named = {(item["action"], item["member"]) for item in found}
    if members - named:
        return None, "%s member %d failed with no failed test of its own" % sorted(members - named)[0]
    return found, None


def flaky_failure_lines(text: str, test: str) -> list[str]:
    """The first diagnostic lines the gate log has for one failing test."""
    short = test.split("::")[-1].split(".")[-1]
    for found in gate_summary.failure_details(text):
        if test in found["tests"] or any(short in line for line in found["lines"] + found.get("plain", [])):
            return gate_summary.shown_lines(found)
    return []


def flaky_conditions() -> dict:
    """The machine's state when a flake is logged: load, the disk's pressure and free swap."""
    swap = None
    try:
        for line in Path("/proc/meminfo").read_text().splitlines():
            if line.startswith("SwapFree:"):
                swap = int(line.split()[1])
    except (OSError, ValueError, IndexError):
        pass
    try:
        load = list(os.getloadavg())
    except OSError:
        load = None
    return {"load": load, "full_avg60": disk_pressure(), "swap_free_kb": swap}


FLAKY_PHASE_SECONDS = 30 * 60  # the whole rerun phase: five tests at the per-test idle bound (300 s), with room to start


def rerun_flaky(root: Path, cache: Path, telemetry: Path, selected: list, metadata: dict, env: dict, snapshots,
                admissions: list, verbose: bool) -> dict | None:
    """Item 4d: rerun each failing test of a finished gate once, alone, under the gate's admission, as its launcher ran
    it (`verification_rerun.py`). Returns the record `last-run.json` keeps as `flaky` (each test, whether it passed
    alone, its seconds and first diagnostics), or None when the gate is not eligible (a failure names no test, more than
    FLAKY_MAX failing tests, a step with no record of how it ran)."""
    import verification_rerun
    text = gate_summary.read_logs(cache / "last-logs" / "gate")
    tests, reason = eligible_failures(root, telemetry, selected, metadata, text)
    if tests is None:
        return None if reason is None else {"passed": False, "rerun": False, "reason": reason, "tests": []}
    if len(tests) > FLAKY_MAX:
        return {"passed": False, "rerun": False, "reason": "%d failing tests (more than %d)" % (len(tests), FLAKY_MAX),
                "tests": tests[:FLAKY_MAX]}
    records = verification_rerun.load(telemetry)
    scratch = Path(tempfile.mkdtemp(prefix="flaky-", dir=telemetry))
    steps = []
    for item in tests:
        candidates = ([records.get((item["action"], item["member"]))] if item["member"] is not None else
                      [value for (action, _member), value in sorted(records.items(), key=str) if action == item["action"]])
        step = None
        for number, value in enumerate(candidates):
            if value and item["action"] == "language" and value.get("member") != item["member"]:
                continue
            own = scratch / ("step-%d-%d" % (len(steps), number))
            own.mkdir()
            step = value and verification_rerun.plan(value, item["test"], own)
            if step:
                break
        if not step:
            return None
        steps.append(dict(step, test=item["test"], action=item["action"]))
    plan_path, results_path = scratch / "plan.json", scratch / "results.json"
    plan_path.write_text(json.dumps(steps))
    print("verification: rerunning %d failing test(s) once, alone: %s" % (len(steps), ", ".join(
        item["test"] for item in tests)[:300]), flush=True)
    run_admitted(root, "gate", [sys.executable, str(root / "scripts/verification_rerun.py"), "--plan", str(plan_path),
                                "--results", str(results_path)], env, lambda: check_all(snapshots), timings=admissions,
                 limits=ProcessLimits(FLAKY_PHASE_SECONDS), log_dir=cache / "last-logs/flaky", verbose=verbose,
                 heartbeat=lambda: drain_events(snapshots))
    try:
        results = json.loads(results_path.read_text())
    except (OSError, ValueError):
        results = None
    if not isinstance(results, list) or len(results) != len(tests):
        return {"passed": False, "rerun": True, "reason": "the rerun reported no result", "tests": tests}
    f22 = "si_code=0x80 trap=13" in text and "f3 a4" in text
    rows = []
    for item, result in zip(tests, results):
        rows.append(dict(item, passed=bool(result.get("passed")), seconds=result.get("seconds"), evidence=result.get("evidence"),
                         timed_out=bool(result.get("timed_out")), failure=flaky_failure_lines(text, item["test"])[:3],
                         rerun_output=str(result.get("output", ""))[-600:] if not result.get("passed") else "", f22=f22))
    passed = all(row["passed"] for row in rows)
    return {"passed": passed, "rerun": True, "tests": rows}


def append_flaky_log(root: Path, rows: list[dict]) -> None:
    """One line per test that failed in the gate and passed alone, in the per-user flaky log."""
    import verification_rerun
    try:
        head = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"], capture_output=True, text=True,
                              timeout=30).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        head = None
    conditions = flaky_conditions()
    path = verification_rerun.flaky_log_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a") as handle:
            for row in rows:
                handle.write(json.dumps(dict(conditions, time=time.strftime("%Y-%m-%dT%H:%M:%S"), worktree=str(root),
                                             head=head, action=row["action"], test=row["test"], state=row["state"],
                                             failure=row["failure"], rerun_seconds=row["seconds"], f22=row["f22"])) + "\n")
    except OSError:
        pass  # The log is advice; the verdict stands without it.


def launch_shadow(root: Path, cache: Path) -> str | None:
    """After the gate's verdict, with every snapshot, lease and lock of `execute` released: when it failed on named
    tests, start `edit_check_shadow.py` detached (a session of its own, no pipes) to record whether the edit check's
    selection held them (stage 6), and return the one line to print. The gate does not wait for it or read it, so
    nothing it does can change the exit status, `last-run.json` or the logs; it bounds itself (D-DL4-13)."""
    report = read_record(cache / "last-run.json") or {}
    flaky = report.get("flaky") or {}
    if flaky.get("passed"):
        names = sorted({row["test"] for row in flaky.get("tests", [])})  # flaky tests, held or missed (item 4d)
    elif report.get("status") not in SHADOW_STATUSES:
        return None
    else:
        names = failed_test_ids(report, gate_summary.read_logs(cache / "last-logs"))
    if not names:
        return None
    command = [sys.executable, str(root / "scripts/edit_check_shadow.py"), "--source", "verify_cache",
               "--timeout", str(SHADOW_SECONDS), "--unlisted", str(max(0, len(names) - SHADOW_MAX_NAMES))]
    command += [argument for name in names[:SHADOW_MAX_NAMES] for argument in ("--failed", name)]
    try:
        subprocess.Popen(command, cwd=root, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True, close_fds=True)
    except OSError as error:
        return "verification: could not start the edit check's shadow (%s)" % error
    return "verification: recording whether the edit check would have selected the failing test (%d)" % len(names)


def report_abandoned(early) -> None:
    """One line for the checks still running at the cheap phase's deadline: they decide nothing, and their actions
    decide as always."""
    if early.abandoned:
        print("verification: cheap checks %s passed their %d s deadline and were abandoned; their actions decide"
              % (", ".join(early.abandoned), gate_cheap_checks.PHASE_SECONDS), file=sys.stderr, flush=True)


def finding_actions(finding) -> tuple:
    """The gate action one finding stands for (each finding names its action, so the input-coverage command
    `coverage_self` is not `coverage`); none for the registry, which no receipt covers."""
    return () if finding.check == "registry" else (finding.check,)


def cheap_findings_that_count(early, results: list[dict]) -> bool:
    """Whether a cheap check has a finding for an action this request will run, decided finding by finding. A finding
    whose actions were all reused from a prior success leaves that success standing (and is reported as a warning): the
    cheap checks change when a gate fails, never whether it does."""
    reused = {row["id"] for row in results if row["state"] in ("reused", "prepared")}
    for name, found in list(early.results.items()):
        kept = []
        for finding in found:
            actions = set(finding_actions(finding))
            if actions and actions <= reused:
                print("verification: warning: cheap check %s fails but its action was reused from a prior success; "
                      "an input it reads may be undeclared: %s" % (finding.check, finding.location or finding.message),
                      file=sys.stderr)
            else:
                kept.append(finding)
        early.results[name] = kept
    return bool(early.findings())


def cheap_check_failure(cache: Path, early, snapshots, results: list[dict], admissions: list, phases: dict,
                        started: float, verbose: bool) -> int:
    """End the gate on a cheap check's findings, before any test action: report and record them; no receipt."""
    early.wait()
    report_abandoned(early)
    if not check_all(snapshots):
        raise InputsChanged("inputs changed during the cheap checks")
    elapsed = time.monotonic() - started
    record = early.report()
    findings = early.findings()
    first = elapsed if early.first_finding_at is None else early.first_finding_at - started
    record["first_finding_gate_seconds"] = round(first, 3)
    diagnostic_record(cache / "last-run.json", {"version": REPORT_VERSION, "success": False, "status": 1,
        "stage": "cheap_checks", "cheap_checks": record, "actions": results, "admissions": admissions,
        "timings": phases, "stability_diagnostics": stability_diagnostics(snapshots), "elapsed_seconds": elapsed})
    write_cheap_log(cache / "last-logs", findings)
    print("verification: FAIL; in %.1f s; a cheap check failed before any test action started (its first finding "
          "at %.1f s); no receipt was recorded; log: %s" % (elapsed, first, cache / "last-run.json"), flush=True)
    for line in gate_cheap_checks.summary_lines(findings, gate_summary.MAX_RED_LINES - 2):
        print(line, flush=True)
    return 1


def empty_logs(directory: Path) -> None:
    """Empty a log directory's files when its build does not run in this request, so that `gate_summary.py` on
    `last-logs` reads only this run (a failed preparation log left from an earlier run would make a green run read red)."""
    for name in ("stdout.log", "stderr.log"):
        path = directory / name
        try:
            if path.exists() and path.stat().st_size:
                path.write_text("")
        except OSError:
            pass  # Diagnostic storage never decides the verdict.


def write_cheap_log(logs: Path, findings) -> None:
    """Leave the findings where `gate_summary.py .selka-cache/verification-v3/last-logs` reads them, in the build
    runner's block shape (`verification action <id> member 0 failure`, its lines, `failed command:`), and empty the
    gate's logs: no gate build ran, so an older run's logs must not be read as this one's."""
    try:
        empty_logs(logs / "gate")
        (logs / "cheap").mkdir(parents=True, exist_ok=True)
        checks = len({finding.check for finding in findings})
        text = ["Build Summary: 0/%d steps succeeded (%d failed); cheap checks, before any test action" % (checks, checks)]
        for finding in findings:
            text.append("verification action %s member 0 failure" % finding.check)
            text.append(finding.message if not finding.location or finding.message.startswith(finding.location)
                        else "%s: %s" % (finding.location, finding.message))
            text += finding.lines
            text.append("failed command: cheap check %s" % finding.check)
        (logs / "cheap" / "stderr.log").write_text("\n".join(text) + "\n")
    except OSError:
        pass  # Diagnostic storage never decides the verdict.


def print_failure_record(path: Path, error: str) -> None:
    """After the one-line error of a run that raised: what its `last-run.json` adds when it records this error (the
    first changed input of an `inputs changed` failure), from the same reader as every summary."""
    record = read_record(path)
    if not record or record.get("error") != error or record.get("status") != RETRY:
        return
    for line in gate_summary.unnamed_failure(record, "")[:3]:
        print("verification: " + line, file=sys.stderr)


def print_preparation_failure(cache: Path, admissions: list) -> None:
    """Name the step that failed a preparation build (a compile error, a failed install) from that build's own log,
    before `main` prints the coordinator's one-line error. Nothing is printed when no preparation build ran."""
    if not admissions or admissions[-1].get("kind") != "build":
        return
    logs = [Path(entry["path"]).parent for entry in admissions[-1].get("logs", []) if entry.get("path")]
    if not logs:
        # No recorded log paths: the newer of the two preparation builds' log directories.
        candidates = [path for path in (cache / "last-logs/inventory", cache / "last-logs/preparation")
                      if (path / "stderr.log").is_file()]
        logs = sorted(candidates, key=lambda path: (path / "stderr.log").stat().st_mtime)[-1:]
    if not logs:
        return
    lines = gate_summary.summarize(log_directory=logs[0])
    if lines[0].startswith("verification: PASS"):
        return
    for line in lines[1:gate_summary.MAX_RED_LINES]:
        print(line, flush=True)


# Item 4f: before it asks for admission, a gate waits while the disk is saturated (root's nightly backup held `full
# avg60` near 60% for hours on 13 November and every overlapping gate failed). The 90-minute gate deadline counts from
# the gate command's start (queue and this wait excluded), so waiting cannot make a gate miss it.
PRESSURE_FILE = Path("/proc/pressure/io")
DISK_PRESSURE_LIMIT = 25.0  # `full avg60` (percent) above which the gate waits
DISK_WAIT_SECONDS = 20 * 60  # the longest it waits before it starts anyway
DISK_POLL_SECONDS = 5.0


def disk_pressure(path: Path | None = None) -> float | None:
    """The disk's `full avg60` pressure in percent, or None without pressure accounting."""
    try:
        text = (path or PRESSURE_FILE).read_text()
    except OSError:
        return None
    match = re.search(r"^full\b.*\bavg60=([0-9.]+)", text, re.M)
    return float(match.group(1)) if match else None


def wait_for_disk(*, limit: float | None = None, bound: float | None = None, poll: float | None = None,
                  clock=time.monotonic, sleep=time.sleep) -> dict:
    """Wait while the disk's pressure is above `limit`, at most `bound` seconds: one line when the wait starts and one
    when it ends (calm, or past the bound, when the gate starts anyway under pressure). Returns what `last-run.json`
    records as `disk_wait`."""
    limit = DISK_PRESSURE_LIMIT if limit is None else limit
    bound = DISK_WAIT_SECONDS if bound is None else bound
    poll = DISK_POLL_SECONDS if poll is None else poll
    started = clock()
    first = pressure = disk_pressure()
    if pressure is not None and pressure > limit:
        print("verification: waiting for the disk before asking for admission: full avg60 %.1f%% > %.0f%% (another "
              "process, such as the nightly backup, saturates it); at most %.0f min" % (pressure, limit, bound / 60),
              flush=True)
    while pressure is not None and pressure > limit:
        if clock() - started >= bound:
            print("verification: the disk is still saturated (full avg60 %.1f%%) after %.0f s; starting under disk "
                  "pressure" % (pressure, clock() - started), flush=True)
            return {"seconds": clock() - started, "gave_up": True, "first": first, "last": pressure, "limit": limit}
        sleep(poll)
        pressure = disk_pressure()
    if first is not None and first > limit:
        print("verification: the disk is calm (full avg60 %.1f%%) after %.0f s; asking for admission"
              % (pressure if pressure is not None else 0.0, clock() - started), flush=True)
    return {"seconds": clock() - started, "gave_up": False, "first": first, "last": pressure, "limit": limit}


class DiskWaiter:
    """The disk wait of one request, done lazily: called immediately before each admission the request really needs,
    it waits the first time only, so a request that needs no admission (everything reused) never waits."""

    def __init__(self, enabled: bool = True):
        self.enabled = enabled
        self.result = None

    def __call__(self) -> None:
        if self.enabled and self.result is None:
            self.result = wait_for_disk()


MAX_RESTARTS = 2  # new snapshots one request may take after inputs changed before any action (item 4c)
# Decision D4 (13 November, the coordinator; to be confirmed by the user): a changed tool on PATH restarts the request
# like any other changed input. False makes such a change fail the request as before; it is the only difference.
RESTART_ON_TOOL_CHANGE = True


def changed_inputs(record: dict | None) -> list[dict]:
    """The changed inputs a failure record names (`stability_diagnostics`): each watched path's role, name and reason,
    in order, without the watcher closures that follow them."""
    reasons = (((record or {}).get("stability_diagnostics") or {}).get("reasons") or [])
    named, seen = [], set()
    for reason in reasons:
        if not isinstance(reason, dict) or reason.get("facet") == "authority" or reason.get("name") in (None, "None"):
            continue
        if reason["name"] not in seen:
            seen.add(reason["name"])
            named.append(reason)
    return named


def loaded_code_paths() -> set[str]:
    """The files this coordinator runs from: its loaded Python modules and its interpreter. A change to one cannot be
    taken up by a restart in this process, which keeps the code it loaded."""
    paths = {os.path.realpath(sys.executable)}
    for module in list(sys.modules.values()):
        name = getattr(module, "__file__", None)
        if name:
            paths.add(os.path.realpath(name))
    return paths


def restartable(error: BaseException, changed: list[dict], root: Path = ROOT) -> bool:
    """Whether a failure is a change of inputs before any gate action started, so a new snapshot may carry on: an
    `InputsChanged`, or an input watch that tripped before a gate command was sent. A changed tool counts as any other
    input while RESTART_ON_TOOL_CHANGE holds (D4, confirmed by the user); a change to the coordinator's own loaded code
    or interpreter never restarts in this process."""
    if isinstance(error, SnapshotError):
        if getattr(error, "verification_action_started", True) or not changed:
            return False
    elif not isinstance(error, InputsChanged):
        return False
    loaded = loaded_code_paths()
    if any(os.path.realpath(os.path.join(root, reason["name"])) in loaded for reason in changed):
        return False
    return RESTART_ON_TOOL_CHANGE or not any(reason.get("role") == "tools" for reason in changed)


def execute_with_restarts(root: Path, cache: Path, *arguments, **options) -> int:
    """`execute`, started again with a new snapshot when its inputs change before any gate action started, at most
    MAX_RESTARTS times; a third change fails the request with every changed path. Nothing of an abandoned attempt is
    used: each attempt takes its own snapshots, keys, preparation decision, cheap checks and admission, and reuses only
    records keyed by content (the inventory, preparation and digest records, action receipts), which it checks against
    its own snapshot."""
    restarts = []
    while True:
        try:
            status = execute(root, cache, *arguments, restarts=restarts, **options)
        except (InputsChanged, SnapshotError) as error:
            record = read_record(cache / "last-run.json")
            changed = changed_inputs(record)
            if not restartable(error, changed, root):
                raise
            first = changed[0] if changed else {"name": "an input the watch did not name", "reason": str(error)}
            restarts.append({"path": first["name"], "reason": first.get("reason"), "role": first.get("role"),
                             "error": str(error)})
            paths = ", ".join(item["path"] for item in restarts)
            if len(restarts) > MAX_RESTARTS:
                if record is not None:
                    diagnostic_record(cache / "last-run.json", dict(record, restarts=list(restarts)))
                raise VerificationError("inputs changed %d times before any action started (%s): something is "
                                        "editing the tree" % (len(restarts), paths), RETRY) from None
            print("verification: %s changed before any action started (%s); taking a new snapshot, restart %d of %d"
                  % (first["name"], str(error), len(restarts), MAX_RESTARTS), flush=True)
            continue
        if not options.get("dry_run") and options.get("_action_keys") is None:
            line = launch_shadow(root, cache)
            if line:
                print(line, flush=True)
        return status


def append_stopped_gate_log(path: Path, text: str) -> None:
    """Add the failure blocks of a gate ended by `--fail-fast` to the gate's own standard-error log.

    The pinned build runner prints its failure report only when every step is over, so the build this coordinator ended printed
    none; the beacons the failing steps left hold what that report would have said, in the same shape, and the summary reads them
    from the log as it reads the report. The marker line (`gate_summary.FAIL_FAST_MARKER`) tells the summary that nothing the
    killed build printed before it belongs to those blocks. The log is the capped file the supervisor wrote; a failed append
    loses only detail.
    """
    try:
        with path.open("a", encoding="utf-8") as log:
            log.write("\n" + gate_summary.FAIL_FAST_MARKER + "\n" + text)
    except OSError:
        pass  # Diagnostic storage never authorizes or prevents verification.


def parse_options(options: list[str]) -> list[str]:
    """Only full-gate build controls; no target, prefix, cache-root or runner overrides."""
    if options[:1] == ["--"]:
        options = options[1:]
    shard_plan_files(options)  # Every accepted plan is a watched required file.
    allowed_values = {"--maxrss", "--summary"}
    index = 0
    while index < len(options):
        arg = options[index]
        if arg in allowed_values:
            index += 1
            if index >= len(options) or options[index].startswith("-"):
                raise VerificationError("missing value for " + arg)
        elif not (arg.partition("=")[0] in SHARD_PLAN_OPTIONS
                  or re.fullmatch(r"-j[1-9][0-9]*", arg)
                  or re.fullmatch(r"--seed=(0x[0-9a-fA-F]+|[0-9]+)", arg) or re.fullmatch(
                r"-D(optimize|test-shards|core-shards|test-rerun|test-filter)=[^\x00]+", arg)
                  or re.fullmatch(r"-Dgolden-shards=[1-4]", arg)):
            raise VerificationError("unsupported verification build option: " + arg)
        index += 1
    # Pinned Maker -jN limits worker threads, excluding its eager main thread.
    # Reserve that main-thread lane. For one CPU, omit -j: Threaded's default
    # async_limit is CPUs-1=0, whereas explicit -j1 could run two root tasks.
    # Admission can narrow affinity afterwards; its child must cap this value
    # again against the actual admitted set before starting Zig.
    if not any(re.fullmatch(r"-j[1-9][0-9]*", arg) for arg in options):
        cpus = len(os.sched_getaffinity(0))
        if cpus == 0:
            raise VerificationError("verification requires at least one allowed CPU")
        if cpus > 1:
            options += ["-j" + str(cpus - 1)]
    # The pinned Maker omits RSS charges when resuming blocked steps, so the
    # 8 GiB request is not a qualified aggregate memory bound.
    if "--maxrss" not in options:
        options += ["--maxrss", "8589934592"]
    if "--summary" not in options:
        options += ["--summary", "all"]
    if not any(arg.startswith("--seed=") for arg in options):
        options += ["--seed=0"]
    return options


def native_default_sharing(root: Path = ROOT) -> bool:
    """The compiler's rollout switch, `default_sharing` in src/shared_cache_policy.zig."""
    try:
        text = (root / "src/shared_cache_policy.zig").read_text()
    except OSError:
        return False
    return re.search(r"^pub const default_sharing = true;", text, re.MULTILINE) is not None


def native_store_roots(environment: Mapping[str, str], default_sharing: bool) -> list[Path]:
    """The native shared store roots ENVIRONMENT selects, as the compiler resolves
    them: a set variable names a store and an empty one disables it; an unset one
    selects `$XDG_CACHE_HOME/selka/<leaf>` or `~/.cache/selka/<leaf>` only while
    the compiler's default sharing is on."""
    roots = []
    for name, leaf in zip(NATIVE_SHARED_VARIABLES, ("compiler-artifacts", "native-tests")):
        value = environment.get(name)
        if value is not None:
            if value:
                roots.append(Path(value))
            continue
        if not default_sharing:
            continue
        base = environment.get("XDG_CACHE_HOME") or ""
        if not os.path.isabs(base):
            home = environment.get("HOME") or ""
            base = os.path.join(home, ".cache") if os.path.isabs(home) else ""
        if base:
            roots.append(Path(base) / "selka" / leaf)
    return roots


def mismatch_logs(environment: Mapping[str, str], default_sharing: bool = False) -> list[Path]:
    """Every `mismatches.log` of the native shared stores ENVIRONMENT selects.

A store logs one line per determinism mismatch in its namespace directory
(`<root>/<namespace>/mismatches.log`).
"""
    logs = []
    for root in native_store_roots(environment, default_sharing):
        logs.extend(sorted(root.glob("*/mismatches.log")))
    return logs


def mismatch_counts(environment: Mapping[str, str], default_sharing: bool = False) -> dict[str, int]:
    """Non-blank lines per mismatch log of the stores ENVIRONMENT selects."""
    counts = {}
    for path in mismatch_logs(environment, default_sharing):
        try:
            counts[str(path)] = sum(1 for line in path.read_text(errors="replace").splitlines() if line.strip())
        except OSError:
            counts[str(path)] = 0
    return counts


def mismatch_verdict(before: Mapping[str, int], after: Mapping[str, int]) -> dict:
    """D3: fail when any used store's log grew during the request or is non-empty. An integration request judges its own
    stores with it (`own_stores`), which start empty, so any line is one this request's builds logged."""
    grew = {path: count - before.get(path, 0) for path, count in after.items() if count > before.get(path, 0)}
    nonzero = {path: count for path, count in after.items() if count}
    return {"logs": dict(after), "grew": grew, "nonzero": nonzero, "passed": not grew and not nonzero}


def own_stores(cache: Path, directory: str = "integration") -> Path:
    """D-NIGHTLY-2: a fresh directory under `<cache>/integration` (`<cache>/gate-stores` for an ordinary request, GATE3)
    holding an empty compiler store and an empty test store for one request. Stores an earlier request kept (it failed) are
    removed first: the coordinator lock serializes requests of a checkout, and the record of that request kept the mismatch
    lines."""
    parent = cache / directory
    parent.mkdir(parents=True, exist_ok=True)
    for old in sorted(parent.glob("stores-*")):
        shutil.rmtree(old, ignore_errors=True)
    base = Path(tempfile.mkdtemp(prefix="stores-", dir=parent))
    for _, leaf in OWN_STORE_LEAVES:
        (base / leaf).mkdir()
    return base


def own_store_environment(base: Path) -> dict[str, str]:
    """The variables that point a request's builds at the own stores under BASE (placement variables: no key changes)."""
    return {name: str(base / leaf) for name, leaf in OWN_STORE_LEAVES}


def request_store_environment(base: Path, caller: Mapping[str, str]) -> dict[str, str]:
    """The own-store variables of a request whose caller's environment is CALLER: a store the caller named (an empty
    value disables it) stays the caller's, as the stage store does, so only the unnamed ones are pointed at BASE."""
    return {name: value for name, value in own_store_environment(base).items() if name not in caller}


def per_user_store_roots(caller: Mapping[str, str]) -> dict[str, Path]:
    """The user's default compiler and test stores a build of CALLER's environment would open by default, by variable: the
    ones whose variable the caller left unset (`stage_store_root` resolves the same way for the stage store)."""
    roots = {}
    base = caller.get("XDG_CACHE_HOME") or ""
    if not os.path.isabs(base):
        home = caller.get("HOME") or ""
        base = os.path.join(home, ".cache") if os.path.isabs(home) else ""
    for (name, _), leaf in zip(OWN_STORE_LEAVES, ("compiler-artifacts", "native-tests")):
        if name not in caller and base:
            roots[name] = Path(base) / "selka" / leaf
    return roots


def lock_holders(text: str) -> list[tuple[int, int]]:
    """The (process, inode) of every lock `/proc/locks` lists in TEXT, a waiting one included: a line reads
    `N: [-> ]KIND ADVISORY|MANDATORY MODE PID MAJOR:MINOR:INODE START END`. A row that does not parse is skipped."""
    rows = []
    for line in text.splitlines():
        found = re.search(r"\s(\d+)\s+[0-9a-f]+:[0-9a-f]+:(\d+)\s+\S+\s+\S+\s*$", line)
        if found:
            rows.append((int(found.group(1)), int(found.group(2))))
    return rows


def process_identity(pid: int, proc: str = "/proc") -> tuple[int, str] | None:
    """The parent and the start time of process PID from `<proc>/<pid>/stat`, or None when it is gone or unreadable. The
    command name may hold spaces and parentheses, so the fields are counted from its last closing parenthesis."""
    try:
        with open("%s/%d/stat" % (proc, pid), "rb") as handle:
            text = handle.read().decode(errors="replace")
    except OSError:
        return None
    fields = text[text.rfind(")") + 2:].split()
    if len(fields) < 20:
        return None
    return int(fields[1]), fields[19]


def descends_from(pid: int, ancestor: int, proc: str = "/proc") -> bool:
    """Whether process PID is ANCESTOR or one of its descendants, by the parent chain in `<proc>`."""
    for _ in range(256):
        if pid == ancestor:
            return True
        found = process_identity(pid, proc)
        if found is None or found[0] <= 1:
            return False
        pid = found[0]
    return False


class StoreLeaseWatch:
    """GATE3's guard for the user's default compiler and test stores (item 1 of the brief): every process that opens one of
    them holds a shared flock on `<store>/<namespace>/.retention.lock` for as long as it builds (a program's work claim lasts
    the whole build), and `/proc/locks` names the holder. The watch samples that table every INTERVAL seconds from a thread
    and keeps each holder that is the request's own process or a descendant of it (the coordinator, then its admitted child,
    then every build and test). A holder of another checkout's is no finding. The compiler the component builder runs is no
    exception since GATE3B: `selfhost/components.zig` passes the store locations through to it. The guard cannot see a
    process that holds the lease for less than one interval; builds hold it for their whole run, and the NIGHTLY lane's own sampler saw the leases
    held in 15% of its 0.5 s samples by every user process together. Inodes are matched without the device number: the
    table prints the superblock's, which `stat` does not always report (btrfs subvolumes); an inode of another file system
    that equals a lease file's and is locked by this request is not a case this machine has."""

    def __init__(self, roots: Mapping[str, Path], ancestor: int | None = None, interval: float = LEASE_SAMPLE_SECONDS,
                 locks: str = "/proc/locks", proc: str = "/proc"):
        self.roots, self.interval, self.locks, self.proc = dict(roots), interval, locks, proc
        self.ancestor = os.getpid() if ancestor is None else ancestor
        self.samples, self.offenders, self.known = 0, {}, {}
        self.stop, self.thread = threading.Event(), None

    def lease_files(self) -> dict[int, tuple[str, str]]:
        """inode -> (variable, path) of each `.retention.lock` under the watched roots, found now (a namespace appears when
        a first build creates it)."""
        found = {}
        for name, root in self.roots.items():
            try:
                namespaces = [entry for entry in os.scandir(root) if entry.is_dir(follow_symlinks=False)]
            except OSError:
                continue
            for entry in namespaces:
                path = os.path.join(entry.path, LEASE_FILE)
                try:
                    found[os.stat(path).st_ino] = (name, path)
                except OSError:
                    continue
        return found

    def own_process(self, pid: int) -> bool:
        """Whether PID descends from the request; a verdict is kept for the process's start time, since a number is reused."""
        identity = process_identity(pid, self.proc)
        if identity is None:
            return False
        key = (pid, identity[1])
        if key not in self.known:
            self.known[key] = descends_from(pid, self.ancestor, self.proc)
        return self.known[key]

    def sample(self) -> list[dict]:
        """Read the lock table once; the holders of a watched lease file that belong to this request are recorded and
        returned."""
        self.samples += 1
        targets = self.lease_files()
        if not targets:
            return []
        try:
            with open(self.locks) as handle:
                rows = lock_holders(handle.read())
        except OSError:
            return []
        found = []
        for pid, inode in rows:
            if inode in targets and self.own_process(pid):
                variable, path = targets[inode]
                command = self.command(pid)
                row = {"pid": pid, "variable": variable, "lease": path, "command": command[:200]}
                found.append(row)
                if len(self.offenders) < LEASE_OFFENDERS_KEPT:
                    self.offenders.setdefault((pid, path), row)
        return found

    def command(self, pid: int) -> str:
        """The command line of PID, its arguments joined by spaces."""
        try:
            with open("%s/%d/cmdline" % (self.proc, pid), "rb") as handle:
                return handle.read().replace(b"\0", b" ").decode(errors="replace").strip()
        except OSError:
            return ""

    def run(self) -> None:
        while not self.stop.wait(self.interval):
            try:
                self.sample()
            except (OSError, ValueError):
                continue

    def __enter__(self) -> "StoreLeaseWatch":
        self.thread = threading.Thread(target=self.run, name="store-lease-watch", daemon=True)
        self.thread.start()
        return self

    def close(self) -> None:
        """Stop the sampler (idempotent); one last sample is taken after it ends."""
        if self.stop.is_set():
            return
        self.stop.set()
        if self.thread is not None:
            self.thread.join(timeout=5)
        try:
            self.sample()
        except (OSError, ValueError):
            pass

    def __exit__(self, *exc) -> None:
        self.close()

    def verdict(self) -> dict:
        """The guard's verdict: the watched roots, the samples taken and each holder found."""
        return {"roots": {name: str(root) for name, root in self.roots.items()}, "samples": self.samples,
                "holders": list(self.offenders.values()), "passed": not self.offenders}


def tree_size(root: Path) -> dict:
    """Bytes and files under ROOT, symbolic links not followed."""
    size, files = 0, 0
    for directory, _, names in os.walk(root):
        for name in names:
            try:
                size += os.lstat(os.path.join(directory, name)).st_size
            except OSError:
                continue
            files += 1
    return {"bytes": size, "files": files}


def mismatch_excerpt(paths, limit: int = MISMATCH_LINES_KEPT) -> dict[str, list[str]]:
    """The first LIMIT non-blank lines of each mismatch log in PATHS: `mismatch <kind> <key> existing=<digest>
    attempted=<digest>`, the store's key and both digests."""
    excerpt = {}
    for path in paths:
        try:
            lines = [line for line in Path(path).read_text(errors="replace").splitlines() if line.strip()]
        except OSError:
            continue
        if lines:
            excerpt[str(path)] = lines[:limit]
    return excerpt


def per_user_mismatch_report(before: Mapping[str, int], after: Mapping[str, int], previous: Mapping[str, int] | None) -> dict:
    """The per-user (or caller-named) stores' mismatch logs as counts, never a verdict: lines now, lines added during the
    request (other processes of the user's write them too) and, when the last integration request of this checkout
    recorded them, lines added since then."""
    report = {}
    for path, count in sorted(after.items()):
        since = None if previous is None or path not in previous else count - previous[path]
        report[path] = {"lines": count, "during_request": count - before.get(path, 0), "since_last_request": since}
    return report


def previous_per_user_counts(record: Mapping | None) -> dict[str, int] | None:
    """The per-user mismatch-log counts the previous integration record holds: `per_user_mismatches` since D-NIGHTLY-1,
    or the older record's `shared_mismatches.logs`, which counted the same per-user logs."""
    if not isinstance(record, Mapping):
        return None
    rows = record.get("per_user_mismatches")
    if isinstance(rows, Mapping):
        return {path: row["lines"] for path, row in rows.items() if isinstance(row, Mapping) and isinstance(row.get("lines"), int)}
    old = record.get("shared_mismatches")
    if isinstance(old, Mapping) and isinstance(old.get("logs"), Mapping) and record.get("own_stores") is None:
        return {path: count for path, count in old["logs"].items() if isinstance(count, int)}
    return None


RERUN_LINE = re.compile(r"test-lang-rerun: (\S+): (.*)")


def two_run_step(root: Path, zig: Path, environment: Mapping[str, str], run=subprocess.run, admission=None) -> dict:
    """D-NIGHTLY-3 (GATE-2): `zig build test-lang-rerun` once, under one gate admission and in ENVIRONMENT (the request's,
    own stores included; the stage store is the empty name unless the caller named one). The step runs each language suite
    twice in one fresh work directory, the second forced, and names every test whose verdict changed or that is unsupported."""
    if admission is None:
        import build_admission
        admission = build_admission.admission
    child = dict(environment)
    child.setdefault(STAGE_VARIABLE, "")
    argv = [str(zig), "build", "test-lang-rerun"]
    started = time.monotonic()
    with admission("gate"):
        completed = run(argv, cwd=root, env=child, capture_output=True, text=True, errors="replace")
    seconds = round(time.monotonic() - started, 1)
    suites, problems = {}, []
    for line in (completed.stdout + "\n" + completed.stderr).splitlines():
        found = RERUN_LINE.fullmatch(line.strip())
        if found is None:
            continue
        if found.group(2) == "ok" or re.fullmatch(r"\d+ problems", found.group(2)):
            suites[found.group(1)] = found.group(2)
        else:
            problems.append(found.group(1) + ": " + found.group(2))
    passed = completed.returncode == 0 and not problems
    if not passed and not problems:
        problems.append("`zig build test-lang-rerun` exited %d: %s" % (
            completed.returncode, " | ".join(completed.stderr.strip().splitlines()[-3:])[-600:]))
    return {"argv": argv[1:], "exit": completed.returncode, "seconds": seconds, "suites": suites,
            "problems": problems[:50], "passed": passed}


def stage_store_root(environment: Mapping[str, str]) -> Path | None:
    """The per-user stage store ENVIRONMENT's compiler would open by default, or None when the caller named a store or
    disabled it (the variable is set) or no home directory is known: `$XDG_CACHE_HOME/selka/stage-artifacts`, else
    `~/.cache/selka/stage-artifacts`."""
    if STAGE_VARIABLE in environment:
        return None
    base = environment.get("XDG_CACHE_HOME") or ""
    if not os.path.isabs(base):
        home = environment.get("HOME") or ""
        base = os.path.join(home, ".cache") if os.path.isabs(home) else ""
    return Path(base) / "selka" / "stage-artifacts" if base else None


def stage_store_fingerprint(root: Path) -> dict:
    """The number of files under ROOT and the newest modification time (nanoseconds) of any file or directory there. A report
    of what changed; it does not say who changed it (any build of the user's writes the store)."""
    files, newest, stack = 0, 0, [root]
    try:
        newest = root.stat().st_mtime_ns
    except OSError:
        return {"root": str(root), "exists": False, "files": 0, "newest_ns": 0}
    while stack:
        try:
            with os.scandir(stack.pop()) as entries:
                for entry in entries:
                    try:
                        info = entry.stat(follow_symlinks=False)
                    except OSError:
                        continue
                    newest = max(newest, info.st_mtime_ns)
                    if entry.is_dir(follow_symlinks=False):
                        stack.append(entry.path)
                    else:
                        files += 1
        except OSError:
            continue
    return {"root": str(root), "exists": True, "files": files, "newest_ns": newest}


def stage_store_roots(root: Path) -> dict[str, int]:
    """The live-root files of the stage store ROOT with their modification times: a build that publishes to the store writes
    one when it finishes, naming its work directory, so a root that is new or rewritten between two snapshots is a build
    that ran between them."""
    found = {}
    try:
        with os.scandir(root / "stage-artifacts-v1" / "roots") as entries:
            for entry in entries:
                if entry.name.endswith(".live"):
                    try:
                        found[entry.name] = entry.stat(follow_symlinks=False).st_mtime_ns
                    except OSError:
                        continue
    except OSError:
        pass
    return found


def stage_store_snapshot(root: Path) -> dict:
    """The stage store ROOT's fingerprint and live roots, taken together."""
    return {"fingerprint": stage_store_fingerprint(root), "roots": stage_store_roots(root)}


def stage_store_work(root: Path, name: str) -> str | None:
    """The work directory the live-root file NAME of the stage store ROOT names, or None for a file that is not a root."""
    try:
        data = (root / "stage-artifacts-v1" / "roots" / name).read_bytes()
    except OSError:
        return None
    start = len(LIVE_ROOT_MAGIC) + 4
    if not data.startswith(LIVE_ROOT_MAGIC) or len(data) < start:
        return None
    length = int.from_bytes(data[len(LIVE_ROOT_MAGIC):start], "little")
    return data[start:start + length].decode(errors="replace")


def stage_store_writers(root: Path, before: Mapping[str, int], trees: list[Path]) -> list[str]:
    """The work directories under any of TREES that live roots of the stage store ROOT name, for roots that are new or were
    rewritten since the BEFORE listing: the builds of this request's own processes (its checkout holds their work directories)."""
    found = []
    for name, mtime in sorted(stage_store_roots(root).items()):
        if before.get(name) == mtime:
            continue
        work = stage_store_work(root, name)
        if work is not None and any(work == str(tree) or work.startswith(str(tree) + os.sep) for tree in trees):
            found.append(work)
    return found


def stage_store_verdict(before: Mapping[str, object], after: Mapping[str, object], writers: list[str]) -> dict:
    """The stage-store guard's verdict. It fails only for WRITERS, the request's own builds; a changed fingerprint alone is a
    report (another process of the user's may write the store while a request runs)."""
    changed = {key: [before.get(key), after.get(key)] for key in ("exists", "files", "newest_ns") if before.get(key) != after.get(key)}
    return {"root": after.get("root"), "before": dict(before), "after": dict(after), "changed": changed,
            "checkout_writers": writers[:20], "passed": not writers}


def prepare_gate_stores(cache: Path, mode: str, caller: Mapping[str, str]) -> dict | None:
    """GATE3: the own stores of an ordinary request in MODE (`fresh`; `off` is None), as the plan the request runs under:
    the base directory, the variables it names for its workers and the user's default stores it guards. Stores an earlier
    request kept are removed first."""
    if mode == "off":
        return None
    base = own_stores(cache, GATE_STORES_DIRECTORY)
    guarded = per_user_store_roots(caller)
    return {"mode": mode, "base": base, "environment": request_store_environment(base, caller), "guarded": guarded}


def finish_gate_stores(cache: Path, plan: dict, watch: StoreLeaseWatch, status: int) -> int:
    """GATE3: judge a finished request that ran against own stores. A mismatch one of the own stores logged is the
    integration gate's status 5 (two producers of this request wrote different bytes under one key); a build of the request
    that held a lease on a default per-user store is the stage store's status 6. A request that failed for another reason keeps
    its status and the findings are printed as notes. The stores are removed at the end, and kept only when they hold a
    finding (a mismatch log to read), until the checkout's next request removes them: a failing test leaves nothing behind, a
    gate's stores being about a gigabyte. The outcome goes into `last-run.json` as `own_stores`."""
    mismatches = mismatch_verdict({}, mismatch_counts(plan["environment"]))
    lease = watch.verdict()
    final = status
    if status == 0 and not mismatches["passed"]:
        final = INTEGRATION_MISMATCH_STATUS
    elif status == 0 and not lease["passed"]:
        final = STAGE_STORE_STATUS
    findings = not mismatches["passed"] or not lease["passed"]
    kept = findings
    size = tree_size(plan["base"])
    record = {"mode": plan["mode"], "root": str(plan["base"]), "named": sorted(plan["environment"]), "kept": kept,
              "files": size["files"], "bytes": size["bytes"], "mismatches": mismatches,
              "mismatch_lines": mismatch_excerpt(mismatches["nonzero"]), "lease_guard": lease}
    label = "FAIL" if status == 0 else "NOTE"
    for path, lines in record["mismatch_lines"].items():
        print("verification: %s: the request's own store logged a determinism mismatch: %s:\n  %s" % (
            label, path, "\n  ".join(lines)), file=sys.stderr)
    for holder in lease["holders"][:5]:
        print("verification: %s: a build of this request opened the per-user store (%s): pid %d, %s" % (
            label, holder["lease"], holder["pid"], holder["command"] or "command unknown"), file=sys.stderr)
    report = read_record(cache / "last-run.json") or {}
    if report:
        report["own_stores"] = record
        if final != status:
            report["success"], report["status"] = False, final
        diagnostic_record(cache / "last-run.json", report)
    if not kept:
        shutil.rmtree(plan["base"], ignore_errors=True)
    print("verification: own stores: %s, %d files, %d bytes, %s; mismatch lines %d; %d samples, %d holders of the per-user "
          "leases among this request's processes" % (
              plan["base"], size["files"], size["bytes"], "kept" if kept else "removed",
              sum(mismatches["nonzero"].values()), lease["samples"], len(lease["holders"])), flush=True)
    return final


def stage_store_guard(trees: list[Path], store: Path | None, before: dict | None, status: int, cache: Path | None = None) -> int:
    """Fail a request whose own processes wrote the user's stage store. A green request with a live root of one of TREES
    registered there since BEFORE (a snapshot, `stage_store_snapshot`) returns STAGE_STORE_STATUS; a failing request keeps its
    status. A store that changed with no such root is another process's doing: a note, never a failure."""
    if store is None or before is None:
        return status
    after = stage_store_fingerprint(store)
    writers = stage_store_writers(store, before["roots"], trees)
    verdict = stage_store_verdict(before["fingerprint"], after, writers)
    if not verdict["changed"]:
        return status
    if verdict["passed"]:
        print("verification: NOTE: the per-user stage store %s changed during the request (%s), but no build of this checkout "
              "registered a root there: another process of yours wrote it" % (store, json.dumps(verdict["changed"], sort_keys=True)),
              file=sys.stderr)
        return status
    print("verification: %s: a test reached the per-user stage store %s (%s); builds of this checkout registered: %s" % (
        "FAIL" if status == 0 else "NOTE", store, json.dumps(verdict["changed"], sort_keys=True), ", ".join(writers[:5])),
        file=sys.stderr)
    if cache is not None:
        report = read_record(cache / "last-run.json") or {}
        if report:
            report["stage_store_guard"] = verdict
            report["success"] = False
            if status == 0:
                report["status"] = STAGE_STORE_STATUS
            diagnostic_record(cache / "last-run.json", report)
    return status if status != 0 else STAGE_STORE_STATUS


def fact_leak_suites(action_metadata: list) -> list[str]:
    """The suites of the `language` action's fact-verification/leak-check members."""
    suites = []
    for action in action_metadata or []:
        if not isinstance(action, dict) or action.get("id") != "language":
            continue
        for step in action.get("steps") or []:
            label = step.get("original_label") if isinstance(step, dict) else None
            found = FACT_LEAK_MEMBER.fullmatch(label) if isinstance(label, str) else None
            if found and found.group(1) not in suites:
                suites.append(found.group(1))
    return suites


def forced_fact_leak_run(root: Path, compiler: Path, suites: list[str], environment: Mapping[str, str],
                         scratch: Path, run=subprocess.run, admission=None) -> dict:
    """D1: one fresh fact-verification and leak-check run of every suite.

The run uses `--force` and a private cache directory removed afterwards, so it
neither reads nor replaces the receipts ordinary requests reuse. It holds one
gate admission for all suites.
"""
    if admission is None:
        import build_admission
        admission = build_admission.admission
    child = dict(environment, SELKA_CORE_LEAKCHECK="1")
    child.setdefault(STAGE_VARIABLE, "")
    results = []
    scratch.mkdir(parents=True, exist_ok=True)
    private = Path(tempfile.mkdtemp(prefix="integration-fact-leak-", dir=scratch))
    try:
        with admission("gate"):
            for suite in suites:
                argv = [str(compiler), "test", suite, "--verify-facts", "--force", "--json",
                        "--cache-dir", str(private / re.sub(r"[^A-Za-z0-9_.-]", "_", suite))]
                completed = run(argv, cwd=root, env=child, capture_output=True, text=True, errors="replace")
                counts = {}
                for line in reversed(completed.stdout.splitlines()):
                    if line.startswith("{"):
                        try:
                            parsed = json.loads(line)
                        except json.JSONDecodeError:
                            continue
                        counts = {key: parsed.get(key) for key in ("passed", "failed", "cached", "skipped", "unsupported")}
                        break
                fresh = completed.returncode == 0 and counts.get("failed") == 0 and counts.get("cached") == 0
                results.append({"suite": suite, "argv": argv[1:], "exit": completed.returncode, "counts": counts,
                                "fresh_and_passed": fresh, "stderr_tail": completed.stderr[-2000:]})
    finally:
        shutil.rmtree(private, ignore_errors=True)
    return {"suites": results, "passed": bool(results) and all(row["fresh_and_passed"] for row in results)}


@contextmanager
def environment_overlay(values: Mapping[str, str]):
    """Set VALUES in this process's environment for the block, which `normalized_environment` projects to every worker,
    and restore what was there before."""
    saved = {name: os.environ.get(name) for name in values}
    os.environ.update(values)
    try:
        yield
    finally:
        for name, value in saved.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value


def integration_status(status: int, forced: dict | None, mismatches: dict, rerun: dict | None = None) -> int:
    """The request's status after the integration checks (D-NIGHTLY-1): a mismatch of the request's own stores is 5, then a
    failing complete request keeps its status, then the forced fact/leak run is 7 and the two-run test step 8."""
    if not mismatches["passed"]:
        return INTEGRATION_MISMATCH_STATUS
    if status != 0:
        return status
    if forced is None or not forced["passed"]:
        return INTEGRATION_FORCED_STATUS
    if rerun is not None and not rerun["passed"]:
        return INTEGRATION_RERUN_STATUS
    return 0


def integration_summary(final: int, integration: Mapping) -> str:
    """The one line that says what the integration request decided and why, for the service's journal."""
    reasons = []
    mismatches = integration["shared_mismatches"]
    if not mismatches["passed"]:
        reasons.append("the request's own stores logged %d mismatch lines (%s; kept at %s)" % (
            sum(mismatches["nonzero"].values()),
            ", ".join("%s: %s" % (Path(path).parent.name, lines[0]) for path, lines in integration["own_mismatch_lines"].items()),
            integration["own_stores"]["root"]))
    if integration["request_status"] != 0:
        failed = integration.get("request_failures") or []
        named = "; ".join("%s: %s" % (action, test) for action, test, _state in failed[:2])
        reasons.append("the complete request failed with status %d%s%s%s" % (
            integration["request_status"], " (" + named if named else "",
            "; %d more" % (len(failed) - 2) if len(failed) > 2 else "", ")" if named else ""))
        for line in integration.get("request_flaky") or []:
            reasons.append(line)
    forced = integration["forced_fact_leak"]
    if forced is not None and not forced["passed"]:
        failing = [row["suite"] for row in forced["suites"] if not row["fresh_and_passed"]]
        reasons.append("the forced fact/leak run failed (%s)" % (", ".join(failing) or forced.get("error", "no suites")))
    rerun = integration["two_run_step"]
    if rerun is not None and not rerun["passed"]:
        reasons.append("the two-run test step failed: " + "; ".join(rerun["problems"][:3]))
    per_user = ", ".join("%s %d lines (%+d during the request%s)" % (
        Path(path).parent.name, row["lines"], row["during_request"],
        "" if row["since_last_request"] is None else ", %+d since the last request" % row["since_last_request"])
        for path, row in integration["per_user_mismatches"].items())
    return "verification: integration %s (status %d)%s; per-user mismatch logs (a record, not the verdict): %s" % (
        "PASS" if final == 0 else "FAIL", final, (": " + "; ".join(reasons)) if reasons else "", per_user or "none")


def integrate(root: Path, cache: Path, status: int, before: Mapping[str, int],
              environment: Mapping[str, str], run=subprocess.run, admission=None,
              own: Path | None = None, zig: Path | None = None) -> int:
    """Apply D1, D3 and the two-run step after a complete request; record them in last-run.json.

ENVIRONMENT is the caller's, without the own stores; BEFORE counts its stores' mismatch logs before the request (a record,
not the verdict). OWN is the request's own stores (`own_stores`), which ran every build of the request and decide D3; they
are removed when the request passes and kept when it fails. ZIG runs the two-run step; without it the step is skipped.
"""
    report = read_record(cache / "last-run.json") or {}
    previous = previous_per_user_counts(read_record(cache / "integration-last-run.json"))
    if own is None:
        own = own_stores(cache)
    child = dict(environment, **own_store_environment(own))
    forced, rerun = None, None
    if status == 0:
        suites = fact_leak_suites(report.get("action_metadata"))
        if suites:
            forced = forced_fact_leak_run(root, root / "zig-out/bin/selka", suites, child,
                                          cache / "integration", run=run, admission=admission)
        else:
            forced = {"suites": [], "passed": False, "error": "inventory has no fact/leak language members"}
        if zig is not None:
            rerun = two_run_step(root, zig, child, run=run, admission=admission)
    own_environment = own_store_environment(own)
    mismatches = mismatch_verdict({}, mismatch_counts(own_environment))
    final = integration_status(status, forced, mismatches, rerun)
    per_user = per_user_mismatch_report(before, mismatch_counts(environment, native_default_sharing(root)), previous)
    kept = final != 0
    failed = gate_summary.report_failures(report) if status != 0 else []
    integration = {"version": 2, "request_status": status, "status": final,
                   "request_failures": [list(row) for row in failed[:10]],
                   "request_flaky": [line[:300] for line in gate_summary.flaky_lines(report.get("flaky"))[:2]],
                   "forced_fact_leak": forced, "two_run_step": rerun, "shared_mismatches": mismatches,
                   "own_mismatch_lines": mismatch_excerpt(mismatches["nonzero"]),
                   "own_stores": dict(tree_size(own), root=str(own), kept=kept),
                   "per_user_mismatches": per_user}
    if not kept:
        shutil.rmtree(own, ignore_errors=True)
    summary = integration_summary(final, integration)
    integration["summary"] = summary
    if report:
        report["integration"] = integration
        report["success"] = report.get("success") is True and final == 0
        report["status"] = final if final != 0 else report.get("status", 0)
        diagnostic_record(cache / "last-run.json", report)
    diagnostic_record(cache / "integration-last-run.json", integration)
    if forced is not None:
        for row in forced["suites"]:
            print("verification: integration forced fact/leak %s: exit %d, %s" % (
                row["suite"], row["exit"], json.dumps(row["counts"], sort_keys=True)), flush=True)
    if rerun is not None:
        print("verification: integration two-run step: exit %d in %.1f s, %s" % (
            rerun["exit"], rerun["seconds"], json.dumps(rerun["suites"], sort_keys=True)), flush=True)
    for path, lines in integration["own_mismatch_lines"].items():
        print("verification: FAIL: the request's own store logged a determinism mismatch: %s:\n  %s" % (path, "\n  ".join(lines)),
              file=sys.stderr)
    print("verification: integration own stores: %s, %d files, %d bytes, %s" % (
        own, integration["own_stores"]["files"], integration["own_stores"]["bytes"], "kept" if kept else "removed"), flush=True)
    print(summary, flush=True)
    return final


def bound_caches(root: Path) -> None:
    """Apply the worktree's `.zig-cache` cap once, before this request takes its first snapshot (F48).

    The caller holds `coordinator.lock`, so from here to the end of the request the admissions of this worktree, this
    request's own among them, find a coordinator running and leave `.zig-cache` alone: the prepared artifacts this
    request watches live there, and a cache renamed aside under it fails the run with "inputs changed while awaiting
    admitted work". The cap (`SELKA_ZIG_CACHE_CAP_GB`, docs/tooling/many-agents.md) is applied here instead, while
    nothing is watched. Never fatal: a cap left unapplied is applied by the next admission or request.
    """
    try:
        reason = worktree_cache_trim.bound_for_coordinator(
            root, verification_measurement.build_admission.slot_directory(), os.environ)
    except (OSError, ValueError, subprocess.SubprocessError, SystemExit) as error:
        reason = str(error) or type(error).__name__
    if reason:
        print("verification: warning: the worktree cache cap was not applied: " + reason, file=sys.stderr)


def main(argv: list[str]) -> int:
    if argv[:1] == ["--admitted"]:
        return admitted_child(int(argv[1]))
    if argv[:1] == ["--keyed-request"]:
        return run_keyed_request(Path(argv[1]))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zig", default=os.environ.get("SELKA_ZIG") or os.environ.get("ZIG") or "zig")
    parser.add_argument("--profile", choices=verification_profiles.PROFILES, default="complete")
    parser.add_argument("--quick-actions", type=int, default=3, help="Maximum quick-profile pending actions; heuristic and partial")
    parser.add_argument("--qualification-target", action="append", choices=verification_qualification.OBLIGATIONS)
    parser.add_argument("--qualification-max-actions", type=int, default=6)
    parser.add_argument("--qualification-timeout", type=float, default=300)
    parser.add_argument("--qualification-fuzz-steps", type=int, default=8)
    parser.add_argument("--force", action="store_true", help="Ignore prior successes for the requested profile")
    parser.add_argument("--verbose", action="store_true",
                        help="Stream the full build output instead of the bounded summary")
    parser.add_argument("--verify", action="store_true",
                        help="Rehash every input instead of reusing recorded digests")
    parser.add_argument("--dry-run", action="store_true",
                        help="Prepare and compute every action key and reuse verdict, write %s/dry-run.json, "
                             "and run no gate" % CACHE_DIRECTORY)
    parser.add_argument("--shared-cache-dir", help="Shared success evidence (default: $%s, else off; an empty value disables); inventory and runs stay private" % SHARED_CACHE_VARIABLE)
    parser.add_argument("--build-timeout-seconds", type=float, default=DEFAULT_BUILD_TIMEOUT_SECONDS,
                        help="Deadline per admitted preparation command, queue excluded (default %d s; 0 disables)" % DEFAULT_BUILD_TIMEOUT_SECONDS)
    parser.add_argument("--gate-timeout-seconds", type=float, default=DEFAULT_GATE_TIMEOUT_SECONDS,
                        help="Deadline for the admitted selected gate, queue excluded (default %d s; 0 disables)" % DEFAULT_GATE_TIMEOUT_SECONDS)
    parser.add_argument("--warn-after-seconds", type=float, help="Advisory total work target excluding admission queues; never changes reuse or pass/fail")
    parser.add_argument("--budget-policy", type=Path, help="Optional v1/v2 report-only scoped policy; never changes reuse or pass/fail")
    parser.add_argument("--timing-window-seconds", type=float,
                        help="Own an exclusive bounded request measurement; run directly, never under a slot")
    parser.add_argument("--fail-fast", action="store_true",
                        help="End the build at the first failing step and print the failure summary then, instead of "
                             "after every other action has finished; the unfinished actions record no receipt (a passing "
                             "run is unchanged)")
    parser.add_argument("--no-flaky-rerun", action="store_true",
                        help="Fail on any failing test, without rerunning a few named failing tests once alone (D5)")
    parser.add_argument("--no-disk-wait", action="store_true",
                        help="Do not wait while the disk's full avg60 pressure is above %.0f%%%% (by default the gate waits "
                             "up to %d min before asking for admission)" % (DISK_PRESSURE_LIMIT, DISK_WAIT_SECONDS // 60))
    parser.add_argument("--integration", action="store_true",
                        help="Integration gate (the nightly): the complete profile against empty compiler and test stores of "
                             "its own, then one forced fact/leak run of the language members (D1, status %d) and the two-run "
                             "test step (status %d); a mismatch its own stores log is status %d (D3)" % (
                                 INTEGRATION_FORCED_STATUS, INTEGRATION_RERUN_STATUS, INTEGRATION_MISMATCH_STATUS))
    parser.add_argument("--own-stores", choices=OWN_STORES_MODES, default="fresh",
                        help="GATE3: run every build of the request against an empty compiler store and test store of its own, "
                             "made under .selka-cache/verification-v3/%s and removed when the request ends (default `fresh`; "
                             "`off` leaves the stores to the caller's environment, which selects the per-user ones when it "
                             "names none). A store the caller names keeps the caller's. A build that opens the user's default "
                             "store instead fails a green request with status %d, a mismatch in the own stores with status %d. "
                             "`--integration` always runs against its own stores" % (
                                 GATE_STORES_DIRECTORY, STAGE_STORE_STATUS, INTEGRATION_MISMATCH_STATUS))
    parser.add_argument("options", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    if args.dry_run and (args.integration or args.force):
        print("verification: FAIL: --dry-run runs nothing; it takes neither --integration nor --force", file=sys.stderr)
        return 2
    if args.integration and (args.profile != "complete" or args.timing_window_seconds is not None):
        print("verification: FAIL: --integration runs the complete profile without a timing window", file=sys.stderr)
        return 2
    cancellation = 130
    def cancel(signum, _frame):
        nonlocal cancellation
        cancellation = 128 + signum
        raise KeyboardInterrupt
    previous = {signum: signal.signal(signum, cancel) for signum in (signal.SIGTERM, signal.SIGHUP)}
    try:
        if args.timing_window_seconds is not None:
            verification_measurement.validate(args.timing_window_seconds)
            if args.profile == "long-qualification":
                raise ValueError("long qualification owns separate measurement phases; omit the request timing window")
        resolved = shutil.which(args.zig)
        if resolved is None:
            raise VerificationError("cannot find Zig: " + args.zig)
        cache = ROOT / CACHE_DIRECTORY
        shared_cache_dir, shared_cache_source = shared_cache_location(args.shared_cache_dir, os.environ)
        cache.mkdir(parents=True, exist_ok=True)
        # Serialize coordinators for this checkout, outside the shared server
        # slots, so preparation and forced invalidation cannot race one another.
        with (cache / "coordinator.lock").open("a") as lock:
            lock_requested_at = time.monotonic()
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
            lock_wait = time.monotonic() - lock_requested_at
            if args.timing_window_seconds is None and not args.dry_run:
                bound_caches(ROOT)  # A timing window admits no wrapper, so it never trimmed; a dry run changes nothing.
            with ExitStack() as stack:
                if args.timing_window_seconds is not None:
                    stack.enter_context(verification_measurement.timing_window(
                        args.timing_window_seconds, coordinator_lock_wait_seconds=lock_wait))
                before = mismatch_counts(os.environ, native_default_sharing()) if args.integration else {}
                caller_environment = dict(os.environ)
                own = own_stores(cache) if args.integration else None
                if own is not None:
                    stack.enter_context(environment_overlay(own_store_environment(own)))
                gate_stores = None
                if args.own_stores != "off" and not args.integration and not args.dry_run:
                    gate_stores = prepare_gate_stores(cache, args.own_stores, caller_environment)
                    stack.enter_context(environment_overlay(gate_stores["environment"]))
                    lease_watch = stack.enter_context(StoreLeaseWatch(gate_stores["guarded"]))
                stage_store = None if args.dry_run else stage_store_root(os.environ)
                stage_before = stage_store_snapshot(stage_store) if stage_store is not None else None
                disk_waiter = DiskWaiter(not (args.no_disk_wait or args.dry_run or args.timing_window_seconds is not None))
                status = execute_with_restarts(ROOT, cache, Path(resolved).absolute(), parse_options(args.options), args.force, shared_cache_dir,
                               build_timeout=args.build_timeout_seconds, gate_timeout=args.gate_timeout_seconds,
                               verbose=args.verbose,
                               warn_after=args.warn_after_seconds, budget_policy=args.budget_policy,
                               profile=args.profile, quick_actions=args.quick_actions,
                               qualification_targets=args.qualification_target,
                               qualification_max_actions=args.qualification_max_actions,
                               qualification_timeout=args.qualification_timeout,
                               qualification_fuzz_steps=args.qualification_fuzz_steps,
                               shared_cache_source=shared_cache_source, dry_run=args.dry_run,
                               verify_digests=args.verify, fail_fast=args.fail_fast, disk_waiter=disk_waiter,
                               flaky_rerun=not args.no_flaky_rerun)
                if args.integration:
                    status = integrate(ROOT, cache, status, before, caller_environment, own=own,
                                       zig=Path(resolved).absolute())
                if gate_stores is not None:
                    lease_watch.close()  # stop the sampler before the verdict
                    status = finish_gate_stores(cache, gate_stores, lease_watch, status)
                return stage_store_guard([ROOT], stage_store, stage_before, status, cache)
    except (verification_measurement.WindowExpired, verification_measurement.WindowLost) as error:
        expired = isinstance(error, verification_measurement.WindowExpired)
        status = 124 if expired else 2
        diagnostic_record(ROOT / CACHE_DIRECTORY / "last-run.json",
                          {"version": REPORT_VERSION, "success": False, "status": status,
                           "stage": "measurement_deadline" if expired else "measurement_authority", "error": str(error),
                           "measurement_window_seconds": args.timing_window_seconds})
        print("verification: FAIL: " + str(error), file=sys.stderr)
        return status
    except (VerificationError, SnapshotError, OSError, ValueError,
            fuzz_campaign_store.FormatError, fuzz_campaign_store.DeterminismError) as error:
        print("verification: FAIL: " + str(error), file=sys.stderr)
        print_failure_record(ROOT / CACHE_DIRECTORY / "last-run.json", str(error))
        return error.status if isinstance(error, VerificationError) else 2
    except KeyboardInterrupt:
        print("verification: cancelled; no new success receipts", file=sys.stderr)
        return cancellation
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)


# Bind evidence to the code actually loaded, even if the files change before
# filesystem watches are installed. Next invocation's new code has another key.
_LOADED_CODE_OBJECT = sys._getframe().f_code
LOADED_CODE_SHA256 = code_identity.loaded_code_sha256(_LOADED_CODE_OBJECT)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

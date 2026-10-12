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
import time
from typing import Mapping

from verification_snapshot import Snapshot, SnapshotError
import verification_snapshot
import fuzz_campaign_store
import verification_report
import verification_budgets
import verification_profiles
import verification_qualification
import verification_process
import verification_producers
import verification_environment
import verification_telemetry
import verification_measurement
from verification_process import BoundedProcessLogs, ProcessLimits, terminate_owned, wait_owned

ROOT = Path(__file__).resolve().parents[1]
# Receipt schema 3: path-free, projected-environment identities. The directory
# carries the same number, so schema-2 receipts are never opened, let alone misread.
VERSION = 3
CACHE_DIRECTORY = Path(".mylang-cache/verification-v3")
ACTION_DOMAIN = "selka-verification-action-v6"
# Shared success evidence at the per-user default location (D2: same user, same
# machine). Off until the week-3 rollout; MYLANG_VERIFICATION_SHARED_CACHE or
# --shared-cache-dir still select a store explicitly, and an empty value disables.
DEFAULT_SHARING = False
SHARED_CACHE_VARIABLE = "MYLANG_VERIFICATION_SHARED_CACHE"
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
    ("build.zig", 'verification_registry.?.register("component-preparation", &component_build.step, '
                  '&test_inputs.component_inputs, false, "component manifests and installed outputs require validation");'),
    ("build.zig", 'verification_registry.?.register("component-support", &run_component_support.step, '
                  '&test_inputs.component_builder, true, "exact native support executable and declared inputs");'),
    ("build.zig", 'verification_registry.?.register("juice", &juice_native_run.step, &test_inputs.juice, false, '
                  '"native performance collectors and host state require fresh execution");'),
    ("build.zig", 'verification_registry.?.register("juice-runtime", &juice_runtime_run.step, &test_inputs.juice_runtime, '
                  'false, "runtime collectors observe CPU, scheduler and current host state");'),
    ("build.zig", 'verification_registry.?.register("coverage", &coverage_run.step, &test_inputs.coverage, false, '
                  '"fixture membership and negative path lookups outside source recipes require freshness");'),
    ("build.zig", 'verification_registry.?.register("doc-coverage", &doc_coverage.step, &test_inputs.doc_coverage, true, '
                  '"complete document and feature-contract scope");'),
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
# `--integration` (plan D3): a shared-store determinism mismatch fails the
# integrated commit with its own status, distinct from a failing test (1).
INTEGRATION_MISMATCH_STATUS = 5
# The native shared stores whose `<namespace>/mismatches.log` the integration
# check reads; only stores this request's environment selects are "used".
NATIVE_SHARED_VARIABLES = ("MYLANG_COMPILER_SHARED_CACHE", "MYLANG_TEST_SHARED_CACHE")
FACT_LEAK_MEMBER = re.compile(r"mylang test (\S+) --release --verify-facts \(leak check\)")
COMPONENT_SOURCE_OPTIONS = {"-Dcomponent-owned-compiler-pin", "-Dcomponent-seed-source"}
MAX_RECORD = 32 * 1024 * 1024
# The build runner's own compile closure: every file `build.zig` imports,
# transitively (`BuildToolIdentity` in verify_cache_test.py names any file
# missing here). `build_env.zig`'s `build-env` host tool wraps every cached test
# step (`withTools`) and `build_identity.zig` keys the compiler build; the build
# graph registers their compile steps as prepared infrastructure, not as
# actions, so their `src/` imports are bound here, in every action's
# `build_configuration`, beside `src/environment_identity.zon` below.
CONFIG_INPUTS = ["./*.zig", "build.zig.zon", ".zigversion", "guardian.toml",
                 "src/user_docs.zig", "src/environment_identity.zig", "src/build_env_rules.zig",
                 "src/build_identity_rules.zig", "src/semantic_cache_format.zig",
                 "selfhost/*.zig", "../guardian-zig/build.zig",
                 "../guardian-zig/build.zig.zon", "../guardian-zig/src/"]
PREPARE_INPUTS = ["src/", "test/", "tests/", "selfhost/",
                  "docs/", "README.md", "SPEC.md", "benchmarks/runtime/ports/native_clock.c"]
COORDINATOR_INPUTS = ["scripts/verification_qualification.py", "scripts/verification_code_identity.py", "scripts/verify_cache.py", "scripts/verification_profiles.py", "scripts/verification_snapshot.py",
                      "scripts/verification_process.py",
                      "scripts/cache_session.py",
                      "scripts/verification_artifacts.py", "scripts/verification_producers.py",
                      "scripts/verification_environment.py", "src/environment_identity.zon",
                      "scripts/verification_telemetry.py", "scripts/build_admission.py",
                      "scripts/verification_measurement.py",
                      "scripts/fuzz_campaign_store.py", "scripts/build-slot.sh"]
# These are the host tools used by the registered test adapters and admission.
# An adapter needing another external provider must declare it here or stay fresh.
HOST_TOOLS = ("python3", "sh", "bash", "env", "grep", "sort", "mktemp", "rm",
              "sleep", "git", "find", "dirname", "readlink", "realpath", "cp",
              "mv", "chmod", "uname", "ln", "head", "tail", "wc", "timeout",
              "taskset", "setsid", "flock", "awk", "seq", "date", "cat", "touch", "sha256sum")
UNTRACKED_ENV = ("LD_PRELOAD", "LD_LIBRARY_PATH", "LD_AUDIT", "PYTHONPATH",
                 "PYTHONHOME", "ZIG_LIB_DIR", "CC", "CXX", "CPATH",
                 "C_INCLUDE_PATH", "CPLUS_INCLUDE_PATH", "LIBRARY_PATH")


class VerificationError(RuntimeError):
    """The requested verification cannot be certified."""

    def __init__(self, message, status=2):
        super().__init__(message)
        self.status = status


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
    return (record is not None and type(record.get("version")) is int and
            record == {"version": VERSION, "kind": "verification-success", "key": action_key})


def save_receipt(path: Path, action_key: str) -> None:
    atomic_record(path, {"version": VERSION, "kind": "verification-success", "key": action_key})


def inventory(path: Path) -> dict:
    value = read_record(path)
    if (not value or type(value.get("version")) is not int or value["version"] != INVENTORY_VERSION
            or value.get("required_targets") != ["test", "fmt-check"]):
        raise VerificationError("invalid or unsupported verification inventory")
    if set(value) != {"version", "required_targets", "groups", "input_lists", "configuration", "coverage", "action_metadata"}:
        raise VerificationError("unsupported inventory fields")
    controls = value.get("configuration")
    if (not isinstance(controls, dict) or set(controls) != {"filtered", "rerun", "optimize"}
            or type(controls["filtered"]) is not bool or type(controls["rerun"]) is not bool
            or not isinstance(controls["optimize"], str) or not controls["optimize"]):
        raise VerificationError("invalid inventory configuration")
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
    if any(group["id"] == "coverage" and group["cacheable"] for group in groups):
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
    env.pop("MYLANG_TEST_TELEMETRY_DIR", None)
    env.pop("SELKA_VERIFICATION_TELEMETRY_DIR", None)
    # The process-local measurement capability controls admission. Transport
    # markers are installed only on admitted children, never trusted as proof.
    for marker in ("MYLANG_ADMISSION_DIR", "MYLANG_ADMISSION_KIND"):
        env.pop(marker, None)
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


def environment_identity(env: Mapping[str, str], tools: Snapshot | None, tool_files: list[Path], root: Path) -> str:
    """Host-scope digest of the worker environment and the content of each resolved tool.

    Tools are named by their snapshot label (absolute for host tools, relative
    for anything inside the checkout) and identified by the digest the tools
    snapshot already computed; nothing is hashed twice.
    """
    wanted = {os.path.abspath(path) for path in tool_files}
    digests = {} if tools is None else {
        item["path"]: item["sha256"] for item in tools.identity["files"]
        if os.path.abspath(root / item["path"]) in wanted}
    return verification_environment.digest(env, digests, scope="host")


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


def admitted_child(fd: int) -> int:
    """Handshake after FIFO admission; execute only after the parent revalidates."""
    expected_pid = int(os.environ.get("MYLANG_ADMISSION_PARENT_PID", os.getppid()))
    expected_start = int(os.environ.get("MYLANG_ADMISSION_PARENT_START",
                                       verification_process._process_starttime(expected_pid) or 0))
    if not verification_process.arm_parent_death(expected_pid, expected_start):
        return 130
    with socket.socket(fileno=fd) as channel:
        channel.sendall(b"admitted\n")
        chunks = []
        while data := channel.recv(65536):
            chunks.append(data)
        if not chunks:
            return RETRY
        request = json.loads(b"".join(chunks))
    os.chdir(request["cwd"])
    return verification_process.run_supervised(request["argv"], request["env"])


def run_admitted(root: Path, kind: str, argv: list[str], env: dict[str, str], unchanged,
                 timings: list[dict] | None = None, *, limits: ProcessLimits | None = None,
                 log_dir: Path | None = None) -> tuple[int, float]:
    """Hold the normal slot only for selected work, checking again after queueing."""
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
                stdout_tee=getattr(sys.stdout, "buffer", None), stderr_tee=getattr(sys.stderr, "buffer", None))
        except OSError:
            pass  # Diagnostic storage never authorizes or prevents verification.
    submitted_at = time.monotonic()
    try:
        wrapper_environment = dict(env, MYLANG_ADMISSION_PARENT_PID=str(os.getpid()),
                                   MYLANG_ADMISSION_PARENT_START=str(verification_process._process_starttime(os.getpid())))
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
    try:
        if logs is not None:
            logs.start(process)
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
        outcome = wait_owned(process, limits=limits if worker_at is not None else ProcessLimits(),
                             execution_started=worker_at, logs=logs)
        status = outcome.returncode
        ended_at = time.monotonic()
        held = 0.0 if admitted_at is None else ended_at - admitted_at
        if timings is not None:
            timings.append({"kind": kind, "status": status, "admitted": admitted_at is not None,
                            "admission_scope": "request-timing-window" if measurement else "command",
                            "admission_wait_seconds": (admitted_at or ended_at) - submitted_at,
                            "validation_seconds": validation_seconds,
                            "worker_seconds": 0.0 if worker_at is None else ended_at - worker_at,
                            "observed_held_seconds": held, "elapsed_seconds": ended_at - submitted_at,
                            "timed_out": outcome.timed_out, "cancelled": outcome.cancelled,
                            "incomplete": outcome.incomplete,
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
    except BaseException:
        parent.close()
        terminate_owned(process)
        if logs is not None:
            logs.close()
        raise
    finally:
        for stream in (process.stdout, process.stderr):
            if stream is not None:
                stream.close()


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
    if not {"mylang", "units", "cli", "core"} <= artifacts.keys():
        raise VerificationError("prepared inventory omits native test executables")
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
    try:
        locations = artifact_locations(read_record(root / "zig-out/verification/artifacts.json"))
    except VerificationError as error:
        raise VerificationError("prepared artifact inventory changed during provider selection") from error
    paths = {name: [Path(path)] for name, path in locations.items()}
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
    commit agree. An installed copy (zig-out/bin/mylang) must equal the produced
    bytes, or the provider falls back to bytes. The report names, per label,
    which identity was used and why a fallback happened.
    """
    select = recipe_selector(sources, root)
    identities, report = {}, {}
    for label in sorted(providers):
        producer, reason = verification_producers.native_producer(record, label)
        # A provider is copies of one artifact (zig-out/bin/mylang beside the
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
        report[label] = {"identity": "producer", "sources": len(identity["sources"])}
    return identities, report


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
                 "component_sources": "value", "action_controls": "value",
                 "environment": "preimage", "tools": "preimage", "build_configuration": "preimage",
                 "inventory": "preimage", "loaded_code_format": "loaded_code", "implementation": "loaded_code",
                 "artifacts": "artifacts"}


def implementation_code() -> list[tuple[str, str, object]]:
    """(module, bound digest, loaded code) of each coordinator module whose
    digest enters `common["implementation"]`, in key order."""
    modules = [("verification_measurement", verification_measurement),
               ("build_admission", verification_measurement.build_admission),
               ("verification_snapshot", verification_snapshot), ("fuzz_campaign_store", fuzz_campaign_store),
               ("verification_process", verification_process), ("verification_producers", verification_producers),
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
    else all of them.
    """
    if any(name not in COMMON_FACETS for name in payload["common"]):
        return False
    if not facets_path_free or mentions(payload, str(root)):
        return False
    artifacts = payload["common"].get("artifacts")
    labels = artifacts.keys() if isinstance(artifacts, dict) else report.keys()
    return all(report.get(label, {}).get("identity") == "producer" for label in labels)


def action_payload(group: dict, snapshot: Snapshot, common: dict, root: Path,
                   providers: dict[str, list[dict]] | None = None, membership: dict | None = None,
                   producer_manifest: dict | None = None, labels: dict | None = None) -> dict:
    """The exact document an action key hashes; `labels` are artifact_identities' per-provider identities."""
    files = snapshot.selected_files(lambda path: any(
        matches_recipe(path, recipe, root) for recipe in group["inputs"]))
    selected = group.get("artifacts")
    if selected is not None:
        if providers is None or any(name not in providers for name in selected):
            raise VerificationError("action names an unavailable artifact provider: " + group["id"])
        legacy = {"mylang", "units", "cli", "core", "golden", "memory-budget",
                  "component-support", "component-builder", "components"}
        identities = {}
        for name in selected:
            if name in verification_producers.CLOSURES:
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
    options = [arg for arg in options if not (rerun and arg.startswith("-Dtest-rerun="))]
    args = [str(zig), "build", *targets, *options]
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
            notes: dict | None = None) -> tuple[dict, Snapshot, float]:
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
    held = 0.0
    if plan is None:
        status, seconds = run_admitted(root, "build", zig_command(zig, ["verification-plan"], options),
                                       env, lambda: check_all(snapshots), timings=timings,
                                       limits=limits, log_dir=cache / "last-logs/inventory")
        held += seconds
        if status or not check_all(snapshots):
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
    if artifacts is None:
        status, seconds = run_admitted(root, "build", zig_command(zig, ["verification-prepare"], options),
                                       env, lambda: check_all(snapshots), timings=timings,
                                       limits=limits, log_dir=cache / "last-logs/preparation")
        held += seconds
        if status or not check_all(snapshots):
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

    Precedence: --shared-cache-dir, then MYLANG_VERIFICATION_SHARED_CACHE, then,
    only when default sharing is on, $XDG_CACHE_HOME/mylang/verification-shared
    or ~/.cache/mylang/verification-shared. An explicitly empty value disables
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
    return Path(base) / "mylang" / "verification-shared", "default"


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


def component_source_files(options: list[str]) -> list[Path]:
    """Explicit packaging inputs; preserve logical paths for symlink watches."""
    sources = {}
    for arg in options:
        name, separator, value = arg.partition("=")
        if name not in COMPONENT_SOURCE_OPTIONS:
            continue
        if not separator or not value or "\x00" in value:
            raise VerificationError("missing or invalid component input: " + name)
        if name in sources:
            raise VerificationError("duplicate component input: " + name)
        sources[name] = Path(value)
    return list(sources.values())


def execute(root: Path, cache: Path, zig: Path, options: list[str], force: bool = False,
            shared_cache_dir: Path | None = None, *, build_timeout: float | None = None,
            gate_timeout: float | None = None, warn_after: float | None = None,
            budget_policy: Path | None = None, profile: str = "complete", quick_actions: int = 3,
            qualification_targets=None, qualification_max_actions=4,
            qualification_timeout=300, qualification_fuzz_steps=8, shared_cache_source: str | None = None,
            dry_run: bool = False) -> int:
    if profile not in verification_profiles.PROFILES or type(quick_actions) is not int or not 1 <= quick_actions <= 1024:
        raise ValueError("invalid verification profile or quick action bound")
    if dry_run and force:
        raise ValueError("a dry run cannot force reruns")
    qualification_controls = {"targets": list(verification_qualification.OBLIGATIONS if qualification_targets is None else qualification_targets),
        "max_actions": qualification_max_actions, "action_timeout": qualification_timeout, "fuzz_steps": qualification_fuzz_steps}
    verification_qualification.validate_options(**qualification_controls)
    build_limits, gate_limits = ProcessLimits(build_timeout), ProcessLimits(gate_timeout)
    measurement = verification_measurement.current()
    if warn_after is not None:
        ProcessLimits(warn_after)  # Same positive, finite validation; advisory only.
    started = time.monotonic()
    admissions, phases = [], {}
    (root / "zig-out/verification").mkdir(parents=True, exist_ok=True)
    env = normalized_environment(root)
    env["ZIG"] = str(zig)
    env["MYLANG_ZIG"] = str(zig)
    tool_recipes, tool_files = tool_contract(zig, env)
    with ExitStack() as stack:
        shared_source = shared_cache_source or ("none" if shared_cache_dir is None else "flag")
        shared = open_shared_store(shared_cache_dir, shared_source, stack)
        if shared is not None:
            # Mutual exclusion only: the real checkout path never enters a key.
            coordinator = key({"domain": "verification-coordinator-v1", "root": str(root)})
            stack.enter_context(shared.coordinator_lock(coordinator))
        session = verification_snapshot.DigestSession()
        tools = snapshot_role(stack.enter_context(Snapshot(root, tool_recipes, tool_files, digest_session=session)), "tools")
        # Recheck lookup membership now. The complete snapshot set is validated
        # before every admitted command, cache verdict and publication below.
        if tool_contract(zig, env) != (tool_recipes, tool_files):
            raise VerificationError("tool resolution changed while installing input watches")
        host = HostContext()
        snapshots = [tools, host]
        failure_context = {"stage": "preparation", "actions": []}

        def record_failure(error_type, error, _traceback):
            if error_type is not None:
                failure_status = (RETRY if isinstance(error, SnapshotError) else
                                  130 if isinstance(error, KeyboardInterrupt) else getattr(error, "status", 2))
                diagnostic_record(cache / "last-run.json", {"version": REPORT_VERSION, "success": False,
                    "status": failure_status, "stage": failure_context["stage"], "error": str(error)[:1024],
                    "actions": failure_context["actions"], "stability_diagnostics": stability_diagnostics(snapshots),
                    "admissions": admissions, "timings": phases,
                    "elapsed_seconds": time.monotonic() - started})
            return False

        stack.push(record_failure)
        component_sources = None
        if files := component_source_files(options):
            # Bind external pin/archive bytes before preparation and keep their
            # watches through admission, execution, and receipt publication.
            component_sources = stack.enter_context(Snapshot(root, [], files, digest_session=session))
            snapshots.append(component_sources)
        common = {"version": VERSION, "options": options,
                  "environment": environment_identity(env, tools, tool_files, root), "platform": host.identity,
                  "tools": key(tools.identity),
                  "execution_limits": {"build": build_limits.execution_identity(),
                                       "gate": gate_limits.execution_identity(),
                                       "measurement_window_seconds": None if measurement is None else measurement.seconds},
                  "loaded_code_format": [code_identity.FORMAT_VERSION, code_identity.LOADED_CODE_SHA256],
                  "implementation": [digest for _, digest, _ in implementation_code()]}
        if component_sources is not None:
            common["component_sources"] = component_sources.identity
        try:
            configuration_notes = {}
            plan, artifacts, build_seconds = prepare(root, cache, zig, options, env, common, snapshots, stack,
                                                    admissions, phases, session, build_limits, configuration_notes)
        except VerificationError as error:
            diagnostic_record(cache / "last-run.json", {"version": REPORT_VERSION, "success": False,
                "status": error.status, "stage": "preparation", "error": str(error), "actions": [],
                "admissions": admissions, "timings": phases,
                "stability_diagnostics": stability_diagnostics(snapshots),
                "elapsed_seconds": time.monotonic() - started})
            raise
        common["inventory"] = key(plan)
        providers = artifact_providers(root, artifacts)
        producer_manifest = read_record(root / "zig-out/verification/artifacts.json")
        # Producer identities come from the preparation snapshots, which every
        # recipe must fall inside; artifacts.json's own bytes hold only paths
        # and producer metadata, both represented here without a location.
        recipe_sources = [item for snapshot in snapshots if getattr(snapshot, "verification_role", "")
                          in ("configuration", "preparation_sources") for item in snapshot.identity["files"]]
        labels, artifact_report = artifact_identities(producer_manifest, providers, recipe_sources, root)
        common["artifacts"] = key({"version": producer_manifest.get("version") if producer_manifest else None,
                                   "providers": labels})
        environment_names = identity_variables(env)
        relocation_dependent = location_dependent_code()
        facets_path_free = not relocation_dependent and not mentions(
            {"tools": tools.identity, "environment": {name: env[name] for name in environment_names},
             "configuration": [snapshot.identity for snapshot in snapshots
                               if getattr(snapshot, "verification_role", "") == "coordinator"],
             "inventory": plan}, str(root))
        groups = plan["groups"]
        recipes = sorted({entry for group in groups for entry in group["inputs"]})
        input_started = time.monotonic()
        inputs = snapshot_role(stack.enter_context(Snapshot(root, recipes, digest_session=session)), "action_inputs")
        phases["action_input_snapshot_seconds"] = time.monotonic() - input_started
        snapshots.append(inputs)
        unsupported = [name for name in UNTRACKED_ENV if env.get(name)]
        force = force or "-Dtest-rerun=true" in options or bool(plan.get("configuration", {}).get("filtered"))
        if force and not dry_run:
            # A failed explicit rerun must not leave an older success available.
            # This is a local evidence store; deleting evidence only causes work.
            for path in (cache / "actions").glob("*.json"):
                path.unlink(missing_ok=True)
        metadata = {action["id"]: action for action in plan["action_metadata"]}
        results, selected, keys, summaries = [], [], {}, {}
        failure_context.update(stage="cache_lookup", actions=results)
        for group in groups:
            payload = action_payload(group, inputs, common, root, providers, metadata[group["id"]],
                                     producer_manifest, labels)
            action_key = key(payload)
            keys[group["id"]] = action_key
            summary = verification_report.dependency_summary(group, payload["files"], dict(payload["common"], membership=metadata[group["id"]]))
            summary_path = cache / "diagnostics" / (group["id"] + ".json")
            previous = verification_report.read_summary(summary_path)
            summaries[group["id"]] = (summary_path, summary)
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
            diagnostic = (verification_report.explain_miss(summary, previous) if reusable and not hit
                          else {"status": "policy", "reason": reason, "changes": [], "truncated": False})
            diagnostic["comparison_scope"] = "previous stable request; not necessarily the receipt-producing success"
            results.append({"id": group["id"], "action_key": action_key, "state": state, "reason": reason,
                            "invalidation": diagnostic,
                            "path_free": path_free(payload, root, facets_path_free, artifact_report),
                            "environment_variables": environment_names})
            print("verification: %s %s (%s)" % (state, group["id"], reason), flush=True)
            if not hit:
                if shared is not None and not dry_run:
                    shared.invalidate_success(action_key)
                selected.append(group)
        profile_plan = verification_profiles.schedule(plan, results, profile, quick_actions=quick_actions)
        selected_ids = set(profile_plan["selected"])
        by_id = {group["id"]: group for group in groups}
        selected = [by_id[name] for name in profile_plan["selected"]]
        for row in results:
            if row["state"] != "reused" and row["id"] not in selected_ids:
                row.update(state="skipped", reason="deferred by partial feedback profile")
        print("verification: profile %s; %d pending, %d selected, %d deferred%s" %
              (profile, len(profile_plan["pending"]), len(selected), len(profile_plan["deferred"]),
               "; heuristic partial selection" if profile_plan["heuristic"] else ""), flush=True)
        if not check_all(snapshots):
            diagnostic_record(cache / "last-run.json", {"version": REPORT_VERSION, "success": False,
                "status": RETRY, "stage": "cache_lookup", "actions": results,
                "inputs_stable": False, "stability_diagnostics": stability_diagnostics(snapshots),
                "admissions": admissions, "timings": phases,
                "elapsed_seconds": time.monotonic() - started})
            raise VerificationError("inputs changed during cache lookup; rerun verification", RETRY)
        if dry_run:
            # The plan export: identities and reuse verdicts after preparation,
            # with no gate admission, publication or advisory summary writes.
            diagnostic_record(cache / "dry-run.json", {"version": REPORT_VERSION, "dry_run": True, "profile": profile,
                "common": common, "budget_context": key({name: value for name, value in common.items() if name != "inventory"}),
                "actions": results, "profile_plan": profile_plan, "artifact_identities": artifact_report,
                "declarative_configuration": configuration_notes.get("declarative_configuration"),
                "relocation_dependent_code": relocation_dependent,
                "admissions": admissions, "elapsed_seconds": time.monotonic() - started})
            print("verification: dry run; %d reused, %d would run; report %s" %
                  (sum(row["state"] == "reused" for row in results), len(selected), cache / "dry-run.json"), flush=True)
            return 0
        phases["prepare_lookup_outside_admission_seconds"] = (time.monotonic() - started
                                                              - sum(event["elapsed_seconds"] for event in admissions))
        status, gate_seconds = 0, 0.0
        failure_context["stage"] = "execution"
        telemetry_directory = None
        if selected:
            gate_environment = dict(env)
            try:
                telemetry_directory = Path(stack.enter_context(tempfile.TemporaryDirectory(
                    prefix="test-telemetry-", dir=cache)))
                gate_environment["SELKA_VERIFICATION_TELEMETRY_DIR"] = str(telemetry_directory)
            except OSError:
                pass  # Diagnostic storage cannot change test selection or verdict.
            # Force chosen Run steps: an outer miss (tool/environment/ABA) must not
            # be accidentally satisfied by a weaker, older inner Zig verdict.
            targets = (plan["required_targets"] if len(selected) == len(groups)
                       else [group["target"] for group in selected])
            status, gate_seconds = run_admitted(root, "gate",
                zig_command(zig, targets, options, rerun=True),
                gate_environment, lambda: check_all(snapshots), timings=admissions,
                limits=gate_limits, log_dir=cache / "last-logs/gate")
        validation_started = time.monotonic()
        stable = check_all(snapshots)
        phases["final_validation_seconds"] = time.monotonic() - validation_started
        if status == 0 and not stable:
            status = RETRY
        publication_started = time.monotonic()
        failure_context["stage"] = "publication"
        if status == 0:
            published = []
            publication_valid = False
            def revoke_publications():
                for path in published:
                    path.unlink(missing_ok=True)
                    if shared is not None:
                        shared.invalidate_success(path.stem)
            def revoke_on_failure(error_type, _error, _traceback):
                if error_type is not None:
                    revoke_publications()
                return False
            stack.push(revoke_on_failure)
            if measurement is not None:
                # A deadline in later reporting still makes this bounded request
                # incomplete. Retain rollback until its timing holder closes.
                measurement.rollbacks.append(revoke_publications)
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
                    revoke_publications()
        phases["publication_seconds"] = time.monotonic() - publication_started
        # Advisory snapshots describe the last stable request, including failures.
        # They are not successes and never participate in cache authorization.
        if stable:
            for path, summary in summaries.values():
                verification_report.write_summary(path, summary)
        qualification_run = None
        qualification_context = {"common": common, "action_keys": keys, "qualification": qualification_controls}
        if profile == "long-qualification" and status == 0 and stable and not plan.get("configuration", {}).get("filtered"):
            compiler = root / "zig-out/bin/mylang"
            qualification_run = stack.enter_context(verification_qualification.qualify(
                root, cache / "long-qualification", compiler, zig, qualification_context, snapshots, **qualification_controls))
            snapshots.extend(qualification_run.additional_snapshots)
            stable = check_all(snapshots)
            if not stable:
                status = RETRY
                revoke_publications()
        elapsed = time.monotonic() - started
        observed_work = max(0.0, elapsed - sum(event["admission_wait_seconds"] for event in admissions))
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
                  "actions": results, "inputs_stable": stable,
                  "stability_diagnostics": stability_diagnostics(snapshots) if not stable or status == RETRY else None,
                  "component_sources": common.get("component_sources"),
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
                  "elapsed_seconds": elapsed}
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
        diagnostic_record(cache / "last-run.json", report)
        print("verification: %s; %d reused, %d selected; build admitted %.3fs, gate admitted %.3fs" %
              ("PASS" if report_status == 0 else "PARTIAL" if report_status == 3 else "FAIL",
               sum(row["state"] == "reused" for row in results), len(selected), build_seconds, gate_seconds), flush=True)
        if status == RETRY:
            print("verification: inputs changed while queued or running; no new success receipts retained", file=sys.stderr)
            causes = report["stability_diagnostics"]["reasons"]
            if causes:
                print("verification: invalidated input " + json.dumps(causes[0], ensure_ascii=True), file=sys.stderr)
        if budget_report["exceeded"]:
            print("verification: advisory loop budget exceeded: %.3fs > %.3fs (queue excluded)" %
                  (observed_work, warn_after), file=sys.stderr)
        return report_status if report_status >= 0 else 128 - report_status


def parse_options(options: list[str]) -> list[str]:
    """Only full-gate build controls; no target, prefix, cache-root or runner overrides."""
    if options[:1] == ["--"]:
        options = options[1:]
    component_source_files(options)  # Reject missing or ambiguous packaging inputs.
    allowed_values = {"--maxrss", "--summary"}
    index = 0
    while index < len(options):
        arg = options[index]
        if arg in allowed_values:
            index += 1
            if index >= len(options) or options[index].startswith("-"):
                raise VerificationError("missing value for " + arg)
        elif not (arg.partition("=")[0] in COMPONENT_SOURCE_OPTIONS
                  or re.fullmatch(r"-j[1-9][0-9]*", arg)
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
    selects `$XDG_CACHE_HOME/mylang/<leaf>` or `~/.cache/mylang/<leaf>` only while
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
            roots.append(Path(base) / "mylang" / leaf)
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
    """D3: fail when any used store's log grew during the request or is non-empty."""
    grew = {path: count - before.get(path, 0) for path, count in after.items() if count > before.get(path, 0)}
    nonzero = {path: count for path, count in after.items() if count}
    return {"logs": dict(after), "grew": grew, "nonzero": nonzero, "passed": not grew and not nonzero}


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
    child = dict(environment, MYL_CORE_LEAKCHECK="1")
    results = []
    scratch.mkdir(parents=True, exist_ok=True)
    private = Path(tempfile.mkdtemp(prefix="integration-fact-leak-", dir=scratch))
    try:
        with admission("gate"):
            for suite in suites:
                argv = [str(compiler), "test", suite, "--release", "--verify-facts", "--force", "--json",
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


def integration_status(status: int, forced: dict | None, mismatches: dict) -> int:
    """The request's status after the integration checks; a mismatch is distinct."""
    if not mismatches["passed"]:
        return INTEGRATION_MISMATCH_STATUS
    if status != 0:
        return status
    return 0 if forced is not None and forced["passed"] else 1


def integrate(root: Path, cache: Path, status: int, before: Mapping[str, int],
              environment: Mapping[str, str], run=subprocess.run, admission=None) -> int:
    """Apply D1 and D3 after a complete request; record them in last-run.json."""
    report = read_record(cache / "last-run.json") or {}
    forced = None
    if status == 0:
        suites = fact_leak_suites(report.get("action_metadata"))
        if suites:
            forced = forced_fact_leak_run(root, root / "zig-out/bin/mylang", suites, environment,
                                          cache / "integration", run=run, admission=admission)
        else:
            forced = {"suites": [], "passed": False, "error": "inventory has no fact/leak language members"}
    mismatches = mismatch_verdict(before, mismatch_counts(environment, native_default_sharing(root)))
    final = integration_status(status, forced, mismatches)
    integration = {"version": 1, "request_status": status, "status": final,
                   "forced_fact_leak": forced, "shared_mismatches": mismatches}
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
    if not mismatches["passed"]:
        print("verification: FAIL: shared-store determinism mismatches: " + json.dumps(mismatches["nonzero"], sort_keys=True),
              file=sys.stderr)
    print("verification: integration %s (status %d)" % ("PASS" if final == 0 else "FAIL", final), flush=True)
    return final


def main(argv: list[str]) -> int:
    if argv[:1] == ["--admitted"]:
        return admitted_child(int(argv[1]))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zig", default=os.environ.get("MYLANG_ZIG") or os.environ.get("ZIG") or "zig")
    parser.add_argument("--profile", choices=verification_profiles.PROFILES, default="complete")
    parser.add_argument("--quick-actions", type=int, default=3, help="Maximum quick-profile pending actions; heuristic and partial")
    parser.add_argument("--qualification-target", action="append", choices=verification_qualification.OBLIGATIONS)
    parser.add_argument("--qualification-max-actions", type=int, default=4)
    parser.add_argument("--qualification-timeout", type=float, default=300)
    parser.add_argument("--qualification-fuzz-steps", type=int, default=8)
    parser.add_argument("--force", action="store_true", help="Ignore prior successes for the requested profile")
    parser.add_argument("--dry-run", action="store_true",
                        help="Prepare and compute every action key and reuse verdict, write %s/dry-run.json, "
                             "and run no gate" % CACHE_DIRECTORY)
    parser.add_argument("--shared-cache-dir", help="Shared success evidence (default: $%s, else off; an empty value disables); inventory and runs stay private" % SHARED_CACHE_VARIABLE)
    parser.add_argument("--build-timeout-seconds", type=float, help="Optional deadline per admitted preparation command; excludes queue time")
    parser.add_argument("--gate-timeout-seconds", type=float, help="Optional deadline for the admitted selected gate; excludes queue time")
    parser.add_argument("--warn-after-seconds", type=float, help="Advisory total work target excluding admission queues; never changes reuse or pass/fail")
    parser.add_argument("--budget-policy", type=Path, help="Optional v1/v2 report-only scoped policy; never changes reuse or pass/fail")
    parser.add_argument("--timing-window-seconds", type=float,
                        help="Own an exclusive bounded request measurement; run directly, never under a slot")
    parser.add_argument("--integration", action="store_true",
                        help="Integration gate: the complete profile, then one forced fact/leak run of the language "
                             "members (D1), failing with status %d on any shared-store mismatch (D3)" % INTEGRATION_MISMATCH_STATUS)
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
            with ExitStack() as stack:
                if args.timing_window_seconds is not None:
                    stack.enter_context(verification_measurement.timing_window(
                        args.timing_window_seconds, coordinator_lock_wait_seconds=lock_wait))
                before = mismatch_counts(os.environ, native_default_sharing()) if args.integration else {}
                status = execute(ROOT, cache, Path(resolved).absolute(), parse_options(args.options), args.force, shared_cache_dir,
                               build_timeout=args.build_timeout_seconds, gate_timeout=args.gate_timeout_seconds,
                               warn_after=args.warn_after_seconds, budget_policy=args.budget_policy,
                               profile=args.profile, quick_actions=args.quick_actions,
                               qualification_targets=args.qualification_target,
                               qualification_max_actions=args.qualification_max_actions,
                               qualification_timeout=args.qualification_timeout,
                               qualification_fuzz_steps=args.qualification_fuzz_steps,
                               shared_cache_source=shared_cache_source, dry_run=args.dry_run)
                if args.integration:
                    status = integrate(ROOT, cache, status, before, os.environ)
                return status
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

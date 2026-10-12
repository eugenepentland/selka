#!/usr/bin/env python3
"""Acceptance matrix for the output-keyed, path-free, shared verification plan.

Runs the thirteen rows of Section 4 of
docs/audits/output-keyed-shared-receipts-plan-2026-10-12.md as independent,
re-runnable cases against a target worktree (`--tree PATH`), writes per-row JSON
evidence under `evidence/<row-id>/` and a `summary.json`, and judges every row
mechanically against the plan's expected decision where a report field exists.
A check whose field or mechanism does not exist on the target tree is recorded
as "not-judged" with the reason; it is never counted as a pass.

This is developer tooling under experiments/: it is never part of the install
graph and is run with `python3 -B`. Builds and `mylang` runs go through
`scripts/build-slot.sh build`; complete verification goes through the
coordinator, which owns its own admission. See README.md.
"""

from __future__ import annotations

import argparse
import dataclasses
import datetime
import hashlib
import json
import os
import re
import shlex
import shutil
import struct
import subprocess
import sys
import time
from pathlib import Path
from typing import Callable

HERE = Path(__file__).resolve().parent
PLAN = "docs/audits/output-keyed-shared-receipts-plan-2026-10-12.md"
SCHEMA = "output-keyed-matrix-v1"

# --- cache.reason vocabulary of `mylang test --json` -------------------------
# IR-tier hits exist today; execution-tier hits are named by plan Section 2.1.
IR_HIT_REASONS = frozenset({"receipt-hit", "whole-receipt-hit", "whole-report-hit", "shared-receipt-hit"})
EXEC_HIT_REASONS = frozenset({"exec-receipt-hit", "whole-exec-receipt-hit"})
HIT_REASONS = IR_HIT_REASONS | EXEC_HIT_REASONS | {"property-prefix-hit"}
# Reasons that make a test legitimately execute on every run (not eligible for a
# receipt). `verify-facts`, `leak-check` and `missing-cache-plan` are deliberately
# absent: the plan expects those tests to hit.
INELIGIBLE_REASONS = frozenset({"live-effects", "native-links", "uncacheable-toolchain",
                                "untracked-loader-environment", "uncacheable-metadata",
                                "configured-skip", "unsupported"})
EXECUTED_STATUSES = frozenset({"passed", "failed"})

PASS, FAIL, NOT_JUDGED = "pass", "fail", "not-judged"


# =============================================================================
# BLAKE3 (hash mode), used only to forge a consistent shared-store record for
# row 10. The forger first recomputes the digest of the original payload and
# refuses to continue unless it equals the digest the compiler recorded, so a
# defect here can never produce a silent false result.
# =============================================================================
_IV = (0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A, 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19)
_PERMUTATION = (2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8)
_CHUNK_START, _CHUNK_END, _PARENT, _ROOT = 1, 2, 4, 8
_MASK = 0xFFFFFFFF


def _g(s, a, b, c, d, x, y):
    s[a] = (s[a] + s[b] + x) & _MASK
    v = s[d] ^ s[a]
    s[d] = ((v >> 16) | (v << 16)) & _MASK
    s[c] = (s[c] + s[d]) & _MASK
    v = s[b] ^ s[c]
    s[b] = ((v >> 12) | (v << 20)) & _MASK
    s[a] = (s[a] + s[b] + y) & _MASK
    v = s[d] ^ s[a]
    s[d] = ((v >> 8) | (v << 24)) & _MASK
    s[c] = (s[c] + s[d]) & _MASK
    v = s[b] ^ s[c]
    s[b] = ((v >> 7) | (v << 25)) & _MASK


def _compress(cv, words, counter, block_len, flags):
    s = list(cv) + list(_IV[:4]) + [counter & _MASK, (counter >> 32) & _MASK, block_len, flags]
    m = list(words)
    for round_index in range(7):
        _g(s, 0, 4, 8, 12, m[0], m[1])
        _g(s, 1, 5, 9, 13, m[2], m[3])
        _g(s, 2, 6, 10, 14, m[4], m[5])
        _g(s, 3, 7, 11, 15, m[6], m[7])
        _g(s, 0, 5, 10, 15, m[8], m[9])
        _g(s, 1, 6, 11, 12, m[10], m[11])
        _g(s, 2, 7, 8, 13, m[12], m[13])
        _g(s, 3, 4, 9, 14, m[14], m[15])
        if round_index < 6:
            m = [m[i] for i in _PERMUTATION]
    return [s[i] ^ s[i + 8] for i in range(8)] + [s[i + 8] ^ cv[i] for i in range(8)]


def _words(block):
    return struct.unpack("<16I", block.ljust(64, b"\0"))


def _chunk_output(chunk, index):
    cv = _IV
    blocks = [chunk[i:i + 64] for i in range(0, len(chunk), 64)] or [b""]
    for position, block in enumerate(blocks):
        flags = _CHUNK_START if position == 0 else 0
        if position == len(blocks) - 1:
            return cv, _words(block), index, len(block), flags | _CHUNK_END
        cv = _compress(cv, _words(block), index, 64, flags)[:8]
    raise AssertionError("unreachable")


def _chaining_value(output):
    return _compress(*output)[:8]


def _parent_output(left, right):
    return _IV, tuple(left) + tuple(right), 0, 64, _PARENT


def blake3(data: bytes) -> bytes:
    """The 32-byte BLAKE3 digest of DATA (unkeyed hash mode)."""
    chunks = [data[i:i + 1024] for i in range(0, len(data), 1024)] or [b""]
    stack = []
    for index, chunk in enumerate(chunks[:-1]):
        cv = _chaining_value(_chunk_output(chunk, index))
        total = index + 1
        while total & 1 == 0:
            cv = _chaining_value(_parent_output(stack.pop(), cv))
            total >>= 1
        stack.append(cv)
    output = _chunk_output(chunks[-1], len(chunks) - 1)
    while stack:
        output = _parent_output(stack.pop(), _chaining_value(output))
    cv, words, counter, block_len, flags = output
    return struct.pack("<8I", *_compress(cv, words, counter, block_len, flags | _ROOT)[:8])


# Shared compiler artifact record layout (src/shared_artifact_store.zig, v2):
# magic, kind byte, 32-byte key, little-endian u64 size, 32-byte BLAKE3 digest.
BLOB_MAGIC = b"selka-compiler-blob-v1\x00"
BLOB_HEADER = len(BLOB_MAGIC) + 1 + 32 + 8 + 32


def forge_blob(data: bytes) -> bytes:
    """A record under the same key whose payload differs in its last byte and
    whose header digest is recomputed, so it is valid but disagrees."""
    if not data.startswith(BLOB_MAGIC) or len(data) <= BLOB_HEADER:
        raise ValueError("not a selka-compiler-blob-v1 record")
    size_at = len(BLOB_MAGIC) + 33
    size = struct.unpack("<Q", data[size_at:size_at + 8])[0]
    payload = data[BLOB_HEADER:]
    if size != len(payload):
        raise ValueError("record size field disagrees with payload")
    recorded = data[size_at + 8:size_at + 40]
    if blake3(payload) != recorded:
        raise ValueError("BLAKE3 self-check failed against the compiler's recorded digest")
    forged = payload[:-1] + bytes([payload[-1] ^ 0xFF])
    return data[:size_at + 8] + blake3(forged) + forged


# =============================================================================
# Report parsing and judging (pure functions; unit-tested in matrix_test.py)
# =============================================================================

def parse_test_report(text: str) -> dict | None:
    """The last JSON object on stdout carrying a `tests` array, or None."""
    for line in reversed(text.splitlines()):
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict) and isinstance(value.get("tests"), list):
            return value
    return None


def parse_cache_report(text: str) -> dict | None:
    """The last `cache-report-v1` JSON line on a `mylang build --report` output."""
    for line in reversed(text.splitlines()):
        line = line.strip()
        if line.startswith("{") and "cache-report-v1" in line:
            try:
                return json.loads(line)
            except json.JSONDecodeError:
                continue
    return None


def test_reason(test: dict) -> str:
    cache = test.get("cache")
    if isinstance(cache, dict) and isinstance(cache.get("reason"), str):
        return cache["reason"]
    return ""


def eligible(test: dict) -> bool:
    return test.get("status") not in ("skipped", "unsupported") and test_reason(test) not in INELIGIBLE_REASONS


def summarize_tests(report: dict | None) -> dict:
    """Counts by status and reason, and the eligible/executed/hit split."""
    if report is None:
        return {"available": False}
    tests = report.get("tests", [])
    by_status: dict[str, int] = {}
    by_reason: dict[str, int] = {}
    summary = {"available": True, "total": len(tests), "eligible": 0, "eligible_executed": 0,
               "eligible_cached": 0, "ir_hits": 0, "exec_hits": 0, "failed": 0,
               "executed_names": [], "failed_names": []}
    for test in tests:
        status = test.get("status", "")
        reason = test_reason(test)
        by_status[status] = by_status.get(status, 0) + 1
        by_reason[reason] = by_reason.get(reason, 0) + 1
        if status == "failed":
            summary["failed"] += 1
            summary["failed_names"].append(test.get("name"))
        if reason in IR_HIT_REASONS and status == "cached":
            summary["ir_hits"] += 1
        if reason in EXEC_HIT_REASONS and status == "cached":
            summary["exec_hits"] += 1
        if eligible(test):
            summary["eligible"] += 1
            if status in EXECUTED_STATUSES:
                summary["eligible_executed"] += 1
                summary["executed_names"].append(test.get("name"))
            elif status == "cached":
                summary["eligible_cached"] += 1
    summary["by_status"] = dict(sorted(by_status.items()))
    summary["by_reason"] = dict(sorted(by_reason.items()))
    summary["exec_receipts"] = report.get("exec_receipts")
    for key in ("executed_names", "failed_names"):
        summary[key] = sorted(name for name in summary[key] if isinstance(name, str))[:200]
    return summary


def outcome_class(status: str) -> str:
    """A verdict's meaning, with a replayed pass equal to an executed pass."""
    return {"cached": "pass", "passed": "pass", "failed": "fail"}.get(status, status)


def verdict_map(report: dict | None) -> dict[str, str]:
    if report is None:
        return {}
    return {test.get("name"): outcome_class(test.get("status", "")) for test in report.get("tests", [])}


def check(name: str, expected, observed, ok: bool | None, note: str = "") -> dict:
    """One judged check. OK None means the field or mechanism is absent."""
    return {"check": name, "expected": expected, "observed": observed,
            "result": NOT_JUDGED if ok is None else PASS if ok else FAIL, "note": note}


def gated(name: str, expected, observed, ok: bool | None, feature: str, features: dict) -> dict:
    """A check whose decision needs FEATURE on the target tree; otherwise not judged."""
    if not features.get(feature):
        return check(name, expected, observed, None,
                     "not judged: target tree lacks feature '%s' (%s)" % (feature, FEATURE_NOTES.get(feature, "")))
    return check(name, expected, observed, ok)


def find_keys(value, needle: str, path: str = "") -> list[tuple[str, object]]:
    """Every (path, value) whose key contains NEEDLE, depth-first."""
    found = []
    if isinstance(value, dict):
        for key, item in value.items():
            here = path + "." + key if path else key
            if needle in key:
                found.append((here, item))
            found.extend(find_keys(item, needle, here))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            found.extend(find_keys(item, needle, "%s[%d]" % (path, index)))
    return found


def decide(checks: list[dict]) -> str:
    """Aggregate check results: any fail fails; all pass passes; some pass with
    the rest not judged is partial; nothing judged is not-judged."""
    results = [item["result"] for item in checks]
    if not results:
        return NOT_JUDGED
    if FAIL in results:
        return FAIL
    if all(result == PASS for result in results):
        return PASS
    if PASS in results:
        return "partial"
    return NOT_JUDGED


def aggregate(decisions: list[str]) -> str:
    """A row's decision from its sub-cases' decisions."""
    if not decisions:
        return NOT_JUDGED
    for severe in ("error", FAIL):
        if severe in decisions:
            return severe
    judged = [d for d in decisions if d != "skipped"]
    if not judged:
        return "skipped"
    if all(d == PASS for d in judged):
        return PASS
    if any(d in (PASS, "partial") for d in judged):
        return "partial"
    return NOT_JUDGED


# --- warm-rerun judging shared by rows 1, 6, 8, 9, 13 ------------------------

def judge_all_hit(label: str, summary: dict, *, feature: str | None = None, features: dict | None = None) -> list[dict]:
    """A run in which every eligible test must be served from a receipt."""
    if not summary.get("available"):
        return [check(label + ": report parsed", "a native-tests JSON report", "missing", False)]
    observed = {"eligible": summary["eligible"], "eligible_executed": summary["eligible_executed"],
                "eligible_cached": summary["eligible_cached"], "by_reason": summary["by_reason"]}
    ok = summary["eligible_executed"] == 0 and summary["eligible_cached"] > 0
    if feature is not None:
        return [gated(label + ": every eligible test reused", "0 eligible executed", observed, ok, feature, features or {})]
    return [check(label + ": every eligible test reused", "0 eligible executed", observed, ok)]


def judge_none_hit(label: str, summary: dict, *, feature: str | None = None, features: dict | None = None) -> list[dict]:
    """A run in which no eligible test may be served from a receipt."""
    if not summary.get("available"):
        return [check(label + ": report parsed", "a native-tests JSON report", "missing", False)]
    observed = {"eligible": summary["eligible"], "eligible_cached": summary["eligible_cached"],
                "by_reason": summary["by_reason"]}
    ok = summary["eligible_cached"] == 0 and summary["eligible"] > 0
    if feature is not None:
        return [gated(label + ": no eligible test reused", "0 eligible cached", observed, ok, feature, features or {})]
    return [check(label + ": no eligible test reused", "0 eligible cached", observed, ok)]


def judge_no_failures(label: str, summary: dict, status: int | None) -> list[dict]:
    if not summary.get("available"):
        return [check(label + ": report parsed", "a native-tests JSON report", "missing", False)]
    return [check(label + ": no failures", "exit 0 and 0 failed",
                  {"exit": status, "failed": summary["failed"], "failed_names": summary["failed_names"]},
                  status == 0 and summary["failed"] == 0)]


def judge_exec_tier(label: str, summary: dict, features: dict) -> list[dict]:
    """Row 2: after a front-end comment edit every eligible test is an execution-receipt hit."""
    if not summary.get("available"):
        return [check(label + ": report parsed", "a native-tests JSON report", "missing", False)]
    reasons = summary["by_reason"]
    checks = [
        check(label + ": IR keys miss", "0 IR-tier hits", {"ir_hits": summary["ir_hits"], "by_reason": reasons},
              summary["ir_hits"] == 0),
        gated(label + ": 100% exec-receipt-hit", "every eligible test cached by an exec reason",
              {"eligible": summary["eligible"], "exec_hits": summary["exec_hits"]},
              summary["eligible"] > 0 and summary["exec_hits"] == summary["eligible"], "exec_receipts", features),
        check(label + ": zero trials", "0 eligible tests executed", summary["eligible_executed"],
              summary["eligible_executed"] == 0 if features.get("exec_receipts") else None,
              "" if features.get("exec_receipts") else "not judged: without execution receipts every test executes after a compiler edit"),
    ]
    receipts = summary.get("exec_receipts")
    if isinstance(receipts, dict) and "hits" in receipts:
        checks.append(check(label + ": exec_receipts.hits equals eligible", summary["eligible"], receipts,
                            receipts.get("hits") == summary["eligible"]))
    else:
        checks.append(check(label + ": exec_receipts report field", "{hits, saves}", receipts, None,
                            "not judged: report has no exec_receipts field"))
    compiled = [value for path, value in find_keys(receipts or {}, "compiled") if isinstance(value, int)]
    checks.append(check(label + ": zero zig cc", 0, compiled or None, (sum(compiled) == 0) if compiled else None,
                        "" if compiled else "not judged: no compiled-unit counter in the test report"))
    return checks


# --- coordinator (verify_cache.py) judging ------------------------------------

def action_rows(report: dict | None) -> dict[str, dict]:
    if not isinstance(report, dict):
        return {}
    return {row.get("id"): row for row in report.get("actions", []) if isinstance(row, dict)}


def judge_coordinator_warm(label: str, report: dict | None, previous: dict | None = None) -> list[dict]:
    """Row 1: an unchanged repeat reuses every cacheable action."""
    if not isinstance(report, dict):
        return [check(label + ": last-run.json read", "a coordinator report", "missing", False)]
    rows = action_rows(report)
    states: dict[str, int] = {}
    for row in rows.values():
        states[row.get("state")] = states.get(row.get("state"), 0) + 1
    executed = sorted(name for name, row in rows.items() if row.get("state") not in ("reused", "fresh"))
    fresh = sorted(name for name, row in rows.items() if row.get("state") == "fresh")
    checks = [
        check(label + ": success", True, {"success": report.get("success"), "status": report.get("status")},
              report.get("success") is True),
        check(label + ": every cacheable action reused", "no action outside reused/fresh",
              {"states": states, "not_reused": executed}, not executed),
        check(label + ": always-fresh actions listed", "policy-fresh groups only", fresh, True,
              "informational: the plan expects only host-fresh collectors here"),
    ]
    if previous is not None:
        before = {name: row.get("action_key") for name, row in action_rows(previous).items()}
        after = {name: row.get("action_key") for name, row in rows.items()}
        changed = sorted(name for name in set(before) | set(after) if before.get(name) != after.get(name))
        checks.append(check(label + ": action keys stable across the repeat", "0 changed", changed, not changed))
    return checks


def language_executed(report: dict | None) -> int | None:
    """Tests the `language` action's members executed, when telemetry knows it."""
    row = action_rows(report).get("language")
    if row is None:
        return None
    total = 0
    for member in row.get("test_telemetry") or []:
        executed = member.get("executed") if isinstance(member, dict) else None
        if not isinstance(executed, int):
            return None
        total += executed
    return total


def judge_language_zero(label: str, report: dict | None) -> list[dict]:
    executed = language_executed(report)
    row = action_rows(report).get("language", {})
    observed = {"state": row.get("state"), "reason": row.get("reason"), "executed_tests": executed}
    if row.get("state") == "reused":
        return [check(label + ": language fact/leak members execute zero tests", 0, observed, True,
                      "the whole language action was reused")]
    if executed is None:
        return [check(label + ": language fact/leak members execute zero tests", 0, observed, None,
                      "not judged: language member test telemetry is unknown on this tree")]
    return [check(label + ": language fact/leak members execute zero tests", 0, observed, executed == 0)]


def judge_two_worktrees(report_a: dict | None, report_b: dict | None) -> list[dict]:
    """Row 7: the second worktree reuses every group except the always-fresh collectors."""
    if not isinstance(report_a, dict) or not isinstance(report_b, dict):
        return [check("coordinator reports read", "two last-run.json", [report_a is not None, report_b is not None], False)]
    a, b = action_rows(report_a), action_rows(report_b)
    differing = sorted(name for name in set(a) | set(b) if a.get(name, {}).get("action_key") != b.get(name, {}).get("action_key"))
    not_reused = sorted(name for name, row in b.items() if row.get("state") not in ("reused", "fresh"))
    checks = [
        check("worktree B success", True, report_b.get("success"), report_b.get("success") is True),
        check("all action keys identical across worktrees", "0 differing (plan: 46 actions)",
              {"actions": len(b), "differing": differing}, not differing and len(a) == len(b) and len(b) > 0),
        check("worktree B reuses every group except always-fresh", "no action outside reused/fresh",
              not_reused, not not_reused),
        check("budget context identical", True, report_a.get("budget_context") == report_b.get("budget_context"),
              report_a.get("budget_context") == report_b.get("budget_context")),
    ]
    flags = [row.get("path_free") for row in b.values()]
    if any(flag is not None for flag in flags):
        checks.append(check("every action identity path-free", True,
                            sorted(name for name, row in b.items() if row.get("path_free") is not True),
                            all(flag is True for flag in flags)))
    else:
        checks.append(check("every action identity path-free", True, None, None,
                            "not judged: last-run.json has no per-action path_free field"))
    return checks


def count_occurrences(path: Path, needle: bytes) -> int:
    """`grep -a -c`-style evidence: occurrences of NEEDLE in a binary."""
    try:
        return path.read_bytes().count(needle)
    except OSError:
        return -1


# =============================================================================
# Steps, rows and execution
# =============================================================================

@dataclasses.dataclass
class Cmd:
    """A command. ARGV items may hold `{name}` placeholders filled from state at
    run time. SLOT 'build' wraps it in scripts/build-slot.sh build."""
    name: str
    argv: list[str]
    cwd: str
    env: dict[str, str] = dataclasses.field(default_factory=dict)
    unset: list[str] = dataclasses.field(default_factory=list)
    slot: str | None = None
    parse: str | None = None  # "tests" | "cache-report" | "coordinator"
    always: bool = False      # cleanup: run even after an earlier failure
    required: bool = False    # a non-zero exit stops the sub-case (builds)

    def render(self, tree: str) -> str:
        parts = ["cd " + shlex.quote(self.cwd), "&&"]
        if self.unset:
            parts += ["env"] + ["-u " + name for name in self.unset]
        parts += ["%s=%s" % (k, shlex.quote(v)) for k, v in sorted(self.env.items())]
        if self.slot:
            parts += [shlex.quote(str(Path(tree) / "scripts/build-slot.sh")), self.slot]
        parts += [shlex.quote(item) if "{" not in item else item for item in self.argv]
        return " ".join(parts)


@dataclasses.dataclass
class Py:
    """An in-process action (edit, restore, forge, worktree add/remove)."""
    name: str
    description: str
    action: Callable[["Run"], dict]
    always: bool = False


@dataclasses.dataclass
class Subcase:
    name: str
    heavy: bool
    plan: Callable[["Context"], list]
    judge: Callable[["Run"], list[dict]]
    needs: tuple[str, ...] = ()


@dataclasses.dataclass
class Row:
    number: int
    slug: str
    case: str
    expected: str
    subcases: list[Subcase]

    @property
    def id(self) -> str:
        return "%02d-%s" % (self.number, self.slug)


FEATURE_NOTES = {
    "runner_identity": "build_identity.zig emits runner_identity (Lane A)",
    "exec_receipts": "execution receipts: 'exec-receipt-hit' in src/core/test_runner*.zig (Lane B)",
    "exec_receipts_opt_in": "MYLANG_TEST_EXEC_RECEIPTS switch present (Lane B, rollout week 2)",
    "fact_leak_receipts": "verify-facts/leak-check no longer refuse receipts (Lane B, D1)",
    "test_v3_namespaces": "receipts-v3 / native-tests-v3 namespaces in src/core (Lane B, D4)",
    "coordinator_v3": "verification-v3 in scripts/verify_cache.py (Lane D, D4)",
    "coordinator_path_free": "per-action path_free in last-run.json (Lane D)",
    "mismatch_counter": "mismatches.log and the determinism-mismatch counter (Lane E, D3)",
    "build_env": "build_env.zig host tool and its built binary (Lane A/C)",
    "execution_key_report": "per-test cache.execution_key in the test report (Lane B)",
}


def _grep(tree: Path, patterns: list[str], needle: str) -> bool:
    for pattern in patterns:
        for path in tree.glob(pattern):
            try:
                if needle in path.read_text(errors="replace"):
                    return True
            except OSError:
                continue
    return False


def probe_features(tree: Path) -> dict[str, bool]:
    """Static probes of the target tree; they decide which checks can be judged."""
    receipt = tree / "src/core/test_runner_receipt.zig"
    receipt_text = receipt.read_text(errors="replace") if receipt.exists() else ""
    exec_receipts = _grep(tree, ["src/core/test_runner*.zig"], "exec-receipt-hit")
    return {
        "runner_identity": _grep(tree, ["build_identity.zig"], "runner_identity"),
        "exec_receipts": exec_receipts,
        "exec_receipts_opt_in": _grep(tree, ["src/core/*.zig", "src/*.zig"], "MYLANG_TEST_EXEC_RECEIPTS"),
        "fact_leak_receipts": exec_receipts and 'return "verify-facts"' not in receipt_text,
        "test_v3_namespaces": _grep(tree, ["src/core/*.zig"], "receipts-v3") or _grep(tree, ["src/core/*.zig"], "native-tests-v3"),
        "coordinator_v3": _grep(tree, ["scripts/verify_cache.py"], "verification-v3"),
        "coordinator_path_free": _grep(tree, ["scripts/verify_cache.py"], "path_free"),
        "mismatch_counter": _grep(tree, ["src/*.zig", "src/core/*.zig"], "mismatches.log"),
        "build_env": (tree / "build_env.zig").exists(),
        "execution_key_report": _grep(tree, ["src/core/test_runner_report.zig"], "execution_key"),
    }


class Context:
    def __init__(self, args):
        self.tree = Path(args.tree).resolve()
        self.work = Path(args.work).resolve() if args.work else HERE / "work"
        self.evidence = Path(args.evidence).resolve() if args.evidence else HERE / "evidence"
        self.dry_run = args.dry_run
        self.keep_work = args.keep_work
        self.lang_entry = args.lang_entry
        self.small_entry = args.small_entry
        self.old_ref = args.old_ref
        self.build_env = args.build_env
        self.zig = os.environ.get("ZIG") or os.environ.get("MYLANG_ZIG") or "$ZIG"
        self.features = probe_features(self.tree)
        self.head = git(self.tree, "rev-parse", "HEAD") or "unknown"
        self.args = vars(args)

    # Paths -----------------------------------------------------------------
    def row_work(self, row_id: str, sub: str) -> Path:
        return self.work / row_id / sub

    def scratch(self, label: str) -> Path:
        # Scratch worktrees sit directly under work/ so that the build's
        # `../guardian-zig` dependency resolves through work/guardian-zig.
        return self.work / label

    def compiler(self, tree: Path) -> str:
        return str(tree / "zig-out/bin/mylang")

    def keyed_extra(self) -> dict[str, str]:
        """Keyed opt-in switches the rollout requires (plan Section 7)."""
        return {"MYLANG_TEST_EXEC_RECEIPTS": "1"} if self.features.get("exec_receipts_opt_in") else {}

    def tree_env(self, tree: Path, **extra) -> dict[str, str]:
        """What sourcing dev-env.sh in TREE sets per tree, plus EXTRA."""
        env = {"ZIG_LOCAL_CACHE_DIR": str(tree / ".zig-cache"), "TMPDIR": str(tree / ".tmp/work"), "PWD": str(tree)}
        env.update(extra)
        return env

    def test_env(self, tree: Path, row_dir: Path, **extra) -> dict[str, str]:
        """Tree env plus row-private shared stores so other agents' stores never
        decide a row (row 7 passes one store to both trees on purpose)."""
        env = self.tree_env(tree, MYLANG_TEST_SHARED_CACHE=str(row_dir / "shared-tests"),
                            MYLANG_COMPILER_SHARED_CACHE=str(row_dir / "shared-compiler"))
        env.update(self.keyed_extra())
        env.update(extra)
        return env


def git(tree: Path, *args: str) -> str | None:
    try:
        return subprocess.run(["git", "-C", str(tree), *args], check=True, capture_output=True, text=True).stdout.strip()
    except (subprocess.CalledProcessError, OSError):
        return None


def sha256_file(path: Path) -> str | None:
    try:
        digest = hashlib.sha256()
        with open(path, "rb") as handle:
            for block in iter(lambda: handle.read(1 << 20), b""):
                digest.update(block)
        return digest.hexdigest()
    except OSError:
        return None


def now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds")


ENV_PROJECTION_PREFIXES = ("MYL_", "MYLANG_", "SELKA_", "ZIG", "LD_", "LC_", "PYTHON")
ENV_PROJECTION_NAMES = ("TMPDIR", "SOURCE_DATE_EPOCH", "ZERO_AR_DATE", "LANG", "TZ", "HOME", "XDG_CACHE_HOME")
ENV_PRESENCE_ONLY = ("CODEX_THREAD_ID", "TERM", "PWD")


def environment_projection(env: dict[str, str]) -> dict:
    """The manifest's environment: keyed-looking names with values, launcher
    names by presence and digest only."""
    values = {name: value for name, value in env.items()
              if name.startswith(ENV_PROJECTION_PREFIXES) or name in ENV_PROJECTION_NAMES}
    presence = {name: hashlib.sha256(env[name].encode()).hexdigest()[:16] if name in env else None
                for name in ENV_PRESENCE_ONLY}
    return {"values": dict(sorted(values.items())), "launcher_sha256_16": presence}


class Run:
    """One sub-case execution: steps, their results and shared state."""

    def __init__(self, ctx: Context, row: Row, sub: Subcase):
        self.ctx, self.row, self.sub = ctx, row, sub
        self.dir = ctx.evidence / row.id / sub.name
        self.state: dict[str, object] = {}
        self.results: dict[str, dict] = {}
        self.compilers: dict[str, str | None] = {}

    def result(self, name: str) -> dict:
        return self.results.get(name, {})

    def tests(self, name: str) -> dict:
        return summarize_tests(self.result(name).get("parsed"))

    def report(self, name: str) -> dict | None:
        return self.result(name).get("parsed")

    def status(self, name: str) -> int | None:
        return self.result(name).get("exit")

    def execute(self, steps: list) -> str | None:
        self.dir.mkdir(parents=True, exist_ok=True)
        failure = None
        for index, step in enumerate(steps):
            if failure is not None and not step.always:
                self.results[step.name] = {"step": step.name, "skipped": "an earlier step failed: " + failure}
                continue
            try:
                if isinstance(step, Py):
                    started = time.monotonic()
                    record = {"step": step.name, "kind": "python", "description": step.description, "started": now()}
                    record["result"] = step.action(self)
                    record["seconds"] = round(time.monotonic() - started, 3)
                    self.results[step.name] = record
                else:
                    self.results[step.name] = self.run_command(index, step)
                    if step.required and self.results[step.name]["exit"] != 0:
                        raise RuntimeError("required step exited %d: %s" % (
                            self.results[step.name]["exit"], self.results[step.name]["stderr_tail"][-600:]))
            except Exception as error:  # noqa: BLE001 - recorded as row evidence
                self.results[step.name] = {"step": step.name, "error": "%s: %s" % (type(error).__name__, error)}
                if failure is None:
                    failure = step.name
        return failure

    def run_command(self, index: int, step: Cmd) -> dict:
        argv = [item.format(**{k: str(v) for k, v in self.state.items()}) if "{" in item else item for item in step.argv]
        env = dict(os.environ)
        for name in step.unset:
            env.pop(name, None)
        env.update(step.env)
        for directory in ("TMPDIR",):
            if directory in step.env:
                Path(step.env[directory]).mkdir(parents=True, exist_ok=True)
        full = ([str(self.ctx.tree / "scripts/build-slot.sh"), step.slot] if step.slot else []) + argv
        compiler = next((item for item in argv if item.endswith(("/zig-out/bin/mylang", "/zig-out/focus/mylang"))), None)
        if compiler and compiler not in self.compilers:
            self.compilers[compiler] = sha256_file(Path(compiler))
        stem = "%02d-%s" % (index, step.name)
        started_at, started = now(), time.monotonic()
        completed = subprocess.run(full, cwd=step.cwd, env=env, capture_output=True, text=True, errors="replace")
        seconds = round(time.monotonic() - started, 3)
        (self.dir / (stem + ".stdout")).write_text(completed.stdout)
        (self.dir / (stem + ".stderr")).write_text(completed.stderr)
        queue = admission_queue_seconds(completed.stderr) if step.slot else 0
        record = {"step": step.name, "kind": "command", "argv": full, "cwd": step.cwd,
                  "queue_seconds": queue,
                  "seconds_excluding_queue": None if queue is None else round(seconds - queue, 3),
                  "env_set": step.env, "env_unset": step.unset, "exit": completed.returncode,
                  "started": started_at, "harness_seconds_including_queue": seconds,
                  "stdout": stem + ".stdout", "stderr": stem + ".stderr",
                  "stderr_tail": completed.stderr[-1500:]}
        if step.parse == "tests":
            record["parsed"] = parse_test_report(completed.stdout)
            record["summary"] = summarize_tests(record["parsed"])
        elif step.parse == "cache-report":
            record["parsed"] = parse_cache_report(completed.stdout + "\n" + completed.stderr)
        elif step.parse == "coordinator":
            record["parsed"] = latest_coordinator_report(Path(step.cwd), started)
            if record["parsed"] is not None:
                (self.dir / (stem + ".last-run.json")).write_text(json.dumps(record["parsed"], indent=1, sort_keys=True))
                record["report_copy"] = stem + ".last-run.json"
                record["excerpt"] = [{key: row.get(key) for key in ("id", "state", "reason", "action_key", "path_free")}
                                     for row in record["parsed"].get("actions", [])]
        return record


QUEUE_LINE = re.compile(r"^build-slot: \w+ slot \d+, FIFO ticket \d+ after (\d+)s", re.MULTILINE)


def admission_queue_seconds(stderr: str) -> int | None:
    """The wait `scripts/build-slot.sh` reports before admitting the command."""
    found = QUEUE_LINE.findall(stderr)
    return int(found[-1]) if found else None


def latest_coordinator_report(tree: Path, since_monotonic: float) -> dict | None:
    """The newest `.mylang-cache/verification-v*/last-run.json` of TREE."""
    candidates = sorted(tree.glob(".mylang-cache/verification-v*/last-run.json"), key=lambda p: p.stat().st_mtime)
    if not candidates:
        return None
    try:
        return json.loads(candidates[-1].read_text())
    except (OSError, json.JSONDecodeError):
        return None


# =============================================================================
# Step builders
# =============================================================================

def add_worktree(label: str) -> Py:
    def action(run: Run) -> dict:
        ctx = run.ctx
        path = ctx.scratch(label)
        ctx.work.mkdir(parents=True, exist_ok=True)
        guardian = ctx.work / "guardian-zig"
        source = (ctx.tree / "../guardian-zig").resolve()
        if not guardian.exists() and source.exists():
            guardian.symlink_to(source)
        if path.exists():
            git(ctx.tree, "worktree", "remove", "--force", str(path))
            shutil.rmtree(path, ignore_errors=True)
        git(ctx.tree, "worktree", "prune")
        ref = run.state.get(label + "_ref", ctx.head)
        completed = subprocess.run(["git", "-C", str(ctx.tree), "worktree", "add", "--detach", str(path), str(ref)],
                                   capture_output=True, text=True)
        if completed.returncode != 0:
            raise RuntimeError("git worktree add failed: " + completed.stderr.strip())
        (path / ".tmp/work").mkdir(parents=True, exist_ok=True)
        return {"worktree": str(path), "ref": ref, "head": git(path, "rev-parse", "HEAD"), "guardian": str(source)}
    return Py("worktree-add-" + label, "git worktree add --detach work/%s <target HEAD>" % label, action)


def remove_worktree(label: str) -> Py:
    def action(run: Run) -> dict:
        ctx = run.ctx
        path = ctx.scratch(label)
        if ctx.keep_work:
            return {"kept": str(path)}
        removed = git(ctx.tree, "worktree", "remove", "--force", str(path))
        shutil.rmtree(path, ignore_errors=True)
        git(ctx.tree, "worktree", "prune")
        return {"removed": str(path), "git": removed is not None}
    return Py("worktree-remove-" + label, "git worktree remove --force work/%s" % label, action, always=True)


def build(ctx: Context, tree: Path, name: str = "build", target: str | None = None) -> Cmd:
    argv = ["zig", "build"] + ([target] if target else [])
    return Cmd(name, argv, str(tree), ctx.tree_env(tree), slot="build", required=True)


def mylang_test(ctx: Context, name: str, tree: Path, entry: str, cache: Path, *, compiler: str | None = None,
                flags: tuple[str, ...] = (), env: dict | None = None, unset: tuple[str, ...] = ("MYL_CORE_LEAKCHECK",)) -> Cmd:
    argv = [compiler or ctx.compiler(tree), "test", entry, "--json", "--cache-dir", str(cache), *flags]
    environment = env if env is not None else ctx.test_env(tree, cache.parent)
    return Cmd(name, argv, str(tree), environment, unset=[u for u in unset if u not in environment], slot="build", parse="tests")


def coordinator(ctx: Context, name: str, tree: Path, *extra: str, env: dict | None = None, prefix: tuple[str, ...] = ()) -> Cmd:
    argv = [*prefix, "python3", "-B", "scripts/verify_cache.py", "--zig", ctx.zig, "--profile", "complete", *extra]
    return Cmd(name, argv, str(tree), env if env is not None else ctx.tree_env(tree), parse="coordinator")


def edit(label: str, relative: str, old: str | None, new: str, description: str) -> Py:
    """Replace OLD (exactly once) with NEW in a scratch worktree, or append NEW when OLD is None."""
    def action(run: Run) -> dict:
        path = run.ctx.scratch(label) / relative
        text = path.read_text()
        if old is None:
            updated = text + new
        else:
            if text.count(old) != 1:
                raise RuntimeError("edit anchor occurs %d times in %s (expected 1)" % (text.count(old), relative))
            updated = text.replace(old, new)
        path.write_text(updated)
        return {"file": relative, "before_sha256": hashlib.sha256(text.encode()).hexdigest(),
                "after_sha256": hashlib.sha256(updated.encode()).hexdigest()}
    return Py("edit", "%s: %s" % (relative, description), action)


def restore(label: str, relative: str) -> Py:
    def action(run: Run) -> dict:
        path = run.ctx.scratch(label)
        if not path.exists():
            return {"restored": False, "reason": "worktree absent"}
        completed = subprocess.run(["git", "-C", str(path), "checkout", "--", relative], capture_output=True, text=True)
        return {"restored": completed.returncode == 0, "status": git(path, "status", "--porcelain")}
    return Py("restore", "git checkout -- %s in the scratch worktree" % relative, action, always=True)


def reset_dir(path_of: Callable[[Context], Path], name: str = "reset-work") -> Py:
    def action(run: Run) -> dict:
        path = path_of(run.ctx)
        shutil.rmtree(path, ignore_errors=True)
        path.mkdir(parents=True, exist_ok=True)
        return {"directory": str(path)}
    return Py(name, "empty the row's private work directory", action)


# =============================================================================
# The thirteen rows
# =============================================================================

def entry_for_lang(ctx: Context) -> str:
    return ctx.lang_entry or "tests/lang"


# Row 1 ----------------------------------------------------------------------

def row1_tests(mode: str):
    flags = ("--release", "--verify-facts") if mode == "facts-leak" else ()

    def plan(ctx: Context) -> list:
        work = ctx.row_work("01-unchanged-repeat", "lang-" + mode)
        extra = {"MYL_CORE_LEAKCHECK": "1"} if mode == "facts-leak" else {}
        env = ctx.test_env(ctx.tree, work, **extra)
        entry = entry_for_lang(ctx)
        return [reset_dir(lambda c: c.row_work("01-unchanged-repeat", "lang-" + mode)),
                mylang_test(ctx, "first", ctx.tree, entry, work / "cache", flags=flags, env=env),
                mylang_test(ctx, "repeat", ctx.tree, entry, work / "cache", flags=flags, env=env)]

    def judge(run: Run) -> list[dict]:
        feature = "fact_leak_receipts" if mode == "facts-leak" else None
        return (judge_no_failures("first", run.tests("first"), run.status("first"))
                + judge_no_failures("repeat", run.tests("repeat"), run.status("repeat"))
                + judge_all_hit("repeat", run.tests("repeat"), feature=feature, features=run.ctx.features))
    return plan, judge


def row1_complete_plan(ctx: Context) -> list:
    return [coordinator(ctx, "first", ctx.tree), coordinator(ctx, "repeat", ctx.tree)]


def row1_complete_judge(run: Run) -> list[dict]:
    return (judge_coordinator_warm("repeat", run.report("repeat"), run.report("first"))
            + judge_language_zero("repeat", run.report("repeat")))


# Rows 2-5: compiler, runner and runtime edits in a scratch worktree ---------

ROW3_ANCHOR = '.dict_new => try out.print(arena, "  {s} = call ptr @myl_core_dict_new(i64 {s}, ptr {s})\\n",'
ROW3_REPLACEMENT = '.dict_new => try out.print(arena, "  call void asm sideeffect \\"nop\\", \\"\\"()\\n  {s} = call ptr @myl_core_dict_new(i64 {s}, ptr {s})\\n",'

EDITS = {
    "02-parser-comment": ("src/parser.zig", None, "\n// lane-f row 2: comment-only front-end edit\n",
                          "append a comment line (front end, no code change)"),
    "03-emitter-helper": ("src/core/emit_dict.zig", ROW3_ANCHOR, ROW3_REPLACEMENT,
                          "emit a side-effecting `nop` before every dictionary construction: changes the "
                          "bytes of every program that builds a dictionary, not its meaning"),
    "04-runner-edit": ("src/core/test_runner_execute.zig", None, "\n// lane-f row 4: runner source edit (runner_identity input)\n",
                       "append a comment line to a runner_identity source"),
    "05-runtime-edit": ("src/core/runtime/core_rt.c", None,
                        "\n/* lane-f row 5: runtime object edit */\n__attribute__((used)) static int myl_lane_f_row5_probe(void) { return 5; }\n",
                        "append a retained static function: the runtime object's bytes change"),
}


def edit_row_plan(row_id: str, *, force_compare: bool = False, flags: tuple[str, ...] = ()):
    relative, old, new, description = EDITS[row_id]
    label = "row%s-tree" % row_id.split("-")[0]

    def plan(ctx: Context) -> list:
        tree = ctx.scratch(label)
        work = ctx.row_work(row_id, "edit")
        entry = entry_for_lang(ctx)
        # A row-private object store: new entries in it after the edit are
        # exactly the `zig cc` compiles and links the edited run performed.
        env = ctx.test_env(tree, work, MYLANG_CORE_RUNTIME_CACHE=str(work / "core-runtime"))
        # An edit without its spec-tagged test fails Guardian, which gates the
        # install of zig-out/bin/mylang; `affected-compiler` installs the same
        # compiler ungated at zig-out/focus/mylang, so both sides use that copy.
        focus = str(tree / "zig-out/focus/mylang")
        steps = [reset_dir(lambda c: c.row_work(row_id, "edit")), add_worktree(label),
                 build(ctx, tree, "build-before", "affected-compiler"),
                 mylang_test(ctx, "cold", tree, entry, work / "cache", compiler=focus, flags=flags, env=env),
                 mylang_test(ctx, "warm", tree, entry, work / "cache", compiler=focus, flags=flags, env=env),
                 edit(label, relative, old, new, description), build(ctx, tree, "build-after", "affected-compiler"),
                 store_count(row_id, "stores-before"),
                 mylang_test(ctx, "after-edit", tree, entry, work / "cache", compiler=focus, flags=flags, env=env),
                 store_count(row_id, "stores-after")]
        if force_compare:
            steps.append(mylang_test(ctx, "forced", tree, entry, work / "cache-forced", compiler=focus,
                                     flags=flags + ("--force",), env=env))
        steps += [restore(label, relative), remove_worktree(label)]
        return steps
    return plan


def store_count(row_id: str, name: str) -> Py:
    def action(run: Run) -> dict:
        work = run.ctx.row_work(row_id, "edit")
        count = lambda root: sum(1 for p in root.rglob("*") if p.is_file()) if root.exists() else 0
        return {"objects": count(work / "core-runtime" / "units-v1"),
                "runtime_store_files": count(work / "core-runtime"),
                "programs": sum(count(path) for path in (work / "cache").glob("programs-v*"))}
    return Py(name, "count unit objects and linked programs in the row-private stores", action)


def store_growth(run: Run) -> dict | None:
    before = run.result("stores-before").get("result")
    after = run.result("stores-after").get("result")
    if not before or not after:
        return None
    return {key: after[key] - before[key] for key in before}


def baseline_checks(run: Run) -> list[dict]:
    return judge_all_hit("baseline warm (precondition)", run.tests("warm"))


def row2_judge(run: Run) -> list[dict]:
    after = run.tests("after-edit")
    checks = baseline_checks(run) + judge_no_failures("after-edit", after, run.status("after-edit"))
    checks += judge_exec_tier("after-edit", after, run.ctx.features)
    growth = store_growth(run)
    checks.append(check("after-edit: zero zig cc (no new unit object, no new linked program)",
                        {"objects": 0, "programs": 0}, growth,
                        None if growth is None else growth["objects"] == 0 and growth["programs"] == 0,
                        "" if growth else "not judged: store counts missing"))
    seconds = run.result("after-edit").get("seconds_excluding_queue")
    checks.append(check("after-edit wall time recorded", "lowering and emission only (baseline 78 s, 0 cached)",
                        {"seconds_excluding_queue": seconds,
                         "queue_seconds": run.result("after-edit").get("queue_seconds")}, True,
                        "informational: harness clock minus the build-slot queue; not an exclusive timing window"))
    return checks


def row3_judge(run: Run) -> list[dict]:
    after, forced = run.report("after-edit"), run.report("forced")
    a, f = verdict_map(after), verdict_map(forced)
    differing = sorted(name for name in set(a) | set(f) if a.get(name) != f.get(name))
    summary = run.tests("after-edit")
    checks = baseline_checks(run) + [growth_note(run),
        check("verdicts equal a --force run", "0 differing", {"tests": len(a), "differing": differing[:50]},
              bool(a) and not differing),
        gated("only tests whose program bytes changed execute", "0 < executed < eligible",
              {"eligible": summary.get("eligible"), "executed": summary.get("eligible_executed"),
               "executed_names": summary.get("executed_names", [])[:50]},
              0 < summary.get("eligible_executed", 0) < summary.get("eligible", 0), "exec_receipts", run.ctx.features),
    ]
    # The cold run executed every test, so it reports every execution key; a
    # warm run's IR hits carry none.
    keys_after = execution_keys(after)
    keys_warm = execution_keys(run.report("cold"))
    if keys_after and keys_warm:
        changed = sorted(name for name, key in keys_after.items() if keys_warm.get(name) != key)
        wrong = sorted(t["name"] for t in (after or {}).get("tests", [])
                       if t.get("name") in keys_after and eligible(t)
                       and (keys_warm.get(t["name"]) != keys_after[t["name"]]) != (t.get("status") in EXECUTED_STATUSES))
        checks.append(check("executed set equals changed execution_key set", "0 mismatched",
                            {"changed_keys": len(changed), "mismatched": wrong[:50]}, not wrong))
    else:
        checks.append(check("executed set equals changed execution_key set", "per-test execution_key", None, None,
                            "not judged: the test report carries no per-test cache.execution_key"))
    return checks


def execution_keys(report: dict | None) -> dict[str, str]:
    """Per-test `cache.execution_key` (the program-keyed receipt identity)."""
    keys = {}
    for test in (report or {}).get("tests", []):
        cache = test.get("cache")
        if isinstance(cache, dict) and isinstance(cache.get("execution_key"), str):
            keys[test.get("name")] = cache["execution_key"]
    return keys


def growth_note(run: Run) -> dict:
    return check("store growth recorded", "informational", store_growth(run), True,
                 "new unit objects and linked programs during the edited run")


def row4_judge(run: Run) -> list[dict]:
    after = run.tests("after-edit")
    checks = baseline_checks(run) + judge_no_failures("after-edit", after, run.status("after-edit")) + [growth_note(run)]
    checks.append(gated("every execution receipt misses", "0 exec hits", after.get("exec_hits"),
                        after.get("available") and after.get("exec_hits") == 0, "exec_receipts", run.ctx.features))
    checks.append(check("IR receipts also miss", "0 IR hits", after.get("ir_hits"),
                        after.get("available") and after.get("ir_hits") == 0))
    checks += judge_none_hit("after-edit", after)
    return checks


def row5_judge(run: Run) -> list[dict]:
    after = run.tests("after-edit")
    checks = baseline_checks(run) + judge_no_failures("after-edit", after, run.status("after-edit")) + [growth_note(run)]
    checks.append(gated("every execution receipt misses", "0 exec hits", after.get("exec_hits"),
                        after.get("available") and after.get("exec_hits") == 0, "exec_receipts", run.ctx.features))
    checks.append(check("IR tier outcome recorded", "informational", after.get("ir_hits"), True,
                        "the plan states no IR expectation for a runtime edit"))
    return checks


# Row 6 ----------------------------------------------------------------------

def row6_plan(ctx: Context) -> list:
    work = ctx.row_work("06-fact-leak-modes", "modes")
    entry = entry_for_lang(ctx)
    facts = ctx.test_env(ctx.tree, work)
    leak = ctx.test_env(ctx.tree, work, MYL_CORE_LEAKCHECK="1")
    fact_flags = ("--release", "--verify-facts")
    return [reset_dir(lambda c: c.row_work("06-fact-leak-modes", "modes")),
            mylang_test(ctx, "facts-1", ctx.tree, entry, work / "cache", flags=fact_flags, env=facts),
            mylang_test(ctx, "facts-2", ctx.tree, entry, work / "cache", flags=fact_flags, env=facts),
            mylang_test(ctx, "leak-1", ctx.tree, entry, work / "cache", flags=("--release",), env=leak),
            mylang_test(ctx, "leak-2", ctx.tree, entry, work / "cache", flags=("--release",), env=leak),
            mylang_test(ctx, "facts-3", ctx.tree, entry, work / "cache", flags=fact_flags, env=facts),
            mylang_test(ctx, "facts-forced", ctx.tree, entry, work / "cache", flags=fact_flags + ("--force",), env=facts)]


def row6_judge(run: Run) -> list[dict]:
    f = run.ctx.features
    checks = []
    for name in ("facts-1", "facts-2", "leak-1", "leak-2", "facts-3", "facts-forced"):
        checks += judge_no_failures(name, run.tests(name), run.status(name))
    checks += judge_all_hit("facts-2 (second identical --verify-facts run)", run.tests("facts-2"), feature="fact_leak_receipts", features=f)
    checks += judge_none_hit("leak-1 (leak mode does not hit facts receipts)", run.tests("leak-1"), feature="fact_leak_receipts", features=f)
    checks += judge_all_hit("leak-2 (leak mode hits its own receipt)", run.tests("leak-2"), feature="fact_leak_receipts", features=f)
    checks += judge_all_hit("facts-3 (facts receipts survive a leak run)", run.tests("facts-3"), feature="fact_leak_receipts", features=f)
    checks += judge_none_hit("facts-forced (--force reruns)", run.tests("facts-forced"))
    return checks


# Row 7 ----------------------------------------------------------------------

def row7_env(ctx: Context, tree: Path, shared: Path, side: str, stores: bool = True) -> dict:
    """The launcher of worktree SIDE. The native shared stores are set only for
    its `mylang test` run: the complete gate's own tests assume no shared store
    (see REPORT.md, row 7), and the coordinator shares through
    --shared-cache-dir instead."""
    env = ctx.tree_env(tree, CODEX_THREAD_ID="lane-f-row07-" + side, TERM="xterm-256color" if side == "a" else "dumb",
                       **ctx.keyed_extra())
    if stores:
        env.update(MYLANG_TEST_SHARED_CACHE=str(shared / "tests"), MYLANG_COMPILER_SHARED_CACHE=str(shared / "compiler"))
    return env


def row7_plan(ctx: Context) -> list:
    a, b = ctx.scratch("row07-a"), ctx.scratch("row07-b")
    shared = ctx.row_work("07-two-worktrees", "shared")
    env_a, env_b = row7_env(ctx, a, shared, "a"), row7_env(ctx, b, shared, "b")
    test = lambda name, tree, env: Cmd(name, [ctx.compiler(tree), "test", "tests/lang", "--json"], str(tree), env,
                                       unset=["MYL_CORE_LEAKCHECK"], slot="build", parse="tests")
    verification = ("--shared-cache-dir", str(shared / "verification"))
    return [reset_dir(lambda c: c.row_work("07-two-worktrees", "shared")), add_worktree("row07-a"), add_worktree("row07-b"),
            Cmd("build-a", ["zig", "build"], str(a), env_a, slot="build", required=True),
            Cmd("build-b", ["zig", "build"], str(b), env_b, slot="build", required=True),
            test("tests-a", a, env_a), test("tests-b", b, env_b),
            coordinator(ctx, "complete-a", a, *verification, env=row7_env(ctx, a, shared, "a", stores=False)),
            coordinator(ctx, "complete-b", b, *verification, env=row7_env(ctx, b, shared, "b", stores=False)),
            Py("binary-paths", "grep -a counts of each root path in installed units/core/cli test binaries", row7_binary_paths),
            Py("keep-diagnostics", "copy each tree's coordinator diagnostics (per-action dependency summaries)", row7_keep),
            remove_worktree("row07-a"), remove_worktree("row07-b")]


def row7_keep(run: Run) -> dict:
    copied = {}
    for side in ("row07-a", "row07-b"):
        source = run.ctx.scratch(side) / ".mylang-cache/verification-v3/diagnostics"
        if source.exists():
            shutil.copytree(source, run.dir / (side + "-diagnostics"), dirs_exist_ok=True)
            copied[side] = len(list(source.iterdir()))
    return copied


def row7_binary_paths(run: Run) -> dict:
    counts = {}
    for side in ("row07-a", "row07-b"):
        root = run.ctx.scratch(side)
        for path in sorted((root / "zig-out").rglob("*")):
            if path.is_file() and path.name in ("units", "core", "cli"):
                counts[str(path.relative_to(root))] = {"root": count_occurrences(path, str(root).encode()),
                                                       "zig_cache": count_occurrences(path, str(root / ".zig-cache").encode())}
        run.state[side + "_binaries"] = counts
    return {"counts": counts}


def row7_judge(run: Run) -> list[dict]:
    b = run.tests("tests-b")
    checks = judge_no_failures("tests-a", run.tests("tests-a"), run.status("tests-a"))
    checks += judge_no_failures("tests-b", b, run.status("tests-b"))
    checks += judge_all_hit("tests-b (second worktree reuses every eligible receipt)", b)
    checks += judge_two_worktrees(run.report("complete-a"), run.report("complete-b"))
    counts = (run.result("binary-paths").get("result") or {}).get("counts") or {}
    if counts:
        dirty = {name: value for name, value in counts.items() if value["root"] != 0}
        checks.append(check("TEST-PATHS-1: test binaries carry no absolute root path", "0 occurrences", counts, not dirty))
    else:
        checks.append(check("TEST-PATHS-1: test binaries carry no absolute root path", "0 occurrences", None, None,
                            "not judged: no installed units/core/cli binaries found under zig-out"))
    return checks


# Row 8 ----------------------------------------------------------------------

def libc_path() -> str:
    for candidate in ("/lib/x86_64-linux-gnu/libc.so.6", "/usr/lib/x86_64-linux-gnu/libc.so.6", "/usr/lib64/libc.so.6"):
        if Path(candidate).exists():
            return candidate
    return "/lib/x86_64-linux-gnu/libc.so.6"


def row8_memory_plan(ctx: Context) -> list:
    work = ctx.row_work("08-negative-controls", "memory-limit")
    entry = ctx.small_entry
    env = ctx.test_env(ctx.tree, work)
    unset = ("MYL_CORE_LEAKCHECK", "MYLANG_MEMORY_LIMIT")
    return [reset_dir(lambda c: c.row_work("08-negative-controls", "memory-limit")),
            mylang_test(ctx, "first", ctx.tree, entry, work / "cache", env=env, unset=unset),
            mylang_test(ctx, "repeat", ctx.tree, entry, work / "cache", env=env, unset=unset),
            mylang_test(ctx, "memory-limit", ctx.tree, entry, work / "cache",
                        env=dict(env, MYLANG_MEMORY_LIMIT="600M"), unset=("MYL_CORE_LEAKCHECK",))]


def row8_memory_judge(run: Run) -> list[dict]:
    return (judge_all_hit("repeat (precondition)", run.tests("repeat"))
            + judge_none_hit("MYLANG_MEMORY_LIMIT change: keys change", run.tests("memory-limit")))


def row8_ld_plan(ctx: Context) -> list:
    work = ctx.row_work("08-negative-controls", "ld-preload")
    env = ctx.test_env(ctx.tree, work, LD_PRELOAD=libc_path())
    return [reset_dir(lambda c: c.row_work("08-negative-controls", "ld-preload")),
            mylang_test(ctx, "first", ctx.tree, ctx.small_entry, work / "cache", env=env),
            mylang_test(ctx, "repeat", ctx.tree, ctx.small_entry, work / "cache", env=env)]


def row8_ld_judge(run: Run) -> list[dict]:
    repeat = run.tests("repeat")
    checks = judge_no_failures("repeat", repeat, run.status("repeat"))
    reasons = repeat.get("by_reason", {}) if repeat.get("available") else {}
    # The refusal may surface as `untracked-loader-environment` or, earlier in the
    # admission order, as `uncacheable-toolchain` (the toolchain identity sees the
    # loader variable). Either is a refusal; `no-success-receipt` would be a miss
    # that writes a receipt, so it fails the row.
    refusals = {"untracked-loader-environment", "uncacheable-toolchain", "live-effects", "configured-skip", "unsupported"}
    checks.append(check("LD_PRELOAD set: no receipts written or read", "0 cached on a repeat; every reason a refusal",
                        {"cached": repeat.get("by_status", {}).get("cached", 0), "by_reason": reasons},
                        repeat.get("available") and repeat.get("by_status", {}).get("cached", 0) == 0
                        and bool(reasons) and set(reasons) <= refusals))
    return checks


def row8_projection_plan(ctx: Context) -> list:
    work = ctx.row_work("08-negative-controls", "projection")
    probe = str(HERE / "fixtures/env_probe.my")
    env = ctx.test_env(ctx.tree, work, CODEX_THREAD_ID="lane-f-row08-probe")
    run_probe = [ctx.compiler(ctx.tree), "run", probe, "--cache-dir", str(work / "cache")]
    return [reset_dir(lambda c: c.row_work("08-negative-controls", "projection")),
            *locate_build_env(ctx, ctx.tree, work),
            Cmd("control-unprojected", run_probe, str(ctx.tree), env, slot="build"),
            Cmd("projected", ["{build_env}", "project", "--", *run_probe], str(ctx.tree), env, slot="build")]


def row8_projection_judge(run: Run) -> list[dict]:
    return [check("control: the probe sees CODEX_THREAD_ID without projection", 1, run.status("control-unprojected"),
                  run.status("control-unprojected") == 1),
            check("projected: CODEX_THREAD_ID is absent under build-env project", 0, run.status("projected"),
                  run.status("projected") == 0)]


def locate_build_env(ctx: Context, tree: Path, work: Path) -> list:
    """`build-env` is a build-graph host tool and is not installed. Use
    --build-env when given, else compile TREE's build_env.zig exactly as
    `build.zig` declares it (host target, ReleaseSafe) into the row's work dir."""
    target = work / "build-env"

    def record(run: Run) -> dict:
        chosen = Path(run.ctx.build_env) if run.ctx.build_env else target
        if not (chosen.is_file() and os.access(chosen, os.X_OK)):
            raise RuntimeError("build-env binary not found at " + str(chosen))
        run.state["build_env"] = str(chosen)
        return {"build_env": str(chosen), "sha256": sha256_file(chosen)}
    steps = []
    if not ctx.build_env:
        steps.append(Cmd("compile-build-env", [ctx.zig, "build-exe", "build_env.zig", "-OReleaseSafe",
                                               "-femit-bin=" + str(target)], str(tree), ctx.tree_env(tree), slot="build"))
    steps.append(Py("locate-build-env", "record the build-env host tool and its SHA-256", record))
    return steps


# Row 9 ----------------------------------------------------------------------

ROW9_ENTRY = "tests/lang/mut_rebind_modules.my"
ROW9_HELPER = "tests/lang/mut_rebind_helpers.my"
ROW9_BROKEN = "mut_rebind_modules::test_imported_mut_collection_rebinding_preserves_source_snapshots"
ROW9_UNAFFECTED = "mut_rebind_modules::test_imported_function_values_and_direct_calls_share_their_mut_abi"


def row9_plan(ctx: Context) -> list:
    tree = ctx.scratch("row09-tree")
    work = ctx.row_work("09-transitive-failure", "helper-edit")
    env = ctx.test_env(tree, work)
    compiler = ctx.compiler(ctx.tree)
    run = lambda name: mylang_test(ctx, name, tree, ROW9_ENTRY, work / "cache", compiler=compiler, env=env)
    return [reset_dir(lambda c: c.row_work("09-transitive-failure", "helper-edit")), add_worktree("row09-tree"),
            run("cold"), run("warm"),
            edit("row09-tree", ROW9_HELPER, "    items[8] = 8\n", "    items[8] = 9\n",
                 "break replace_dict, reached through an import by one of the two tests"),
            run("after-edit"), restore("row09-tree", ROW9_HELPER), run("after-restore"), remove_worktree("row09-tree")]


def row9_judge(run: Run) -> list[dict]:
    after = run.report("after-edit")
    statuses = {t.get("name"): t.get("status") for t in (after or {}).get("tests", [])}
    checks = judge_all_hit("warm (precondition)", run.tests("warm"))
    checks.append(check("edited helper's caller executes and fails (no stale pass)", "failed",
                        statuses.get(ROW9_BROKEN), statuses.get(ROW9_BROKEN) == "failed"))
    checks.append(check("unaffected test stays reused", "cached", statuses.get(ROW9_UNAFFECTED),
                        statuses.get(ROW9_UNAFFECTED) == "cached"))
    checks.append(check("run exits 1 on the failure", 1, run.status("after-edit"), run.status("after-edit") == 1))
    checks += judge_no_failures("after-restore", run.tests("after-restore"), run.status("after-restore"))
    return checks


# Row 10 ---------------------------------------------------------------------

def row10_plan(ctx: Context) -> list:
    work = ctx.row_work("10-mismatch-injection", "forged-record")
    store = work / "store"
    env = ctx.tree_env(ctx.tree, MYLANG_COMPILER_SHARED_CACHE=str(store))
    program = "examples/collatz.my"
    build_cmd = lambda name, out: Cmd(name, [ctx.compiler(ctx.tree), "build", program, "-o", str(work / out),
                                             "--cache-dir", str(work / "cache"), "--report"],
                                      str(ctx.tree), env, slot="build", parse="cache-report")
    return [reset_dir(lambda c: c.row_work("10-mismatch-injection", "forged-record")),
            build_cmd("publish", "first.out"),
            Py("forge", "rewrite every shared program record with different, self-consistent bytes", row10_forge),
            Py("drop-replay", "remove the private replay records so the second build reaches the link step", row10_drop_replay),
            build_cmd("republish", "second.out"),
            Py("inspect", "count mismatches.log lines, re-hash the forged records, run the integration check", row10_inspect)]


def _program_blobs(store: Path) -> list[Path]:
    return sorted(store.glob("compiler-artifacts-v*/program/*.blob"))


def row10_forge(run: Run) -> dict:
    store = run.ctx.row_work("10-mismatch-injection", "forged-record") / "store"
    blobs = _program_blobs(store)
    if not blobs:
        raise RuntimeError("no shared program record was published under " + str(store))
    forged = {}
    for blob in blobs:
        data = forge_blob(blob.read_bytes())
        blob.write_bytes(data)
        forged[blob.name] = hashlib.sha256(data).hexdigest()
    run.state["forged"] = forged
    return {"forged": forged}


def row10_drop_replay(run: Run) -> dict:
    cache = run.ctx.row_work("10-mismatch-injection", "forged-record") / "cache"
    removed = []
    for path in cache.glob("replay-v*"):
        shutil.rmtree(path, ignore_errors=True)
        removed.append(path.name)
    return {"removed": removed}


def integration_mismatch_check(store: Path) -> dict:
    """The integration-gate rule of D3, as the harness applies it: fail when any
    mismatches.log under the store has a line."""
    logs = sorted(store.rglob("mismatches.log"))
    lines = sum(len([line for line in log.read_text(errors="replace").splitlines() if line.strip()]) for log in logs)
    return {"logs": [str(log.relative_to(store)) for log in logs], "lines": lines, "passes": lines == 0}


def row10_inspect(run: Run) -> dict:
    store = run.ctx.row_work("10-mismatch-injection", "forged-record") / "store"
    current = {blob.name: sha256_file(blob) for blob in _program_blobs(store)}
    return {"blobs_after": current, "forged": run.state.get("forged"), "integration": integration_mismatch_check(store)}


def row10_judge(run: Run) -> list[dict]:
    f = run.ctx.features
    report = run.report("republish")
    inspect = run.result("inspect").get("result") or {}
    integration = inspect.get("integration") or {}
    counters = find_keys(report or {}, "mismatch")
    numeric = [value for _, value in counters if isinstance(value, int)]
    checks = [
        check("publish build succeeded", 0, run.status("publish"), run.status("publish") == 0),
        gated("build proceeds with a miss", "exit 0", {"exit": run.status("republish"),
              "stderr_tail": run.result("republish").get("stderr_tail", "")[-400:]},
              run.status("republish") == 0, "mismatch_counter", f),
        gated("mismatch counter is 1", 1, counters or None, numeric == [1] or (numeric and sum(numeric) == 1), "mismatch_counter", f),
        gated("mismatches.log has one line", 1, integration.get("lines"), integration.get("lines") == 1, "mismatch_counter", f),
        check("second bytes never published", "forged records unchanged",
              {"forged": inspect.get("forged"), "after": inspect.get("blobs_after")},
              bool(inspect.get("forged")) and inspect.get("forged") == inspect.get("blobs_after")),
        gated("integration check fails on a non-zero counter", "fails", integration,
              integration.get("passes") is False, "mismatch_counter", f),
    ]
    return checks


# Row 11 ---------------------------------------------------------------------

def row11_plan(own: bool):
    def plan(ctx: Context) -> list:
        sub = "own-compilers" if own else "same-compiler"
        work = ctx.row_work("11-path-independence", sub)
        a, b = ctx.scratch("row11-a"), ctx.scratch("row11-b")
        steps = [reset_dir(lambda c: c.row_work("11-path-independence", sub)), add_worktree("row11-a"), add_worktree("row11-b")]
        if own:
            steps += [build(ctx, a, "build-a"), build(ctx, b, "build-b")]
        for side, tree in (("a", a), ("b", b)):
            compiler = ctx.compiler(tree) if own else ctx.compiler(ctx.tree)
            env = ctx.tree_env(tree)
            for mode, flags in (("debug", ()), ("release", ("--release",))):
                steps.append(Cmd("%s-%s" % (mode, side), [compiler, "build", "examples/collatz.my", "-o",
                                                          str(work / ("%s-%s.out" % (mode, side))),
                                                          "--cache-dir", str(work / ("cache-" + side)), "--report", *flags],
                                 str(tree), env, slot="build", parse="cache-report"))
        steps += [Py("compare", "sha256 and grep -a root-path counts of both roots' programs", row11_compare(sub)),
                  remove_worktree("row11-a"), remove_worktree("row11-b")]
        return steps
    return plan


def row11_compare(sub: str):
    def action(run: Run) -> dict:
        work = run.ctx.row_work("11-path-independence", sub)
        result = {}
        for mode in ("debug", "release"):
            entry = {}
            for side in ("a", "b"):
                path = work / ("%s-%s.out" % (mode, side))
                root = run.ctx.scratch("row11-" + side)
                entry[side] = {"sha256": sha256_file(path), "own_root": count_occurrences(path, str(root).encode()),
                               "work_dir": count_occurrences(path, str(run.ctx.work).encode())}
            result[mode] = entry
        return result
    return action


def row11_judge(run: Run) -> list[dict]:
    compared = run.result("compare").get("result") or {}
    checks = []
    for mode in ("debug", "release"):
        entry = compared.get(mode) or {}
        a, b = entry.get("a") or {}, entry.get("b") or {}
        checks.append(check("%s: identical program bytes from two roots" % mode, "equal sha256",
                            [a.get("sha256"), b.get("sha256")], a.get("sha256") is not None and a.get("sha256") == b.get("sha256")))
        checks.append(check("%s: no root path in either program" % mode, "0 occurrences",
                            [a.get("own_root"), b.get("own_root")], a.get("own_root") == 0 and b.get("own_root") == 0))
        reports = [run.report("%s-%s" % (mode, side)) or {} for side in ("a", "b")]
        keys = [r.get("program_key") for r in reports]
        if all(isinstance(k, str) for k in keys):
            checks.append(check("%s: identical program_key" % mode, "equal", keys, keys[0] == keys[1]))
        else:
            checks.append(check("%s: identical program_key" % mode, "equal", keys, None,
                                "not judged: cache-report-v1 carries no program_key"))
    return checks


# Row 12 ---------------------------------------------------------------------

def row12_plan(ctx: Context) -> list:
    tree = ctx.scratch("row12-tree")
    shared = ctx.row_work("12-projection-gate", "complete")
    return [reset_dir(lambda c: c.row_work("12-projection-gate", "complete")), add_worktree("row12-tree"),
            build(ctx, tree), *locate_build_env(ctx, tree, shared),
            coordinator(ctx, "projected-complete", tree, "--force", "--shared-cache-dir", str(shared / "verification"),
                        prefix=("{build_env}", "project", "--")),
            remove_worktree("row12-tree")]


def row12_in_tree_plan(ctx: Context) -> list:
    """The same projected, forced complete gate in the target tree itself, whose
    path has an ordinary length (scratch trees under work/ nest deeper, and some
    CLI tests are sensitive to that; see REPORT.md, row 12)."""
    shared = ctx.row_work("12-projection-gate", "complete-in-tree")
    return [reset_dir(lambda c: c.row_work("12-projection-gate", "complete-in-tree")),
            *locate_build_env(ctx, ctx.tree, shared),
            coordinator(ctx, "projected-complete", ctx.tree, "--force", "--shared-cache-dir", str(shared / "verification"),
                        prefix=("{build_env}", "project", "--"))]


def failed_tests(run: Run, name: str) -> list[str]:
    """Zig test names the gate reported as failed, from the step's stderr."""
    record = run.result(name)
    try:
        text = (run.dir / record["stderr"]).read_text(errors="replace")
    except (KeyError, OSError):
        return []
    return sorted(set(re.findall(r"^error: '(.+)' failed:", text, re.MULTILINE)))


def row12_judge(run: Run) -> list[dict]:
    report = run.report("projected-complete")
    return [check("complete gate exits 0 under build-env project", 0,
                  {"exit": run.status("projected-complete"), "failed_tests": failed_tests(run, "projected-complete")},
                  run.status("projected-complete") == 0),
            check("coordinator reports success", True, (report or {}).get("success"), (report or {}).get("success") is True)]


# Row 13 ---------------------------------------------------------------------

def row13_tests_plan(ctx: Context) -> list:
    old = ctx.scratch("row13-old")
    work = ctx.row_work("13-namespace-bump", "test-receipts")
    env = ctx.test_env(ctx.tree, work)
    old_compiler, new_compiler = ctx.compiler(old), ctx.compiler(ctx.tree)

    def set_ref(run: Run) -> dict:
        run.state["row13-old_ref"] = ctx.old_ref
        return {"old_ref": ctx.old_ref}
    run = lambda name, compiler: mylang_test(ctx, name, ctx.tree, ctx.small_entry, work / "cache", compiler=compiler, env=env)
    return [reset_dir(lambda c: c.row_work("13-namespace-bump", "test-receipts")),
            Py("old-ref", "select the pre-bump commit (--old-ref)", set_ref), add_worktree("row13-old"),
            build(ctx, old, "build-old"),
            run("old-1", old_compiler), run("old-2", old_compiler),
            run("new-1", new_compiler), run("new-2", new_compiler), run("old-3", old_compiler),
            Py("namespaces", "list namespace directories in the shared cache dir", row13_namespaces),
            remove_worktree("row13-old")]


def row13_namespaces(run: Run) -> dict:
    # Receipt namespaces live under `<cache>/tests/` (`receipts-v3`,
    # `manifests-v3`); list both levels.
    cache = run.ctx.row_work("13-namespace-bump", "test-receipts") / "cache"
    entries = sorted(path.name for path in cache.iterdir()) if cache.exists() else []
    tests = cache / "tests"
    entries += sorted("tests/" + path.name for path in tests.iterdir()) if tests.exists() else []
    return {"entries": entries}


def row13_tests_judge(run: Run) -> list[dict]:
    f = run.ctx.features
    entries = (run.result("namespaces").get("result") or {}).get("entries", [])
    checks = judge_all_hit("old-2 (old compiler warm, precondition)", run.tests("old-2"))
    checks += judge_no_failures("new-1 (v2 receipts not misread)", run.tests("new-1"), run.status("new-1"))
    checks += judge_none_hit("new-1 (v2 receipts ignored)", run.tests("new-1"), feature="test_v3_namespaces", features=f)
    checks += judge_all_hit("new-2 (second v3 run hits)", run.tests("new-2"))
    checks += judge_all_hit("old-3 (v2 receipts untouched)", run.tests("old-3"))
    checks.append(gated("v3 receipt namespaces exist beside the v2 ones", "tests/receipts-v3 and tests/receipts-v2", entries,
                        "tests/receipts-v3" in entries and any(name.startswith("tests/receipts-v2") for name in entries),
                        "test_v3_namespaces", f))
    return checks


def row13_coordinator_plan(ctx: Context) -> list:
    tree = ctx.scratch("row13-tree")
    shared = ctx.row_work("13-namespace-bump", "coordinator")
    verification = ("--shared-cache-dir", str(shared / "verification"))
    return [reset_dir(lambda c: c.row_work("13-namespace-bump", "coordinator")), add_worktree("row13-tree"),
            Py("seed-v2", "copy the target tree's .mylang-cache/verification-v2 into the scratch tree", row13_seed),
            coordinator(ctx, "first-v3", tree, *verification),
            coordinator(ctx, "second-v3", tree, *verification),
            Py("v2-digest", "re-hash the seeded v2 evidence", row13_v2_digest),
            remove_worktree("row13-tree")]


def _tree_digest(root: Path) -> str | None:
    if not root.exists():
        return None
    digest = hashlib.sha256()
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        digest.update(str(path.relative_to(root)).encode() + b"\0" + (sha256_file(path) or "").encode() + b"\n")
    return digest.hexdigest()


def row13_seed(run: Run) -> dict:
    source = run.ctx.tree / ".mylang-cache/verification-v2"
    target = run.ctx.scratch("row13-tree") / ".mylang-cache/verification-v2"
    if source.exists():
        shutil.copytree(source, target, dirs_exist_ok=True)
    run.state["v2_seed"] = _tree_digest(target)
    return {"seeded": source.exists(), "digest": run.state["v2_seed"]}


def row13_v2_digest(run: Run) -> dict:
    target = run.ctx.scratch("row13-tree") / ".mylang-cache"
    return {"v2": _tree_digest(target / "verification-v2"), "seed": run.state.get("v2_seed"),
            "namespaces": sorted(p.name for p in target.glob("verification-v*"))}


def row13_coordinator_judge(run: Run) -> list[dict]:
    f = run.ctx.features
    first, second = run.report("first-v3"), run.report("second-v3")
    digest = run.result("v2-digest").get("result") or {}
    reused_first = sorted(name for name, row in action_rows(first).items() if row.get("state") == "reused")
    checks = [
        gated("first v3 gate is a full run", "0 reused", reused_first, first is not None and not reused_first, "coordinator_v3", f),
        gated("v2 evidence ignored and untouched", "seed digest unchanged", digest,
              digest.get("v2") == digest.get("seed"), "coordinator_v3", f),
        gated("verification-v3 namespace written", "verification-v3", digest.get("namespaces"),
              "verification-v3" in (digest.get("namespaces") or []), "coordinator_v3", f),
    ]
    checks += judge_coordinator_warm("second v3 gate", second, first)
    return checks


# The matrix -------------------------------------------------------------------

ROWS = [
    Row(1, "unchanged-repeat", "Unchanged repeat in one worktree",
        "All receipts hit; `language` members in fact and leak modes execute zero tests (today 1,790)",
        [Subcase("lang-debug", False, *row1_tests("debug")),
         Subcase("lang-facts-leak", False, *row1_tests("facts-leak")),
         Subcase("complete", True, row1_complete_plan, row1_complete_judge)]),
    Row(2, "parser-comment", "Comment-only edit to `src/parser.zig`, then `mylang test tests/lang`",
        "IR keys miss; all program bytes unchanged; 100 % `exec-receipt-hit`; zero `zig cc`; zero trials. "
        "Record the time (expected: lowering and emission only)",
        [Subcase("edit", True, edit_row_plan("02-parser-comment"), row2_judge)]),
    Row(3, "emitter-helper", "Emitter edit that changes one helper's code",
        "Only tests whose program bytes changed execute; verdicts equal a `--force` run",
        [Subcase("edit", True, edit_row_plan("03-emitter-helper", force_compare=True), row3_judge)]),
    Row(4, "runner-edit", "Edit to `src/core/test_runner_execute.zig` behaviour",
        "Every execution receipt misses (`runner_identity`); IR receipts also miss",
        [Subcase("edit", True, edit_row_plan("04-runner-edit"), row4_judge)]),
    Row(5, "runtime-edit", "Edit to `src/core/runtime/core_rt.c`",
        "Every execution receipt misses (runtime object digest is in `program_key`)",
        [Subcase("edit", True, edit_row_plan("05-runtime-edit"), row5_judge)]),
    Row(6, "fact-leak-modes", "Fact and leak modes",
        "A second identical `--release --verify-facts` run hits; a leak-check run hits its own receipt; "
        "neither hits the other's; `--force` reruns",
        [Subcase("modes", False, row6_plan, row6_judge)]),
    Row(7, "two-worktrees", "Two worktrees at one commit, different paths, different launcher environments "
        "(`CODEX_THREAD_ID`, `TERM`, `PWD`, `TMPDIR`)",
        "The second worktree's `mylang test` reuses every eligible receipt and its complete verification reuses "
        "every group except the host-fresh collectors; all 46 action keys identical",
        [Subcase("two-worktrees", True, row7_plan, row7_judge)]),
    Row(8, "negative-controls", "Negative controls",
        "`MYLANG_MEMORY_LIMIT` change: keys change. `LD_PRELOAD` set: no receipts. A fixture test reading "
        "`CODEX_THREAD_ID` sees it absent under projection",
        [Subcase("memory-limit", False, row8_memory_plan, row8_memory_judge),
         Subcase("ld-preload", False, row8_ld_plan, row8_ld_judge),
         Subcase("projection", False, row8_projection_plan, row8_projection_judge, needs=("build_env",))]),
    Row(9, "transitive-failure", "Transitive failure injection",
        "An edit in a function a cached-pass test reaches makes it execute and fail; no stale pass",
        [Subcase("helper-edit", False, row9_plan, row9_judge)]),
    Row(10, "mismatch-injection", "Mismatch injection",
        "Different bytes published under one shared key: the build proceeds with a miss, the counter is 1, "
        "the log has one line, the integration check fails",
        [Subcase("forged-record", False, row10_plan, row10_judge)]),
    Row(11, "path-independence", "Program path independence",
        "The same test program built from two roots yields identical `program_key`s and identical bytes",
        [Subcase("same-compiler", False, row11_plan(False), row11_judge),
         Subcase("own-compilers", True, row11_plan(True), row11_judge)]),
    Row(12, "projection-gate", "Projection safety of the whole gate",
        "The complete gate passes under `build-env project` before projection becomes the default",
        [Subcase("complete", True, row12_plan, row12_judge, needs=("build_env",)),
         Subcase("complete-in-tree", True, row12_in_tree_plan, row12_judge, needs=("build_env",))]),
    Row(13, "namespace-bump", "Namespace bump",
        "Old v2 receipts are ignored, not misread; the first v3 gate is a full run and the second is a hit",
        [Subcase("test-receipts", True, row13_tests_plan, row13_tests_judge),
         Subcase("coordinator", True, row13_coordinator_plan, row13_coordinator_judge)]),
]


def select(spec: str | None) -> list[tuple[Row, list[Subcase]]]:
    """`--rows 1,7` or `--rows 1:lang-debug,8:ld-preload`; default every row."""
    if not spec:
        return [(row, list(row.subcases)) for row in ROWS]
    wanted: dict[int, set[str] | None] = {}
    for item in spec.split(","):
        item = item.strip()
        if not item:
            continue
        number, _, sub = item.partition(":")
        key = int(number.split("-")[0])
        if key not in {row.number for row in ROWS}:
            raise SystemExit("unknown row: " + item)
        if sub:
            existing = wanted.get(key, set())
            if existing is not None:
                existing.add(sub)
                wanted[key] = existing
        else:
            wanted[key] = None
    selected = []
    for row in ROWS:
        if row.number in wanted:
            names = wanted[row.number]
            subs = [s for s in row.subcases if names is None or s.name in names]
            if names is not None and len(subs) != len(names):
                raise SystemExit("unknown sub-case in %s; known: %s" % (spec, [s.name for s in row.subcases]))
            selected.append((row, subs))
    return selected


def manifest(ctx: Context) -> dict:
    """The frozen manifest of one invocation: compiler, tree, options, environment."""
    status = git(ctx.tree, "status", "--porcelain=v1") or ""
    return {"schema": SCHEMA, "plan": PLAN, "tree": str(ctx.tree), "tree_head": ctx.head,
            "tree_dirty_sha256": hashlib.sha256(status.encode()).hexdigest() if status else None,
            "compiler": str(ctx.tree / "zig-out/bin/mylang"), "compiler_sha256": sha256_file(ctx.tree / "zig-out/bin/mylang"),
            "zig": ctx.zig, "harness_sha256": sha256_file(Path(__file__)), "options": ctx.args,
            "features": ctx.features, "environment": environment_projection(dict(os.environ)),
            "slot_dir": os.environ.get("MYLANG_SLOT_DIR")}


def dry_run(ctx: Context, selected) -> int:
    print("# output-keyed acceptance matrix: dry run against %s (HEAD %s)" % (ctx.tree, ctx.head))
    print("# features: " + ", ".join("%s=%s" % item for item in sorted(ctx.features.items())))
    print("# $TREE=%s\n# $WORK=%s\n# $ZIG=%s" % (ctx.tree, ctx.work, ctx.zig))
    for row, subs in selected:
        print("\n## Row %d (%s): %s" % (row.number, row.id, row.case))
        print("expected: " + row.expected)
        for sub in subs:
            missing = [need for need in sub.needs if not ctx.features.get(need)]
            print("\n### %s%s%s" % (sub.name, " [heavy]" if sub.heavy else "",
                                     " [needs: %s; not judged on this tree]" % ", ".join(missing) if missing else ""))
            for index, step in enumerate(sub.plan(ctx)):
                if isinstance(step, Py):
                    print("  %2d. [python] %s%s" % (index, step.description, " (always)" if step.always else ""))
                else:
                    text = step.render(str(ctx.tree)).replace(str(ctx.work), "$WORK").replace(str(ctx.tree), "$TREE")
                    print("  %2d. %s" % (index, text))
    return 0


def execute(ctx: Context, selected, allow_heavy: bool) -> int:
    missing_env = [name for name in ("ZIG", "MYLANG_SLOT_DIR") if not os.environ.get(name)]
    if missing_env:
        print("matrix: source ~/.config/mylang/dev-env.sh first (missing %s)" % ", ".join(missing_env), file=sys.stderr)
        return 2
    ctx.evidence.mkdir(parents=True, exist_ok=True)
    frozen = manifest(ctx)
    summary_path = ctx.evidence / "summary.json"
    try:
        summary = json.loads(summary_path.read_text())
    except (OSError, json.JSONDecodeError):
        summary = {"schema": SCHEMA, "rows": {}}
    summary.setdefault("rows", {})
    for row, subs in selected:
        row_dir = ctx.evidence / row.id
        row_dir.mkdir(parents=True, exist_ok=True)
        # Sub-cases run in an earlier invocation keep their records; a rerun of
        # one sub-case replaces only that sub-case (each names its own manifest).
        try:
            previous = json.loads((row_dir / "row.json").read_text()).get("subcases", {})
        except (OSError, json.JSONDecodeError):
            previous = {}
        row_record = {"row": row.number, "id": row.id, "case": row.case, "expected": row.expected,
                      "manifest": frozen, "started": now(), "subcases": dict(previous)}
        for sub in subs:
            missing = [need for need in sub.needs if not ctx.features.get(need)]
            if missing:
                row_record["subcases"][sub.name] = {"decision": NOT_JUDGED, "reason": "target tree lacks: " + ", ".join(missing)}
                continue
            if sub.heavy and not allow_heavy:
                row_record["subcases"][sub.name] = {"decision": "skipped", "reason": "heavy sub-case; pass --heavy"}
                continue
            run = Run(ctx, row, sub)
            started = now()
            print("matrix: row %s sub-case %s: running" % (row.id, sub.name), flush=True)
            failure = run.execute(sub.plan(ctx))
            if failure is not None:
                checks = [check("harness step " + failure, "completes", run.results[failure].get("error"), False)]
                decision = "error"
            else:
                checks = sub.judge(run)
                decision = decide(checks)
            record = {"decision": decision, "started": started, "finished": now(), "checks": checks, "manifest": frozen,
                      "compilers_sha256": run.compilers, "steps": run.results}
            for result in record["steps"].values():
                result.pop("parsed", None)
            (run.dir / "result.json").write_text(json.dumps(record, indent=1, sort_keys=True, default=str))
            row_record["subcases"][sub.name] = {"decision": decision, "harness_sha256": frozen["harness_sha256"],
                                                "tree_head": ctx.head, "finished": now(),
                                                "evidence": str((run.dir / "result.json").relative_to(ctx.evidence)),
                                                "checks": [{k: c[k] for k in ("check", "result")} for c in checks]}
            print("matrix: row %s sub-case %s: %s" % (row.id, sub.name, decision), flush=True)
            for item in checks:
                print("  [%s] %s; observed %s" % (item["result"], item["check"], json.dumps(item["observed"], default=str)[:300]))
        row_record["finished"] = now()
        row_record["decision"] = aggregate([s["decision"] for s in row_record["subcases"].values()])
        (row_dir / "row.json").write_text(json.dumps(row_record, indent=1, sort_keys=True, default=str))
        summary["rows"][row.id] = {"decision": row_record["decision"], "finished": row_record["finished"],
                                   "tree_head": ctx.head,
                                   "subcases": {name: value["decision"] for name, value in row_record["subcases"].items()}}
    summary["last_manifest"] = frozen
    summary_path.write_text(json.dumps(summary, indent=1, sort_keys=True, default=str))
    return 0 if all(value["decision"] in (PASS, "skipped") for value in summary["rows"].values()) else 1


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--tree", required=True, help="target worktree (its HEAD seeds scratch worktrees)")
    parser.add_argument("--rows", help="comma list of rows, optionally ROW:SUBCASE (default: all)")
    parser.add_argument("--dry-run", action="store_true", help="print the planned commands; run nothing")
    parser.add_argument("--heavy", action="store_true", help="also run sub-cases marked heavy (complete gates, scratch builds)")
    parser.add_argument("--lang-entry", help="replace tests/lang in rows 1-6 (cheap smoke runs only)")
    parser.add_argument("--small-entry", default="tests/lang/frontend_numbers.my", help="entry for the negative controls and row 13")
    parser.add_argument("--old-ref", default="f6971a623", help="pre-bump commit for row 13 (default: Lane A integration)")
    parser.add_argument("--build-env", help="path of the build-env host tool (default: search zig-out)")
    parser.add_argument("--work", help="scratch directory (default: work/ beside this file)")
    parser.add_argument("--evidence", help="evidence directory (default: evidence/ beside this file)")
    parser.add_argument("--keep-work", action="store_true", help="keep scratch worktrees for inspection")
    parser.add_argument("--manifest-only", metavar="LABEL",
                        help="write the frozen manifest to evidence/manifests/LABEL.json and run nothing (cohorts.md)")
    args = parser.parse_args(argv)
    ctx = Context(args)
    if args.manifest_only:
        target = ctx.evidence / "manifests" / (args.manifest_only + ".json")
        target.parent.mkdir(parents=True, exist_ok=True)
        frozen = dict(manifest(ctx), label=args.manifest_only, written=now())
        target.write_text(json.dumps(frozen, indent=1, sort_keys=True, default=str) + "\n")
        print(target)
        return 0
    selected = select(args.rows)
    if args.dry_run:
        return dry_run(ctx, selected)
    return execute(ctx, selected, args.heavy)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

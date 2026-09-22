#!/usr/bin/env python3
"""Compiler-invocation events: the unit of measurement for the feedback study.

One event is one compiler process. It is written by the wrapper that runs the
compiler, before either rendering, so every arm is measured identically and
assistant prose, echoed transcripts and repeated reads of a result contribute
nothing. The plan fixed the schema (`compiler-invocation-v1`) and the metric
names defined here; the aggregation keeps them separate on purpose:

    failed compiler invocations      completed processes rejected for source or
                                     invocation errors (infrastructure separate)
    failed checks on changed source  those whose source hash differs from the
                                     attempt's initial snapshot
    failed candidate versions        distinct changed source hashes with a failure;
                                     repeated checks on unchanged code count once
    repeated diagnostic              the same semantic diagnostic on distinct
                                     failed invocations
    first compiler green             first successful check on a snapshot —
                                     compilation is not task completion
    first public acceptance          first snapshot passing the public checks
    hidden acceptance                the coordinator's grading of the sealed
                                     snapshot, recorded by the runner, not here

A semantic diagnostic identity is `(code, message, snippet)`, not the bare code:
`E_TYPE` covers both a bool returned as an int and an unhandled `Result`, and an
edit that shifts line numbers must not look like a new error.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re

SCHEMA = "compiler-invocation-v1"
REQUIRED = ("schema", "cohort_id", "attempt_id", "invocation_id", "command", "argv", "cwd",
            "source_sha256", "compiler_sha256", "started_monotonic_ns", "finished_monotonic_ns",
            "exit_code", "outcome", "diagnostic_codes", "source_stable")
OUTCOMES = ("success", "source_error", "invocation_misuse", "runtime_failure",
            "public_failure", "infrastructure_failure", "limit_reached")
INFRASTRUCTURE_CODES = ("E_MODULE_READ",)  # only with a host-failure marker; see classify()
HOST_FAILURE = re.compile(r"host failure|NativeToolFailed|ReadOnlyFileSystem|sub-compilation of .* failed")
INVOCATION_CODES = ("E_MODULE_NAME", "E_MAIN")
HEADER = re.compile(r"^(?P<path>.+?):(?P<line>\d+):(?P<column>\d+): error\[(?P<code>[A-Z_]+)\]: (?P<message>.*)$")
NOTE = re.compile(r"^\s*note:\s*(?P<text>.*)$")
EXCLUDED = (".cache", ".mylang-cache", "_verify", "public/.cache")


def inventory(root: Path) -> tuple[str, dict[str, str]]:
    """Hash every candidate source file by relative path, additions included.

    Caches and coordinator-owned reports stay outside the inventory: a compiler
    cache changing between two checks must not look like an edit by the agent.
    """
    entries: dict[str, str] = {}
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(root).as_posix()
        if any(part in relative for part in EXCLUDED) or relative.startswith("public/"):
            continue
        entries[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    digest = hashlib.sha256(json.dumps(entries, sort_keys=True).encode()).hexdigest()
    return digest, entries


def parse_diagnostics(stderr: str) -> list[dict]:
    """The canonical diagnostic records, independent of how they are rendered."""
    diagnostics: list[dict] = []
    for line in stderr.splitlines():
        match = HEADER.match(line)
        if match:
            diagnostics.append({**match.groupdict(), "snippet": "", "notes": []})
            continue
        if not diagnostics:
            continue
        note = NOTE.match(line)
        if note:
            diagnostics[-1]["notes"].append(note.group("text"))
        elif line.strip() and not diagnostics[-1]["snippet"] and set(line.strip()) != {"^"}:
            diagnostics[-1]["snippet"] = line.strip()
    return diagnostics


def identity(diagnostic: dict) -> str:
    """A stable identity for a diagnostic: the code alone is too coarse."""
    parts = (diagnostic.get("code", ""), diagnostic.get("message", ""),
             (diagnostic.get("snippet") or "").strip())
    return hashlib.sha256("\x1f".join(parts).encode()).hexdigest()[:16]


def classify(exit_code: int, stderr: str, diagnostics: list[dict], command: str) -> str:
    """What happened, from the process rather than from the word `error`."""
    if HOST_FAILURE.search(stderr):
        return "infrastructure_failure"
    if diagnostics:
        codes = {diagnostic["code"] for diagnostic in diagnostics}
        if codes & set(INVOCATION_CODES):
            return "invocation_misuse"
        return "source_error"
    if exit_code == 0:
        return "success"
    return "runtime_failure"


def read_events(path: Path) -> tuple[list[dict], dict]:
    """Validated events, deduplicated by invocation id, plus coverage flags.

    A truncated final line is a missing event, not a zero-diagnostic one, and a
    repeated delivery of the same invocation is counted once.
    """
    events: list[dict] = []
    seen: set[str] = set()
    problems: list[str] = []
    duplicates = 0
    truncated = 0
    if not path.is_file():
        return [], {"missing": True, "duplicates": 0, "truncated": 0, "invalid": 0}
    text = path.read_text(errors="replace")
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            truncated += 1
            problems.append(f"line {index + 1}: unparseable")
            continue
        missing = [field for field in REQUIRED if field not in event]
        if missing:
            problems.append(f"line {index + 1}: missing {', '.join(missing)}")
            continue
        if event["schema"] != SCHEMA:
            problems.append(f"line {index + 1}: schema {event['schema']!r}")
            continue
        if event["invocation_id"] in seen:
            duplicates += 1
            continue
        seen.add(event["invocation_id"])
        events.append(event)
    return events, {"missing": False, "duplicates": duplicates, "truncated": truncated,
                    "invalid": len(problems), "problems": problems[:5]}


def aggregate(events: list[dict], initial_source_sha256: str) -> dict:
    """The M0 metrics, each named separately and never merged into one count."""
    failed_invocations = 0
    infrastructure = 0
    failed_on_changed = 0
    failed_versions: set[str] = set()
    checked_versions: set[str] = set()
    repeated = 0
    seen_identities: dict[str, int] = {}
    first_green_ns = None
    diagnostic_codes: dict[str, int] = {}
    for event in sorted(events, key=lambda item: item.get("started_monotonic_ns") or 0):
        codes = event.get("diagnostic_codes") or []
        for code in codes:
            diagnostic_codes[code] = diagnostic_codes.get(code, 0) + 1
        outcome = event.get("outcome")
        if outcome == "infrastructure_failure":
            infrastructure += 1
            continue
        if outcome in ("source_error", "invocation_misuse", "runtime_failure", "public_failure"):
            failed_invocations += 1
            changed = event.get("source_sha256") != initial_source_sha256
            if changed and not event.get("source_stable", True):
                continue  # the source moved under the compiler: invalid measurement
            if changed:
                failed_on_changed += 1
                failed_versions.add(event["source_sha256"])
            for identity_value in event.get("diagnostic_identities") or []:
                seen_identities[identity_value] = seen_identities.get(identity_value, 0) + 1
        elif outcome == "success":
            checked_versions.add(event.get("source_sha256", ""))
            if first_green_ns is None:
                first_green_ns = event.get("finished_monotonic_ns")
    repeated = sum(count - 1 for count in seen_identities.values() if count > 1)
    return {
        "invocations": len(events),
        "failed_compiler_invocations": failed_invocations,
        "infrastructure_failures": infrastructure,
        "failed_checks_on_changed_source": failed_on_changed,
        "failed_candidate_versions": len(failed_versions),
        "checked_candidate_versions": len(checked_versions),
        "repeated_diagnostics": repeated,
        "distinct_diagnostics": len(seen_identities),
        "diagnostic_codes": diagnostic_codes,
        "first_compiler_green_ns": first_green_ns,
    }

#!/usr/bin/env python3
"""Run a language suite and reject undocumented unsupported guest verdicts.

This is a test-only policy around the installed compiler's native-tests-v1
report. Every selected guest still goes through the real compiler/test runner;
the allowlist neither skips a test nor changes its recorded status.
"""
from __future__ import annotations

import argparse
from collections import Counter
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import ownership_corpus as corpus  # noqa: E402  (stamps the certificate directories a run writes)
try:
    import verification_telemetry  # noqa: E402  (records how the suite ran, for a rerun of one failing test)
except ImportError:  # a copy of this driver without its neighbours (the corpus tests' fixtures): it records nothing
    verification_telemetry = None

SUITES = ("tests/lang", "tests/value_semantics", "tests/ported")
STATUSES = ("passed", "cached", "failed", "skipped", "unsupported")


class GuardError(ValueError):
    """The allowlist or actual runner report cannot justify a passing gate."""


def unique_object(pairs):
    """Decode JSON without allowing a repeated key to replace evidence."""
    result = {}
    for key, value in pairs:
        if key in result:
            raise GuardError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def qualified_name(name):
    return (isinstance(name, str) and "::" in name and
            all(part for part in name.split("::")) and
            not any(char.isspace() or char in "*?[" for char in name))


def allowlist_entries(value):
    """Validate exact suite/name/reason entries; wildcard exceptions are refused."""
    if not isinstance(value, dict) or set(value) != {"version", "tests"}:
        raise GuardError("unsupported allowlist must contain version and tests")
    if type(value["version"]) is not int or value["version"] != 1 or not isinstance(value["tests"], list):
        raise GuardError("unsupported allowlist must use version 1 and a tests array")
    entries = {}
    for entry in value["tests"]:
        if not isinstance(entry, dict) or set(entry) != {"suite", "name", "reason"}:
            raise GuardError("each unsupported entry needs suite, name and reason")
        suite, name, reason = entry["suite"], entry["name"], entry["reason"]
        if suite not in SUITES or not qualified_name(name):
            raise GuardError("unsupported entries need an exact language suite and qualified test name")
        if not isinstance(reason, str) or not reason.strip():
            raise GuardError(f"unsupported entry {suite}/{name} needs a nonempty reason")
        key = suite, name
        if key in entries:
            raise GuardError(f"duplicate unsupported entry: {suite}/{name}")
        entries[key] = reason
    return entries


def load_allowlist(path):
    return allowlist_entries(json.loads(path.read_text(), object_pairs_hook=unique_object))


def report_verdicts(text):
    """Validate the complete native report and reconcile every summary count."""
    value = json.loads(text, object_pairs_hook=unique_object)
    if not isinstance(value, dict) or value.get("version") != "native-tests-v1" or not isinstance(value.get("tests"), list):
        raise GuardError("compiler produced no native-tests-v1 report")
    names, counts = set(), Counter()
    for verdict in value["tests"]:
        if not isinstance(verdict, dict) or not qualified_name(verdict.get("name")):
            raise GuardError("invalid guest test name in native report")
        name, status = verdict["name"], verdict.get("status")
        if name in names or status not in STATUSES:
            raise GuardError(f"duplicate test or invalid verdict: {name}")
        if not isinstance(verdict.get("reason"), str) or (status == "unsupported" and not verdict["reason"].strip()):
            raise GuardError(f"invalid or absent verdict reason: {name}")
        names.add(name)
        counts[status] += 1
    for status in STATUSES:
        if type(value.get(status)) is not int or value[status] != counts[status]:
            raise GuardError(f"native report {status} count does not match its verdicts")
    return value["tests"]


def unsupported_errors(suite, verdicts, entries):
    """Only matching observed unsupported reasons may use an allowlist entry."""
    errors = []
    for verdict in verdicts:
        if verdict["status"] != "unsupported":
            continue
        name, reason = verdict["name"], verdict["reason"]
        expected = entries.get((suite, name))
        if expected is None:
            errors.append(f"unexpected unsupported test {suite}/{name}: {reason}")
        elif reason != expected:
            errors.append(f"unsupported reason changed for {suite}/{name}: expected {expected!r}, got {reason!r}")
    return errors


def certificate_directory(arguments):
    """The directory `--emit-certificates DIR` names, or None."""
    if "--emit-certificates" in arguments:
        index = arguments.index("--emit-certificates")
        if index + 1 < len(arguments):
            return Path(arguments[index + 1])
    return None


def main(argv=None, run=subprocess.run):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--allowlist", type=Path, default=ROOT / "tests/unsupported.json")
    parser.add_argument("suite", choices=SUITES)
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    try:
        entries = load_allowlist(args.allowlist)
    except (OSError, ValueError, TypeError) as error:
        print(f"test-lang guard: {error}", file=sys.stderr)
        return 2
    arguments = args.arguments[1:] if args.arguments[:1] == ["--"] else args.arguments
    # A run that writes certificates owns its directory's stamp (scripts/ownership_corpus.py): a directory not stamped for this
    # compiler and these suite inputs is emptied and every program is rebuilt (--force), so a receipt cannot stand in for the
    # build; the stamp is written only when the run succeeds.
    certificates = certificate_directory(arguments)
    key = None
    if certificates is not None:
        try:
            key = corpus.current_key(args.compiler, ROOT, args.suite, run)
            if corpus.begin(certificates, key) and "--force" not in arguments:
                arguments = [*arguments, "--force"]
        except (corpus.CorpusError, OSError) as error:
            print(f"test-lang guard: {error}", file=sys.stderr)
            return 2
    status = run_suite(args, arguments, entries, run)
    if status == 0 and certificates is not None:
        corpus.commit(certificates, key)
    return status


def run_suite(args, arguments, entries, run):
    # How this suite ran, so the coordinator can rerun one failing guest test alone the same way (item 4d).
    if verification_telemetry is not None:
        verification_telemetry.record_rerun(os.environ.get("SELKA_VERIFICATION_TELEMETRY_DIR"), "language",
                                            SUITES.index(args.suite), "guest", argv=[],
                                            extra={"compiler": str(Path(args.compiler).resolve()), "suite": args.suite,
                                                   "arguments": list(arguments)})
    command = [args.compiler, "test", args.suite, *arguments]
    if "--json" not in arguments:
        command.append("--json")
    try:
        completed = run(command, capture_output=True, text=True)
    except OSError as error:
        print(f"test-lang guard: cannot run compiler: {error}", file=sys.stderr)
        return 2
    # Keep the actual JSON, including every unsupported status/reason and all
    # cache/work details, available to readers and verification telemetry.
    sys.stdout.write(completed.stdout)
    sys.stderr.write(completed.stderr)
    try:
        verdicts = report_verdicts(completed.stdout)
        errors = unsupported_errors(args.suite, verdicts, entries)
    except (ValueError, TypeError) as error:
        verdicts, errors = [], [str(error)]
    for error in errors:
        print(f"test-lang guard: {error}", file=sys.stderr)
    if completed.returncode:
        return completed.returncode if completed.returncode > 0 else 128 - completed.returncode
    if errors or any(verdict["status"] == "failed" for verdict in verdicts):
        return 1
    return 0 if any(verdict["status"] != "skipped" for verdict in verdicts) else 3


if __name__ == "__main__":
    sys.exit(main())

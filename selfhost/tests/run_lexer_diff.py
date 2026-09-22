#!/usr/bin/env python3
"""Differential lexer check: stage-0 `dump-tokens` versus `selfhost/lexer.my`.

Run from the repository root:

    python3 selfhost/tests/run_lexer_diff.py

Each fixture is classified in `selfhost/tests/fixtures/lexer/expect.json`:

* ``ok``    -- the stage-0 lexer succeeds; compare the `tokens-v1` document
  converted to the ``<kind> <start> <end>`` protocol against the self-host
  lexer's stdout byte for byte.
* ``error`` -- the stage-0 lexer fails; compare the self-host ``error ...``
  line against the first `diagnostic-v1` record `mylang check` reports, and
  require that record to be a lexical code.
* ``skip``  -- not compared, with the reason recorded in the manifest. Skips
  are for cases a stage-0 lexical comparison cannot decide (a later-phase
  error, or a limit a small fixture cannot reach).

The selfhost lexer is built natively once per run with the pinned stage 0
(``build ... --project``; a module entry is a project entry), and every fixture
uses that binary.  ``--via-run`` keeps the slower ``mylang run selfhost/lexer.my``
path for a comparison baseline.  ``--fixture SUBSTRING`` (repeatable) restricts
the run to fixtures whose name contains a substring, and ``--jobs N`` (default
1, capped at ``min(8, cpu count)``) runs independent fixtures in parallel while
preserving the fixture order in the report.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import stage0  # noqa: E402 - sibling pin authority, imported after sys.path setup
FIXTURES = ROOT / "selfhost" / "tests" / "fixtures" / "lexer"
MANIFEST = FIXTURES / "expect.json"
PROGRAM = "selfhost/lexer.my"

LEXICAL_CODES = frozenset({
    "E_TOKEN",
    "E_INDENTATION",
    "E_BYTE_LITERAL",
    "E_BYTE_ESCAPE",
    "E_BYTE_LITERAL_LIMIT",
    "E_NESTING_LIMIT",
    "E_REMOVED_SPELLING",
})


def run(args):
    return subprocess.run(
        [str(stage0.require()), *args],
        cwd=str(ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def oracle_protocol(path: Path):
    """Return the stage-0 token protocol lines, or (None, proc) when it fails."""
    result = run(["dump-tokens", str(path)])
    if result.returncode != 0:
        return None, result
    document = json.loads(result.stdout)
    return [
        "{} {} {}".format(token["kind"], token["start"], token["end"])
        for token in document["tokens"]
    ], result


def selfhost_protocol(path: Path, built, via_run: bool):
    if via_run:
        result = run(["run", PROGRAM, "--", str(path)])
    else:
        result = subprocess.run(
            [str(built), str(path)],
            cwd=str(ROOT),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    if result.returncode != 0:
        return None, result
    return result.stdout.splitlines(), result


def check_error_line(path: Path):
    """Return the first `diagnostic-v1` record as an `error ...` protocol line."""
    result = run(["check", str(path), "--diagnostics=json"])
    record = None
    for line in result.stderr.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            candidate = json.loads(line)
        except json.JSONDecodeError:
            continue
        if candidate.get("kind") == "diagnostic":
            record = candidate
            break
    if record is None:
        return None, None, result
    diagnostic = record["diagnostic"]
    location = diagnostic["location"]
    span = location.get("bytes")
    if span is None:
        return diagnostic.get("code"), None, result
    line = "error {} {} {} {} {}".format(
        diagnostic["code"],
        location["start"]["line"],
        location["start"]["column"],
        span["start"],
        span["end"],
    )
    return diagnostic.get("code"), line, result


def first_difference(expected, actual):
    for index in range(max(len(expected), len(actual))):
        want = expected[index] if index < len(expected) else "<missing>"
        got = actual[index] if index < len(actual) else "<missing>"
        if want != got:
            return index + 1, want, got
    return None


def build_program(output: Path, program: str = PROGRAM) -> int:
    """Build ``program`` once into ``output``; 0 on success, 2 with a message.

    The selfhost programs open with a module header, so the build needs
    ``--project``: a module entry is a project entry. ``--backend qbe`` is
    explicit: a component iteration must not depend on the host's default
    backend or its LLVM toolchain.
    """
    command = [str(stage0.require()), "build", program, "--project", "--backend", "qbe", "-o", str(output)]
    result = subprocess.run(
        command,
        cwd=str(ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or "no output"
        print("lexer diff: cannot build {} (exit {}): {}".format(program, result.returncode, detail))
        return 2
    return 0


def matches_filter(name: str, filters) -> bool:
    """True when ``name`` matches at least one ``--fixture`` substring."""
    if not filters:
        return True
    return any(fragment in name for fragment in filters)


def compare_fixture(name, path, entry, built, via_run):
    """Compare one fixture; return ``(failures, mismatches, compared, skipped)``."""
    status = entry.get("status")
    if status == "skip":
        return [], 0, 0, 1
    if status == "ok":
        expected, oracle = oracle_protocol(path)
        if expected is None:
            return ["{}: oracle failed ({})".format(name, oracle.stderr.strip())], 1, 0, 0
        actual, host = selfhost_protocol(path, built, via_run)
        if actual is None:
            return ["{}: self-host lexer failed ({}): {}".format(name, host.returncode, host.stderr.strip())], 1, 0, 0
        compared = len(expected)
        difference = first_difference(expected, actual)
        if difference is not None:
            number, want, got = difference
            return ["{}: line {}\n  expected {}\n  actual   {}".format(name, number, want, got)], 1, compared, 0
        return [], 0, compared, 0
    if status == "error":
        code, expected, check = check_error_line(path)
        if expected is None:
            return ["{}: check produced no usable diagnostic (exit {}): {}".format(name, check.returncode, check.stderr.strip())], 1, 0, 0
        if code not in LEXICAL_CODES:
            return ["{}: stage 0 reports later-phase {} instead of a lexical error; mark the fixture skip with a reason".format(name, code)], 1, 0, 0
        actual, host = selfhost_protocol(path, built, via_run)
        if actual is None:
            return ["{}: self-host lexer failed ({}): {}".format(name, host.returncode, host.stderr.strip())], 1, 0, 0
        compared = 1
        difference = first_difference([expected], actual)
        if difference is not None:
            number, want, got = difference
            return ["{}: line {}\n  expected {}\n  actual   {}".format(name, number, want, got)], 1, compared, 0
        return [], 0, compared, 0
    return ["{}: unknown manifest status {!r}".format(name, status)], 1, 0, 0


def collect(selected, manifest, built, via_run, jobs):
    """Run every selected fixture, returning results in the original order."""
    if jobs < 2 or len(selected) < 2:
        return [compare_fixture(name, FIXTURES / name, manifest[name], built, via_run) for name in selected]
    results = [None] * len(selected)
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        pending = {
            pool.submit(compare_fixture, name, FIXTURES / name, manifest[name], built, via_run): index
            for index, name in enumerate(selected)
        }
        for future in concurrent.futures.as_completed(pending):
            results[pending[future]] = future.result()
    return results


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", action="append", metavar="SUBSTRING",
                        help="only compare fixtures whose name contains SUBSTRING (repeatable; default all)")
    parser.add_argument("--jobs", type=int, default=1, metavar="N",
                        help="fixture workers (default 1; capped at min(8, cpu count))")
    parser.add_argument("--via-run", action="store_true",
                        help="run the selfhost program with `mylang run` instead of the built binary")
    return parser.parse_args(argv)


def main() -> int:
    args = parse_args(sys.argv[1:])
    try:
        stage0.require()
    except stage0.PinError as error:
        print("lexer diff: {}".format(error))
        return 2
    manifest = json.loads(MANIFEST.read_text())
    names = sorted(p.name for p in FIXTURES.glob("*.my"))
    unknown = sorted(set(names) - set(manifest))
    if unknown:
        print("lexer diff: fixtures missing from expect.json: {}".format(", ".join(unknown)))
        return 2
    selected = [name for name in names if matches_filter(name, args.fixture)]
    jobs = max(1, min(args.jobs, min(8, os.cpu_count() or 1)))
    with tempfile.TemporaryDirectory(prefix="mylang-lexer-diff-") as tmp:
        built = None
        if not args.via_run:
            built = Path(tmp) / "lexer"
            code = build_program(built)
            if code != 0:
                return 2
        results = collect(selected, manifest, built, args.via_run, jobs)
    failures = []
    mismatches = 0
    compared = 0
    skipped = 0
    for problems, bad, count, skipped_here in results:
        failures.extend(problems)
        mismatches += bad
        compared += count
        skipped += skipped_here
    for failure in failures:
        print(failure)
    print("lexer diff: {} fixtures, {} token lines, {} mismatches, {} skipped".format(
        len(selected), compared, mismatches, skipped))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

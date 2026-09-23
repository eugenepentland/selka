#!/usr/bin/env python3
"""Drive every carried boundary shape through both native backends and compare.

The copied-value boundary is compiler output plus a generated C adapter, so one
shape can satisfy its contract on one backend and disagree on the other without
anything failing: each backend is only ever compared against its own previous
run. This runs the same shape twice through `mylang invoke` and through
`mylang test --cases` - once with the vendored QBE and once with the LLVM
experiment that replaces it - and requires the two answers to be the same
answer, and that answer to be the one the contract declares. Agreement alone
would pass if both backends were equally wrong, so every case carries its
expected value.

The two backends are given separate caches. An object cache keyed on the source
and the manifest cannot tell a QBE object from an LLVM one, so a shared cache
would let the second backend reuse the first backend's object and the whole
comparison would be vacuous.
"""
from __future__ import annotations

import argparse
from concurrent.futures import Executor, ThreadPoolExecutor
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parent.parent
LLVM_QBE = ROOT / "experiments" / "llvm-backend" / "qbe_llvm.py"
CASES = "tests/native/list_boundary.cases.json"
AGGREF_CASES = "tests/native/aggref_arguments.cases.json"

# entry, function, request fixture path, expected `invocation.value` (None
# asserts agreement only, for a case whose value is a structure this file does
# not want to restate).
INVOKE_CASES = (
    ("tests/invoke/lists.my", "lists::sum_numbers", "tests/invoke/requests/list-numbers.json", "9"),
    ("tests/invoke/lists.my", "lists::sum_numbers", "tests/invoke/requests/list-empty.json", "0"),
    ("tests/invoke/lists.my", "lists::make_numbers", "tests/invoke/requests/list-count.json", ["0", "1", "2", "3"]),
    ("tests/invoke/lists.my", "lists::join_text", "tests/invoke/requests/list-pieces.json", "abc"),
    ("tests/invoke/lists.my", "lists::lengths", "tests/invoke/requests/list-lengths.json", ["1", "2", "3"]),
    ("tests/invoke/lists.my", "lists::bracket_all", "tests/invoke/requests/list-text.json", ["[hi]", "hi"]),
    ("tests/invoke/lists.my", "lists::row_totals", "tests/invoke/requests/list-rows.json", ["3", "3"]),
    ("tests/invoke/lists.my", "lists::scale_rows", "tests/invoke/requests/list-scale-rows.json", [["10", "20"], ["30"]]),
    ("tests/invoke/tool.my", "tool::bracket", "tests/invoke/requests/text-unicode.json", "[a\u00e9\U0001f600e\u0301]"),
    ("tests/invoke/tool.my", "tool::bracket", "tests/invoke/requests/text-nul.json", "[a\u0000b]"),
    ("tests/invoke/tool.my", "tool::bracket", "tests/invoke/requests/text-empty.json", "[]"),
    ("tests/invoke/tool.my", "tool::scale", "tests/invoke/requests/scale.json", "42"),
    ("tests/invoke/tool.my", "tool::answer", "tests/invoke/requests/empty.json", "42"),
    ("tests/invoke/tool.my", "tool::sample_label", "tests/invoke/requests/sample.json", "7"),
    ("tests/invoke/tool.my", "tool::grow", "tests/invoke/requests/grow.json", None),
    ("tests/invoke/tool.my", "tool::ratio", "tests/invoke/requests/ratio.json", None),
    ("tests/invoke/tool.my", "tool::ratio", "tests/invoke/requests/ratio-error.json", None),
    # The codec-callback boundary: a domain whose codec receives a copyable
    # aggregate by address, so the generated adapter's implicit decoder and
    # encoder both run and both have to agree between backends. `codec_round_trip`
    # exercises the two callbacks in one call, decode then encode.
    ("tests/invoke/boundary.my", "boundary::scalar_argument", "tests/invoke/requests/boundary-scalar.json", "6"),
    ("tests/invoke/boundary.my", "boundary::record_argument", "tests/invoke/requests/boundary-span.json", "1002"),
    (
        "tests/invoke/boundary.my",
        "boundary::codec_round_trip",
        "tests/invoke/requests/boundary-codec.json",
        {"n": "7", "m": "1"},
    ),
    (
        "tests/invoke/boundary.my",
        "boundary::codec_result",
        "tests/invoke/requests/boundary-codec-result.json",
        {"n": "5", "m": "1"},
    ),
    ("tests/invoke/boundary.my", "boundary::text_round_trip", "tests/invoke/requests/boundary-text.json", "[hi]"),
    ("tests/invoke/boundary.my", "boundary::variant_argument", "tests/invoke/requests/boundary-choice.json", "7"),
    (
        "tests/invoke/boundary.my",
        "boundary::empty_result",
        "tests/invoke/requests/boundary-empty.json",
        {"nothing": []},
    ),
    # An export whose body calls another function: the build lowers the target's
    # transitive call closure, so a tool composed of helpers builds like any
    # other. `shifted` reaches `twice` only through `quad`.
    ("tests/invoke/calls.my", "calls::twice", "tests/invoke/requests/call-value.json", "6"),
    ("tests/invoke/calls.my", "calls::quad", "tests/invoke/requests/call-value.json", "12"),
    ("tests/invoke/calls.my", "calls::shifted", "tests/invoke/requests/call-value.json", "13"),
    ("tests/invoke/composed.my", "composed::labels_of", "tests/invoke/requests/buckets-two.json", ["x", "y"]),
    ("tests/invoke/composed.my", "composed::grand_total", "tests/invoke/requests/buckets-two.json", "6"),
    # Lists composed with records, `Option` and `Result`: the shapes a tool
    # actually returns once text and lists cross.
    ("tests/invoke/composed.my", "composed::bucket_total", "tests/invoke/requests/bucket-one.json", "3"),
    ("tests/invoke/composed.my", "composed::bucket_labels", "tests/invoke/requests/buckets-two.json", ["x", "y"]),
    ("tests/invoke/composed.my", "composed::totals", "tests/invoke/requests/buckets-two.json", ["1", "5"]),
    (
        "tests/invoke/composed.my",
        "composed::make_buckets",
        "tests/invoke/requests/list-count.json",
        [
            {"label": "b", "values": ["0", "1"]},
            {"label": "b", "values": ["1", "2"]},
            {"label": "b", "values": ["2", "3"]},
            {"label": "b", "values": ["3", "4"]},
        ],
    ),
    ("tests/invoke/composed.my", "composed::first_or_none", "tests/invoke/requests/option-some.json", {"case": "some", "value": "7"}),
    ("tests/invoke/composed.my", "composed::first_or_none", "tests/invoke/requests/option-none.json", {"case": "none"}),
    (
        "tests/invoke/composed.my",
        "composed::find",
        "tests/invoke/requests/lookup-hit.json",
        {"case": "ok", "value": {"label": "x", "values": ["1"]}},
    ),
    (
        "tests/invoke/composed.my",
        "composed::find",
        "tests/invoke/requests/lookup-miss.json",
        {"case": "err", "value": "no bucket named z"},
    ),
    # The two worked examples, whose contracts a caller is meant to discover
    # through `--describe` rather than by reading the wire form.
    (
        "examples/invoke/reading_validator.my",
        "reading_validator::validate",
        "examples/invoke/requests/reading-ok.json",
        {"case": "ok", "value": {"site": "7", "mean": "15", "spread": "10"}},
    ),
    (
        "examples/invoke/reading_validator.my",
        "reading_validator::validate",
        "examples/invoke/requests/reading-cold.json",
        {"case": "err", "value": {"site": "3", "rule": "too_cold", "observed": "-40"}},
    ),
    (
        "examples/invoke/reading_validator.my",
        "reading_validator::validate",
        "examples/invoke/requests/reading-unsteady.json",
        {"case": "err", "value": {"site": "5", "rule": "unsteady", "observed": "90"}},
    ),
    (
        "examples/invoke/text_report.my",
        "text_report::summarize",
        "examples/invoke/requests/text-report.json",
        {"scalars": "5", "pieces": "3", "longest": "2", "empty": "1"},
    ),
    (
        "examples/invoke/text_report.my",
        "text_report::widths",
        "examples/invoke/requests/pieces.json",
        ["1", "2", "0"],
    ),
    (
        "examples/invoke/text_report.my",
        "text_report::join",
        "examples/invoke/requests/join.json",
        "a|bb|",
    ),
)

# Descriptions must agree too: an argument both backends refuse identically is
# not a shape either of them carries, and a backend that reports a different
# wire kind has already diverged before any guest code runs.
DESCRIBE_CASES = (
    ("tests/invoke/lists.my", "lists::sum_numbers"),
    ("tests/invoke/lists.my", "lists::join_text"),
    ("tests/invoke/lists.my", "lists::row_totals"),
    ("tests/invoke/lists.my", "lists::scale_rows"),
    ("tests/invoke/tool.my", "tool::bracket"),
    ("tests/invoke/tool.my", "tool::grow"),
    ("tests/invoke/tool.my", "tool::identity"),
    ("tests/invoke/tool.my", "tool::probe_filesystem"),
    ("examples/invoke/reading_validator.my", "reading_validator::validate"),
    ("examples/invoke/text_report.my", "text_report::summarize"),
    ("examples/invoke/text_report.my", "text_report::join"),
    ("examples/invoke/text_report.my", "text_report::widths"),
    ("examples/invoke/text_report.my", "text_report::bracket_all"),
    ("tests/invoke/composed.my", "composed::bucket_total"),
    ("tests/invoke/composed.my", "composed::bucket_labels"),
    ("tests/invoke/composed.my", "composed::totals"),
    ("tests/invoke/composed.my", "composed::first_or_none"),
    ("tests/invoke/composed.my", "composed::find"),
    ("tests/invoke/boundary.my", "boundary::codec_round_trip"),
    ("tests/invoke/boundary.my", "boundary::codec_result"),
    ("tests/invoke/boundary.my", "boundary::record_argument"),
    ("tests/invoke/boundary.my", "boundary::variant_argument"),
    ("tests/invoke/boundary.my", "boundary::large_argument"),
)

# Guest `.my` cases driven through `mylang test --cases`, whose codec is the same
# checked-schema codec `invoke` uses.
CASES_CASES = (
    ("tests/native/list_boundary.my", CASES),
    ("tests/native/aggref_arguments.my", AGGREF_CASES),
)


class Failure(Exception):
    """One case did not hold."""


def run(compiler: Path, argv: list[str], cache: Path, timeout: float) -> subprocess.CompletedProcess:
    """Run the compiler with one backend's cache and return the finished process."""
    command = [str(compiler), *argv, f"--cache-dir={cache}"]
    return subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=timeout)


def payload(proc: subprocess.CompletedProcess, label: str) -> dict:
    """Parse the single JSON object a command prints, or fail with its stderr."""
    text = proc.stdout.strip()
    if not text:
        raise Failure(f"{label}: no output (exit {proc.returncode}): {proc.stderr.strip()[:300]}")
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        raise Failure(f"{label}: output is not one JSON object: {exc}: {text[:300]}") from exc


def comparable(report: dict) -> dict:
    """The part of a report the backend is not allowed to change.

    `context` carries the compiler identity, which is the backend by
    construction, so it is dropped rather than compared. Everything a caller can
    observe about the call - whether it ran, what it returned, how it refused -
    is kept.
    """
    keep = {key: report[key] for key in ("status", "invocation", "description", "failure") if key in report}
    failure = keep.get("failure")
    if isinstance(failure, dict):
        # `diagnostics` can name a backend-specific path; the kind and reason are
        # the contract.
        keep["failure"] = {key: failure[key] for key in ("kind", "path", "reason") if key in failure}
    return keep


def invoke_argv(entry: str, function: str, request: str) -> list[str]:
    """The argv for one `mylang invoke` call, with no backend selected yet."""
    return ["invoke", entry, "--function", function, f"--input={request}"]


def with_backend(argv: list[str], qbe: Path | None) -> list[str]:
    """Select one backend, or leave the vendored QBE in place."""
    return argv if qbe is None else [*argv, f"--qbe={qbe}"]


def check_invoke(compiler: Path, caches: dict, timeout: float, pool: Executor) -> Callable[[], list[str]]:
    """Start every invoke case on both backends; the result compares them, one line each."""
    pending = []
    for entry, function, request, expected in INVOKE_CASES:
        label = f"invoke {function} {Path(request).name}"
        runs = {name: pool.submit(run, compiler, with_backend(invoke_argv(entry, function, request), qbe["qbe"]), qbe["cache"], timeout)
                for name, qbe in caches.items()}
        pending.append((label, expected, runs))

    def finish() -> list[str]:
        lines = []
        for label, expected, runs in pending:
            reports = {name: payload(proc.result(), f"{label} [{name}]") for name, proc in runs.items()}
            first, second = reports["qbe"], reports["llvm"]
            if comparable(first) != comparable(second):
                raise Failure(f"{label}: backends disagree\n  qbe : {json.dumps(comparable(first))[:400]}\n  llvm: {json.dumps(comparable(second))[:400]}")
            if expected is not None:
                actual = first.get("invocation", {}).get("value")
                if actual != expected:
                    raise Failure(f"{label}: expected {json.dumps(expected)}, got {json.dumps(actual)}")
            lines.append(f"agree  {label} -> {json.dumps(first.get('invocation', {}).get('value'))[:60]}")
        return lines
    return finish


def check_describe(compiler: Path, caches: dict, timeout: float, pool: Executor) -> Callable[[], list[str]]:
    """Start the schema query for every export on both backends; the result compares them."""
    pending = []
    for entry, function in DESCRIBE_CASES:
        label = f"describe {function}"
        runs = {name: pool.submit(run, compiler, with_backend(["invoke", entry, "--function", function, "--describe"], qbe["qbe"]), qbe["cache"], timeout)
                for name, qbe in caches.items()}
        pending.append((label, runs))

    def finish() -> list[str]:
        lines = []
        for label, runs in pending:
            reports = {name: payload(proc.result(), f"{label} [{name}]") for name, proc in runs.items()}
            first, second = reports["qbe"], reports["llvm"]
            if comparable(first) != comparable(second):
                raise Failure(f"{label}: backends disagree\n  qbe : {json.dumps(comparable(first))[:400]}\n  llvm: {json.dumps(comparable(second))[:400]}")
            status = first.get("description", {})
            lines.append(f"agree  {label} -> eligible={status.get('eligible')} wire={status.get('wire_supported')}")
        return lines
    return finish


def check_cases(compiler: Path, caches: dict, timeout: float, pool: Executor) -> Callable[[], list[str]]:
    """Start `mylang test --cases` on both backends over the shared codec; the result compares them."""
    pending = []
    for entry, cases in CASES_CASES:
        label = f"cases {Path(entry).name}"
        runs = {name: pool.submit(run, compiler, with_backend(["test", entry, "--cases", cases], qbe["qbe"]), qbe["cache"], timeout)
                for name, qbe in caches.items()}
        pending.append((label, runs))

    def finish() -> list[str]:
        lines = []
        for label, runs in pending:
            results = {}
            for name, future in runs.items():
                proc = future.result()
                if proc.returncode != 0:
                    raise Failure(f"{label} [{name}]: exit {proc.returncode}\n{proc.stdout[-400:]}\n{proc.stderr[-400:]}")
                summary = proc.stdout.strip().splitlines()[-1] if proc.stdout.strip() else ""
                if "0 failed" not in summary:
                    raise Failure(f"{label} [{name}]: {summary}")
                results[name] = summary
            if results["qbe"] != results["llvm"]:
                raise Failure(f"{label}: backends disagree\n  qbe : {results['qbe']}\n  llvm: {results['llvm']}")
            lines.append(f"agree  {label} -> {results['qbe']}")
        return lines
    return finish


def default_jobs() -> int:
    """Commands run at once: `MYLANG_JOBS` when set, else the cores up to 8."""
    try:
        return max(1, int(os.environ["MYLANG_JOBS"]))
    except (KeyError, ValueError):
        return max(1, min(8, os.cpu_count() or 1))


def self_test() -> None:
    """Check the comparator without needing a compiler or a backend."""
    base = {"status": "completed", "invocation": {"value": "9"}, "context": {"identities": {"compiler": "a"}}}
    same = {"status": "completed", "invocation": {"value": "9"}, "context": {"identities": {"compiler": "b"}}}
    if comparable(base) != comparable(same):
        raise Failure("self-test: the backend identity must not affect the comparison")
    differ = {"status": "completed", "invocation": {"value": "10"}, "context": {"identities": {"compiler": "b"}}}
    if comparable(base) == comparable(differ):
        raise Failure("self-test: a different value must be a difference")
    # A refusal keeps its kind and reason but not a backend-specific diagnostic.
    refused = {"status": "setup-failure", "failure": {"kind": "unsupported-type", "reason": "nope", "diagnostics": "qbe/path"}}
    moved = {"status": "setup-failure", "failure": {"kind": "unsupported-type", "reason": "nope", "diagnostics": "llvm/path"}}
    if comparable(refused) != comparable(moved):
        raise Failure("self-test: a backend-specific diagnostic must not be a difference")
    print("self-test: the comparator keeps the contract and drops the backend identity")


def main() -> int:
    """Run the matrix, or the comparator self-test."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", help="check the comparator and exit")
    parser.add_argument("--compiler", type=Path, help="the mylang binary under test")
    parser.add_argument("--timeout", type=float, default=180.0, help="seconds allowed per command")
    parser.add_argument("--keep", action="store_true", help="keep the per-backend caches for inspection")
    parser.add_argument("--jobs", type=int, default=default_jobs(), help="commands run at once (default: MYLANG_JOBS, else up to 8)")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if args.compiler is None:
        parser.error("--compiler is required unless --self-test is given")
    if not LLVM_QBE.is_file():
        # Not a skip: a matrix that silently runs one backend is not a matrix.
        print(f"native-boundary: the LLVM backend is missing at {LLVM_QBE}", file=sys.stderr)
        return 1
    root = Path(tempfile.mkdtemp(prefix="mylang-boundary-"))
    try:
        caches = {
            "qbe": {"qbe": None, "cache": root / "qbe"},
            "llvm": {"qbe": LLVM_QBE, "cache": root / "llvm"},
        }
        # Every command is independent and each backend has its own cache, so
        # they all run concurrently; the comparisons still happen in case order.
        lines = []
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            checks = [check(args.compiler, caches, args.timeout, pool) for check in (check_invoke, check_describe, check_cases)]
            for finish in checks:
                lines += finish()
        for line in lines:
            print(line)
        print(f"native-boundary: {len(lines)} case(s) agree across QBE and LLVM")
    finally:
        if args.keep:
            print(f"caches kept under {root}", file=sys.stderr)
        else:
            shutil.rmtree(root, ignore_errors=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Failure as failure:
        print(f"native-boundary: {failure}", file=sys.stderr)
        sys.exit(1)

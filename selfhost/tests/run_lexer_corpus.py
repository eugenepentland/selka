#!/usr/bin/env python3
"""Corpus-scale differential lexer check: stage-0 versus ``selfhost/lexer.selka``.

The fixture harness (``run_lexer_diff.py``) exercises hand-written edge cases.
This one casts a much wider net: it runs both lexers over every ``.selka`` file in
the repository's own source trees and compares the full token stream.

    python3 selfhost/tests/run_lexer_corpus.py

The stage-0 side is the pinned compiler's ``dump-tokens`` command; the self-host
side is ``selfhost/lexer.selka`` built once with the same pinned stage 0. A file
whose stage-0 lexer reports a lexical error is counted as *unchecked* rather
than compared token-by-token: the corpus is real source, so a lexical error
means the file is not a clean input (or the oracle itself is stale), and the
fixture harness owns located-error comparisons.

``--paths`` (repeatable, glob) overrides the default corpus roots, ``--jobs N``
parallelizes the per-file stage-0 invocations, and ``--max-report`` bounds how
many mismatches are printed. Exit status is 0 only when at least one file was
compared and none mismatched.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import glob
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import stage0  # noqa: E402 - sibling pin authority, imported after sys.path setup
PROGRAM = "selfhost/lexer.selka"
DEFAULT_PATHS = (
    "tests/lang/**/*.selka",
    "examples/**/*.selka",
    "src/stdlib/**/*.selka",
    "src/schematic/**/*.selka",
)


def corpus(paths):
    """Return the sorted, de-duplicated corpus the harness will compare."""
    found = []
    for pattern in paths:
        found.extend(glob.glob(str(ROOT / pattern), recursive=True))
    return sorted({Path(p) for p in found if Path(p).is_file()})


def build_lexer(output):
    """Build ``selfhost/lexer.selka`` with the pinned stage 0; return 0 or 2."""
    command = [
        str(stage0.require()),
        "build",
        PROGRAM,
        "--project",
        "--backend",
        "qbe",
        "-o",
        str(output),
    ]
    result = subprocess.run(
        command, cwd=str(ROOT), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    if result.returncode != 0:
        sys.stderr.write("lexer corpus: cannot build %s (exit %d)\n" % (PROGRAM, result.returncode))
        tail = (result.stderr or result.stdout).strip().splitlines()[-8:]
        for line in tail:
            sys.stderr.write("  %s\n" % line)
    return 0 if result.returncode == 0 else 2


def expected_tokens(compiler, path):
    """Stage-0 token lines for ``path``, or None when stage 0 reports an error."""
    result = subprocess.run(
        [str(compiler), "dump-tokens", str(path)],
        cwd=str(ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode != 0:
        return None
    try:
        document = json.loads(result.stdout)
    except ValueError:
        return None
    return [
        "%s %d %d" % (token["kind"], token["start"], token["end"])
        for token in document["tokens"]
    ]


def compare_one(work, compiler, lexer, path):
    """Compare one file; return ``(status, detail)`` where status is compare/unchecked/mismatch."""
    expected = expected_tokens(compiler, path)
    if expected is None:
        return path, "unchecked", ""
    result = subprocess.run(
        [str(lexer), str(path)],
        cwd=str(ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    actual = result.stdout.splitlines()
    if actual and actual[0].startswith("error"):
        return path, "mismatch", "self-host %s" % actual[0]
    if expected == actual:
        return path, "compare", ""
    for index in range(max(len(expected), len(actual))):
        want = expected[index] if index < len(expected) else "<missing>"
        got = actual[index] if index < len(actual) else "<missing>"
        if want != got:
            return path, "mismatch", "line %d: want %s got %s" % (index + 1, want, got)
    return path, "mismatch", "length differs"


def main(argv=None):
    """Run the corpus comparison and return the process exit status."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--paths", action="append", help="glob under the repo root (repeatable)")
    parser.add_argument("--jobs", type=int, default=4, help="parallel stage-0 invocations")
    parser.add_argument("--max-report", type=int, default=20, help="mismatches to print")
    parser.add_argument("--lexer", help="reuse a prebuilt self-host lexer instead of building")
    args = parser.parse_args(argv)

    files = corpus(args.paths or DEFAULT_PATHS)
    if not files:
        sys.stderr.write("lexer corpus: no files matched\n")
        return 2

    with tempfile.TemporaryDirectory(prefix="lexer-corpus-") as work:
        lexer = Path(args.lexer) if args.lexer else Path(work) / "lexer"
        if args.lexer is None:
            status = build_lexer(lexer)
            if status != 0:
                return status
        compiler = stage0.require()

        compared = unchecked = 0
        mismatches = []
        jobs = max(1, min(args.jobs, 8))
        with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
            futures = [
                pool.submit(compare_one, work, compiler, lexer, path) for path in files
            ]
            for future in concurrent.futures.as_completed(futures):
                path, status, detail = future.result()
                if status == "compare":
                    compared += 1
                elif status == "unchecked":
                    unchecked += 1
                else:
                    mismatches.append((path, detail))

    mismatches.sort()
    for path, detail in mismatches[: args.max_report]:
        print("  %s: %s" % (path.relative_to(ROOT), detail))
    if len(mismatches) > args.max_report:
        print("  ... %d more" % (len(mismatches) - args.max_report))
    print(
        "lexer corpus: %d files, %d compared, %d unchecked, %d mismatches"
        % (len(files), compared, unchecked, len(mismatches))
    )
    return 0 if compared and not mismatches else 1


if __name__ == "__main__":
    sys.exit(main())

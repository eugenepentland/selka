#!/usr/bin/env python3
"""Check a candidate lexer or parser against the Zig front end over the syntax corpus.

Run from anywhere; paths are relative to the repository root:

    python3 selfhost/tests/syntax_parity.py --self --compiler zig-out/bin/selka
    python3 selfhost/tests/syntax_parity.py --lexer 'build/lexer {file}' --compiler zig-out/bin/selka
    python3 selfhost/tests/syntax_parity.py --parser 'build/parser {file} {flags}' --compiler ...

The corpus is `selfhost/corpus.json`: globs over the repository's `.selka` files, the
selka-projects tree when it exists, and the negative fixtures. Every file is an
oracle input whether it parses or not.

* The lexer oracle is `selka dump-tokens FILE`. A candidate lexer is a command that
  prints the same `tokens-v1` document on standard output and exits 0, or exits 1
  with the rendered diagnostics of the Zig lexer on standard error. Exit status and
  standard output must match, and standard error too when both fail.
* The parser oracle is `selka dump-syntax FILE [FLAGS]` (`selfhost/syntax-frame`
  in `src/syntax_dump.zig`): the `StoredSyntax` payload and the diagnostics in one
  frame. A candidate parser prints the same bytes. `{flags}` expands to the flags a
  corpus root asks for (`--trusted` for the embedded standard library); the mode
  (`--module` or `--program`) is left to the candidate, which must choose as the Zig
  rule does, and the frame's mode byte is compared.
* `--self` makes the Zig front end its own candidate: it shows the harness and the
  oracle agree (zero mismatches, and the oracle is deterministic).

A mismatch names the file and the first difference: for a lexer the first differing
token, for a parser the first differing field path of the payload
(`selka dump-syntax --diff REFERENCE CANDIDATE`). The report is at most a screen;
`--json PATH` keeps every record. Exit status: 0 when every compared file matches,
1 on any mismatch, 2 when the corpus or a command line is wrong (including a
negative fixture the reference accepts).
"""
from __future__ import annotations

import argparse
import collections
import concurrent.futures
import json
import os
import re
import shlex
import struct
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "selfhost" / "corpus.json"
MAGIC = b"SLKSYN01"
TIMEOUT_SECONDS = 120
SUPPORTED_CORPUS = "syntax-corpus-v1"


class CorpusError(Exception):
    """The corpus file, a command line or the oracle itself is wrong (exit 2)."""


# ---------------------------------------------------------------------------
# The corpus.
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Entry:
    """One corpus file: where to find it, how the compiler names it, and its flags."""

    root: str
    display: str
    argument: str
    trusted: bool
    negative: bool

    def flags(self) -> list[str]:
        return ["--trusted"] if self.trusted else []


def glob_regex(pattern: str) -> re.Pattern[str]:
    """Translate a path glob (`**` crosses directories, `*` and `?` do not) to a regex."""
    out: list[str] = []
    i = 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
        elif pattern.startswith("**", i):
            out.append(".*")
            i += 2
        elif pattern[i] == "*":
            out.append("[^/]*")
            i += 1
        elif pattern[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(pattern[i]))
            i += 1
    return re.compile("".join(out) + r"\Z")


def walk(base: Path, pattern: re.Pattern[str]) -> list[str]:
    """Relative paths under `base` that match `pattern`, skipping hidden directories."""
    found: list[str] = []
    for directory, subdirs, files in os.walk(base):
        subdirs[:] = sorted(d for d in subdirs if not d.startswith("."))
        for name in sorted(files):
            relative = (Path(directory) / name).relative_to(base).as_posix()
            if pattern.match(relative):
                found.append(relative)
    return found


def load_corpus(path: Path, in_tree: bool) -> tuple[list[Entry], dict[str, int]]:
    """Resolve the corpus file into sorted entries; the second value counts skipped optional roots."""
    document = json.loads(path.read_text())
    if document.get("version") != SUPPORTED_CORPUS:
        raise CorpusError(f"{path}: version is not {SUPPORTED_CORPUS}")
    excludes = [glob_regex(p) for p in document.get("exclude", [])]
    negatives = [glob_regex(p) for p in document.get("negative", [])]
    entries: dict[str, Entry] = {}
    skipped: dict[str, int] = {}
    for root in document["roots"]:
        base = Path(root["path"])
        external = base.is_absolute()
        if root.get("optional") and (in_tree or not base.is_dir()):
            skipped[root["name"]] = 1
            continue
        if not external:
            base = ROOT / base
        if not base.is_dir():
            raise CorpusError(f"corpus root {root['name']}: {base} is not a directory")
        for relative in walk(base, glob_regex(root["glob"])):
            # Names are repository-relative for in-tree roots, `name/relative` for an outside root.
            display = f"{root['name']}/{relative}" if external else (Path(root["path"]) / relative).as_posix()
            if any(rx.match(display) for rx in excludes):
                continue
            argument = str(base / relative) if external else display
            entries.setdefault(display, Entry(
                root=root["name"],
                display=display,
                argument=argument,
                trusted=bool(root.get("trusted")),
                negative=any(rx.match(display) for rx in negatives),
            ))
    return [entries[key] for key in sorted(entries)], skipped


# ---------------------------------------------------------------------------
# The frame `selka dump-syntax` writes (src/syntax_dump.zig).
# ---------------------------------------------------------------------------


class FrameError(Exception):
    """The bytes are not a well-formed syntax frame."""


class Reader:
    def __init__(self, data: bytes) -> None:
        self.data = data
        self.at = 0

    def take(self, count: int) -> bytes:
        if count < 0 or self.at + count > len(self.data):
            raise FrameError(f"frame ends inside a field at byte {self.at}")
        chunk = self.data[self.at:self.at + count]
        self.at += count
        return chunk

    def u8(self) -> int:
        return self.take(1)[0]

    def u64(self) -> int:
        return struct.unpack("<Q", self.take(8))[0]

    def blob(self) -> bytes:
        return self.take(self.u64())

    def text(self) -> str:
        return self.blob().decode("utf-8", "replace")

    def span(self) -> tuple[int, int]:
        return (self.u64(), self.u64())

    def option(self, read):
        flag = self.u8()
        if flag > 1:
            raise FrameError(f"option byte {flag} at {self.at - 1}")
        return read() if flag else None

    def note(self) -> dict:
        return {"span": self.span(), "message": self.text(), "role": self.u8()}

    def edit(self) -> dict:
        return {"span": self.span(), "text": self.text()}


@dataclass
class Frame:
    mode: int
    trusted: bool
    outcome: int
    payload: bytes
    diagnostics: list[dict] = field(default_factory=list)


def decode_frame(data: bytes) -> Frame:
    """Decode a frame far enough to summarise it; the bytes themselves are what is compared."""
    reader = Reader(data)
    if reader.take(len(MAGIC)) != MAGIC:
        raise FrameError("magic is not SLKSYN01")
    mode, trusted, outcome = reader.u8(), reader.u8(), reader.u8()
    payload = reader.blob()
    diagnostics = []
    for _ in range(reader.u64()):
        diagnostics.append({
            "code": reader.text(),
            "severity": reader.u8(),
            "span": reader.span(),
            "message": reader.text(),
            "related": reader.option(reader.note),
            "origin": reader.option(reader.note),
            "requirement": reader.option(reader.note),
            "fix": [reader.edit() for _ in range(reader.u64())],
            "rule": reader.option(reader.text),
        })
    if reader.at != len(data):
        raise FrameError(f"{len(data) - reader.at} trailing byte(s)")
    return Frame(mode, bool(trusted), outcome, payload, diagnostics)


# ---------------------------------------------------------------------------
# Running commands.
# ---------------------------------------------------------------------------


@dataclass
class Run:
    status: int
    out: bytes
    err: bytes


def execute(argv: list[str], cwd: Path) -> Run:
    try:
        done = subprocess.run(argv, cwd=cwd, capture_output=True, timeout=TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired:
        return Run(-1, b"", f"timed out after {TIMEOUT_SECONDS} s".encode())
    except OSError as problem:
        raise CorpusError(f"cannot run {argv[0]}: {problem}") from problem
    return Run(done.returncode, done.stdout, done.stderr)


def expand(template: str, entry: Entry) -> list[str]:
    """Split a candidate command and fill `{file}` and `{flags}`; a template without `{file}` gets it last."""
    words = shlex.split(template)
    argv: list[str] = []
    used = False
    for word in words:
        if word == "{flags}":
            argv.extend(entry.flags())
        elif "{file}" in word:
            argv.append(word.replace("{file}", entry.argument))
            used = True
        else:
            argv.append(word)
    if not used:
        argv.append(entry.argument)
    return argv


# ---------------------------------------------------------------------------
# Comparison.
# ---------------------------------------------------------------------------


def first_difference(left: bytes, right: bytes) -> int:
    for index, (a, b) in enumerate(zip(left, right)):
        if a != b:
            return index
    return min(len(left), len(right))


def describe_lexer(reference: Run, candidate: Run) -> str:
    if reference.status != candidate.status:
        detail = candidate.err.decode("utf-8", "replace").strip().splitlines()[:1]
        return f"exit status {candidate.status}, reference {reference.status}" + (f" ({detail[0]})" if detail else "")
    if reference.status == 0:
        try:
            ours = json.loads(candidate.out)["tokens"]
            theirs = json.loads(reference.out)["tokens"]
        except (ValueError, KeyError):
            return f"standard output differs at byte {first_difference(reference.out, candidate.out)}"
        for index, (a, b) in enumerate(zip(ours, theirs)):
            if a != b:
                return f"token {index}: {json.dumps(a, separators=(',', ':'))}, reference {json.dumps(b, separators=(',', ':'))}"
        return f"token count {len(ours)}, reference {len(theirs)}"
    return f"diagnostics differ at byte {first_difference(reference.err, candidate.err)}"


def describe_parser(compiler: Path, reference: Run, candidate: Run) -> str:
    if candidate.status != 0:
        detail = candidate.err.decode("utf-8", "replace").strip().splitlines()[:1]
        return f"exit status {candidate.status}" + (f" ({detail[0]})" if detail else "")
    with tempfile.TemporaryDirectory() as scratch:
        want, got = Path(scratch, "reference.frame"), Path(scratch, "candidate.frame")
        want.write_bytes(reference.out)
        got.write_bytes(candidate.out)
        told = execute([str(compiler), "dump-syntax", "--diff", str(want), str(got)], ROOT)
    line = told.out.decode("utf-8", "replace").strip()
    return line if told.status == 1 and line else f"bytes differ at {first_difference(reference.out, candidate.out)}"


@dataclass
class Result:
    entry: Entry
    refused: bool = False
    first_code: str = ""
    tokens_failed: bool = False
    mismatches: list[tuple[str, str]] = field(default_factory=list)
    problem: str = ""


def check_entry(entry: Entry, args: argparse.Namespace) -> Result:
    """Run the oracle (and the candidates) on one file."""
    result = Result(entry)
    compiler: Path = args.compiler
    reference = execute([str(compiler), "dump-syntax", entry.argument, *entry.flags()], ROOT)
    if reference.status != 0:
        result.problem = f"dump-syntax exited {reference.status}: {reference.err.decode('utf-8', 'replace').strip()[:200]}"
        return result
    try:
        frame = decode_frame(reference.out)
    except FrameError as problem:
        result.problem = f"dump-syntax wrote a malformed frame: {problem}"
        return result
    result.refused = frame.outcome == 1
    result.first_code = frame.diagnostics[0]["code"] if frame.diagnostics else ""
    tokens = execute([str(compiler), "dump-tokens", entry.argument], ROOT)
    result.tokens_failed = tokens.status != 0
    if args.lexer:
        candidate = execute(expand(args.lexer, entry), ROOT)
        same = candidate.status == tokens.status and candidate.out == tokens.out and (tokens.status == 0 or candidate.err == tokens.err)
        if not same:
            result.mismatches.append(("lexer", describe_lexer(tokens, candidate)))
    if args.parser:
        candidate = execute(expand(args.parser, entry), ROOT)
        if candidate.status != 0 or candidate.out != reference.out:
            result.mismatches.append(("parser", describe_parser(compiler, reference, candidate)))
    return result


# ---------------------------------------------------------------------------
# The report.
# ---------------------------------------------------------------------------


def report(results: list[Result], skipped: dict[str, int], args: argparse.Namespace, seconds: float) -> list[str]:
    lines: list[str] = []
    by_root = collections.Counter(r.entry.root for r in results)
    refused = [r for r in results if r.refused]
    codes = collections.Counter(r.first_code for r in refused)
    lines.append(f"corpus: {len(results)} files in {len(by_root)} roots ({', '.join(f'{k} {v}' for k, v in by_root.items())})")
    if skipped:
        lines.append(f"skipped optional roots: {', '.join(sorted(skipped))}")
    lines.append(
        f"reference: {len(results) - len(refused)} parsed, {len(refused)} refused "
        f"({', '.join(f'{code} {n}' for code, n in codes.most_common(6))}); "
        f"{sum(r.tokens_failed for r in results)} fail in the lexer; "
        f"{sum(r.entry.negative for r in results)} declared negative"
    )
    kinds = [kind for kind, template in (("lexer", args.lexer), ("parser", args.parser)) if template]
    for kind in kinds:
        bad = [r for r in results if any(k == kind for k, _ in r.mismatches)]
        lines.append(f"{kind}: {len(results)} compared, {len(bad)} mismatches")
        for r in bad[:8]:
            lines.append(f"  {r.entry.display}: " + next(text for k, text in r.mismatches if k == kind))
        if len(bad) > 8:
            lines.append(f"  ... and {len(bad) - 8} more (--json PATH keeps them all)")
    lines.append(f"{seconds:.1f} s with {args.jobs} job(s)")
    return lines


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--compiler", type=Path, default=ROOT / "zig-out" / "bin" / "selka", help="the Zig front end (the oracle)")
    parser.add_argument("--corpus", type=Path, default=CORPUS)
    parser.add_argument("--self", action="store_true", dest="self_check", help="use the compiler's own dump commands as the candidates")
    parser.add_argument("--lexer", help="candidate lexer command; {file} is the source path")
    parser.add_argument("--parser", help="candidate parser command; {file} is the source path, {flags} the root's flags")
    parser.add_argument("--in-tree", action="store_true", help="skip roots outside the repository (the gate's setting)")
    parser.add_argument("--filter", action="append", default=[], metavar="SUBSTRING", help="only files whose name contains a substring")
    parser.add_argument("--list", action="store_true", help="print the resolved corpus and exit")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--json", type=Path, help="write every record to this file")
    return parser


def main(argv: list[str]) -> int:
    args = build_parser().parse_args(argv)
    try:
        entries, skipped = load_corpus(args.corpus, args.in_tree)
        if args.filter:
            entries = [e for e in entries if any(f in e.display for f in args.filter)]
        if args.list:
            for entry in entries:
                print(entry.display, "negative" if entry.negative else "", *entry.flags())
            return 0
        if not args.compiler.is_file():
            raise CorpusError(f"{args.compiler}: no such compiler (build it, or pass --compiler)")
        args.compiler = args.compiler.resolve()
        if args.self_check:
            args.lexer = args.lexer or f"{shlex.quote(str(args.compiler))} dump-tokens {{file}}"
            args.parser = args.parser or f"{shlex.quote(str(args.compiler))} dump-syntax {{file}} {{flags}}"
        started = time.monotonic()
        with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
            results = list(pool.map(lambda e: check_entry(e, args), entries))
        seconds = time.monotonic() - started
        broken = [r for r in results if r.problem]
        if broken:
            raise CorpusError("\n".join(f"{r.entry.display}: {r.problem}" for r in broken[:10]))
        accepted_negatives = [r.entry.display for r in results if r.entry.negative and not r.refused]
        if accepted_negatives:
            raise CorpusError("negative fixtures the reference accepts: " + ", ".join(accepted_negatives[:10]))
    except CorpusError as problem:
        print(f"syntax_parity: {problem}", file=sys.stderr)
        return 2
    for line in report(results, skipped, args, seconds):
        print(line)
    if args.json:
        args.json.write_text(json.dumps({
            "corpus": args.corpus.as_posix(),
            "files": [{
                "file": r.entry.display, "root": r.entry.root, "refused": r.refused, "code": r.first_code,
                "lexer_failed": r.tokens_failed, "negative": r.entry.negative,
                "mismatches": [{"kind": k, "detail": d} for k, d in r.mismatches],
            } for r in results],
        }, indent=1) + "\n")
    return 1 if any(r.mismatches for r in results) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

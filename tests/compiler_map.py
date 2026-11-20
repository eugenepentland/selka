#!/usr/bin/env python3
"""The compiler map's check: fail when `docs/tooling/compiler-map.md` names a file or a function that is not there.

The page tells an agent where each stage of the compiler lives and which files a common change touches. It stays true only
while the files and functions it names exist, so this driver reads the page and prints one line `file:line: message` for each
thing that does not. It runs inside the gate action `goals_register` (`tests/goals_register.py --map PAGE`), which already
reads documentation and checks the paths it names, and it runs alone:

    python3 tests/compiler_map.py
    python3 tests/compiler_map.py --root DIR --page docs/tooling/compiler-map.md

A finding is one of:

* path: a backquoted repository path does not exist (`<name>` and `*` in a path stand for any name and must match a file;
  a path ending in `/` is a directory; build outputs under `zig-out/`, `.selka-cache/` and `.zig-cache/` are not checked);
* function: `` `path: name` `` names a function the file does not declare (`fn` in Zig, `func` in Selka, `def` in Python,
  a definition in C, a theorem or definition in Lean), comment lines left out; the colon sits inside the backquotes;
* command: a backquoted command (a span with a space) names a repository path that does not exist;
* size: the page is longer than LINE_LIMIT lines or has a line longer than WIDTH_LIMIT characters;
* inputs: a named path is not covered by the `goals_register` list of `build_test_inputs.zig`, so an edit to it would
  leave a stale green verdict.

Fenced blocks are skipped. Exit status: 0 when nothing is found, 1 when something is, 2 on a usage error.
"""
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_inputs_coverage  # noqa: E402  (the one parser of build_test_inputs.zig lists)

PAGE = "docs/tooling/compiler-map.md"
LIST_NAME = "goals_register"
LINE_LIMIT = 300
WIDTH_LIMIT = 120
OUTPUT_PREFIXES = ("zig-out/", ".selka-cache/", ".zig-cache/", "~", "/")
FILE_EXTENSIONS = ("md", "zig", "lean", "py", "selka", "json", "zon", "toml", "sh", "txt", "c", "h")
TOP_LEVELS = ("src/", "scripts/", "tests/", "test/", "docs/", "tools/", "proofs/", "selfhost/", "experiments/")
TOP_FILES = ("build.zig", "build_test_inputs.zig", "CLAUDE.md", "CHANGES.md", "SPEC.md")
PATH_TOKEN = re.compile(r"^[\w.+*?<>-]+(?:/[\w.+*?<>-]+)*/?$")
EXTENSION_TOKEN = re.compile(r"^[\w.+*?<>-]*[\w+*?>-]\.(?:%s)$" % "|".join(FILE_EXTENSIONS))
PAIR = re.compile(r"^(\S+?):\s+([A-Za-z_][\w.]*)$")


@dataclass
class Finding:
    """One thing the page says that is not true: where it is written, which check found it and what was expected."""

    path: str
    line: int
    kind: str
    message: str

    def __str__(self) -> str:
        where = "{}:{}".format(self.path, self.line) if self.line else self.path
        return "{}: {}: {}".format(where, self.kind, self.message)


@dataclass
class Span:
    """A backquoted span of the page: its text and its 1-based line."""

    text: str
    line: int


@dataclass
class Report:
    """The findings of one run and the counts of what was checked, for the one-line summary."""

    findings: list[Finding] = field(default_factory=list)
    counts: dict[str, int] = field(default_factory=dict)


def mask_fences(text: str) -> str:
    """The text with every fenced block blanked, newlines kept, so line numbers still match."""
    def blank(match: re.Match[str]) -> str:
        return re.sub(r"[^\n]", " ", match.group())
    return re.sub(r"^(```|~~~).*?^\1[ \t]*$", blank, text, flags=re.M | re.S)


def spans_of(masked: str) -> list[Span]:
    """Every backquoted span outside fenced blocks, in order, with its line."""
    return [Span(m.group(1), masked.count("\n", 0, m.start()) + 1) for m in re.finditer(r"`([^`\n]+)`", masked)]


def is_path(token: str) -> bool:
    """Whether a token is a repository path: no space, a `/` or a known file extension, a top-level directory or file."""
    if not PATH_TOKEN.match(token):
        return False
    if "/" in token:
        return token.startswith(TOP_LEVELS) or token in TOP_FILES
    return bool(EXTENSION_TOKEN.match(token)) and token in TOP_FILES


def expand(root: Path, path: str) -> list[str] | None:
    """The repository paths a token names, or None when it is a build output that is not checked.

    `<name>` and `*` stand for any name within one path segment. An empty list means nothing matches."""
    if path.startswith(OUTPUT_PREFIXES):
        return None
    pattern = re.sub(r"<[^>]*>", "*", path)
    if re.search(r"[*?]", pattern):
        return sorted(p.relative_to(root).as_posix() for p in root.glob(pattern.rstrip("/")))
    target = root / pattern.rstrip("/")
    if pattern.endswith("/"):
        return [pattern] if target.is_dir() else []
    return [pattern] if target.exists() else []


def declared(file: Path, name: str) -> bool:
    """Whether a source file declares a function called `name`, by the file's own keyword; comment lines are left out."""
    last = name.rsplit(".", 1)[-1]
    suffix = file.suffix
    lines = file.read_text(errors="replace").splitlines()
    if suffix == ".zig":
        code = [line for line in lines if not line.lstrip().startswith("//")]
        pattern = r"\bfn\s+%s\b" % re.escape(last)
    elif suffix == ".selka":
        code = [line for line in lines if not line.lstrip().startswith("#")]
        pattern = r"\bfunc\s+%s\b" % re.escape(last)
    elif suffix == ".py":
        code = [line for line in lines if not line.lstrip().startswith("#")]
        pattern = r"\bdef\s+%s\b" % re.escape(last)
    elif suffix in (".c", ".h"):
        code = [line for line in lines if not line.lstrip().startswith(("//", "/*", "*"))]
        pattern = r"\b%s\s*\(" % re.escape(last)
    elif suffix == ".lean":
        code = [line for line in lines if not line.lstrip().startswith("--")]
        pattern = r"\b(?:theorem|lemma|def)\s+(?:[\w.]*\.)?%s\b" % re.escape(last)
    else:
        code = lines
        pattern = r"\b%s\b" % re.escape(last)
    return any(re.search(pattern, line) for line in code)


def check_size(page: str, text: str, report: Report) -> None:
    """The page has at most LINE_LIMIT lines of at most WIDTH_LIMIT characters."""
    lines = text.splitlines()
    if len(lines) > LINE_LIMIT:
        report.findings.append(Finding(page, len(lines), "size", "the page has {} lines; the limit is {}".format(len(lines), LINE_LIMIT)))
    for number, line in enumerate(lines, 1):
        if len(line) > WIDTH_LIMIT:
            report.findings.append(Finding(page, number, "size", "the line has {} characters; the limit is {}".format(len(line), WIDTH_LIMIT)))
    report.counts["lines"] = len(lines)


def check_spans(root: Path, page: str, spans: list[Span], report: Report) -> list[tuple[str, int]]:
    """Every named path exists and every `path: function` pair names a function the file declares; returns the paths found."""
    named: list[tuple[str, int]] = []
    paths = functions = 0
    for span in spans:
        pair = PAIR.match(span.text)
        if pair and is_path(pair.group(1)):
            path, name = pair.group(1), pair.group(2)
            found = expand(root, path)
            paths += 1
            functions += 1
            if found is None:
                continue
            if not found:
                report.findings.append(Finding(page, span.line, "path", "`{}` does not exist".format(path)))
                continue
            named.extend((match, span.line) for match in found)
            for match in found:
                if (root / match).is_file() and not declared(root / match, name):
                    report.findings.append(Finding(page, span.line, "function", "`{}` declares no function `{}`".format(match, name)))
        elif is_path(span.text):
            found = expand(root, span.text)
            paths += 1
            if found is None:
                continue
            if not found:
                report.findings.append(Finding(page, span.line, "path", "`{}` does not exist".format(span.text)))
                continue
            named.extend((match, span.line) for match in found)
        elif " " in span.text:
            for word in span.text.split():
                word = word.strip(",;()")
                if not is_path(word):
                    continue
                found = expand(root, word)
                paths += 1
                if found is None:
                    continue
                if not found:
                    report.findings.append(Finding(page, span.line, "command", "`{}` in `{}` does not exist".format(word, span.text)))
                    continue
                named.extend((match, span.line) for match in found)
    report.counts["paths"] = paths
    report.counts["functions"] = functions
    return named


def check_inputs(root: Path, page: str, named: list[tuple[str, int]], report: Report) -> None:
    """The page, this check's files and every named file are inputs of the action's list, so an edit reruns it.

    A directory is only checked for existing. A path with `<name>` or `*` is one finding per extension for its first file
    that is not covered."""
    declared_file = root / "build_test_inputs.zig"
    lists = test_inputs_coverage.declared_lists(declared_file.read_text(errors="replace"))
    entries = lists.get(LIST_NAME)
    if entries is None:
        report.findings.append(Finding("build_test_inputs.zig", 0, "inputs", "declares no `{}` list".format(LIST_NAME)))
        return

    def message(path: str) -> str:
        return "`{}` is not covered by `{}` in build_test_inputs.zig, so an edit to it would not rerun this check: add it".format(path, LIST_NAME)

    for own in (page, "tests/compiler_map.py"):
        if (root / own).is_file() and not test_inputs_coverage.covered(own, entries):
            report.findings.append(Finding("build_test_inputs.zig", 0, "inputs", message(own)))
    reported: set[tuple[int, str]] = set()
    for path, line in named:
        key = (line, path.rsplit(".", 1)[-1])
        if (root / path).is_file() and not test_inputs_coverage.covered(path, entries) and key not in reported:
            reported.add(key)
            report.findings.append(Finding(page, line, "inputs", message(path)))


def check(root: Path, page: str = PAGE) -> Report:
    """Run every check of the map against the page under `root`."""
    report = Report()
    text = (root / page).read_text(errors="replace")
    spans = spans_of(mask_fences(text))
    check_size(page, text, report)
    named = check_spans(root, page, spans, report)
    check_inputs(root, page, named, report)
    report.findings.sort(key=lambda f: (f.path, f.line, f.kind, f.message))
    return report


def main(argv: list[str] | None = None) -> int:
    """Command-line entry: print each finding on its own line, or one summary line when there are none."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=str(Path(__file__).resolve().parent.parent), help="the repository root (default: this checkout)")
    parser.add_argument("--page", default=PAGE, help="the map page, relative to the root")
    args = parser.parse_args(argv)
    root = Path(args.root).resolve()
    if not (root / args.page).is_file():
        print("compiler map: {} not found under {}".format(args.page, root), file=sys.stderr)
        return 2
    report = check(root, args.page)
    if report.findings:
        for finding in report.findings:
            print(finding, file=sys.stderr)
        print("compiler map: {} finding(s); each line names the page's line to fix or the file that moved".format(len(report.findings)), file=sys.stderr)
        return 1
    print("compiler map: {} checked ({})".format(args.page, ", ".join("{} {}".format(n, what) for what, n in report.counts.items())))
    return 0


if __name__ == "__main__":
    sys.exit(main())

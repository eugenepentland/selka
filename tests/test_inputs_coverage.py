#!/usr/bin/env python3
"""Fail when a test names a repository file its cached build step does not declare.

`zig build test` caches a test step's verdict and re-runs it only when one of
its declared inputs changes (`build_test_inputs.zig`). A test that starts
reading a fixture nobody declared would keep a stale green verdict after that
fixture changes. This check reads every test source a cached Zig root compiles,
collects the repository paths it names — string literals such as
``"tests/lang/text_views.selka"`` and path joins such as
``&.{ root, "tests", "goldens" }`` — and requires each path that exists in the
repository to be covered by that root's declared entries. Paths that do not
exist are fixtures a test writes into a temporary directory and are ignored.

    python3 tests/test_inputs_coverage.py            # check, exit 1 on a gap
    python3 tests/test_inputs_coverage.py --self-test

It is a static net, not a proof: a path assembled some other way is invisible
to it, which is why `-Dtest-rerun=true` exists.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
INPUTS = ROOT / "build_test_inputs.zig"
# Cached Zig test roots and the list in build_test_inputs.zig that covers each.
ROOTS = {
    "src/memory_budget.zig": "memory_budget",
    "src/root_test.zig": "unit",
    "test/integration.zig": "cli",
    "test/golden_parity.zig": "golden",
}
TOP = ("tests", "test", "examples", "docs", "experiments", "velocity", "bench", "selfhost", "scripts", "vendor")
LITERAL = re.compile(r'"((?:%s)/[^"\s]*)"' % "|".join(TOP))
JOIN = re.compile(r'"(%s)"((?:\s*,\s*"[^"/\s{}]+")+)' % "|".join(TOP))
ROOT_FILE = re.compile(r'"(SPEC\.md|README\.md)"')
IMPORT = re.compile(r'@import\("([^"]+\.zig)"\)')
TEST_BLOCK = re.compile(r'^test "(?:[^"\\]|\\.)*" \{$', re.M)
DECL = re.compile(r'(?:pub )?const (\w+) = (?:\[_\]\[\]const u8\{(.*?)\};|"([^"]*)";)', re.S)
STRING = re.compile(r'"([^"]*)"|\b([a-z_]+)\b')
# Paths a test spells out without opening them: compared as text, matched as a
# glob, or printed in a message. (file, path) -> why it is not an input.
NOT_READ = {
    ("src/doctest_command.zig", "docs"): "glob-matching cases in a pure `globMatches` test",
    ("src/doctest_command.zig", "docs/arenas.md"): "glob-matching cases in a pure `globMatches` test",
}


def declared_lists(text: str) -> dict[str, list[str]]:
    """Every string list (and string constant) `build_test_inputs.zig` declares, resolved."""
    constants: dict[str, str] = {}
    lists: dict[str, list[str]] = {}
    for name, body, value in DECL.findall(text):
        if value:
            constants[name] = value
            continue
        entries = []
        for literal, ident in STRING.findall(body):
            if literal:
                entries.append(literal)
            elif ident in constants:
                entries.append(constants[ident])
        lists[name] = entries
    return lists


def covered(path: str, entries: list[str]) -> bool:
    """Whether one repository path falls under one of the declared entries."""
    for entry in entries:
        if entry.endswith("/"):
            if path.startswith(entry) or path + "/" == entry:
                return True
        elif "/**/*" in entry:
            base, suffix = entry.split("/**/*", 1)
            if path.startswith(base + "/") and path.endswith(suffix):
                return True
        elif "/*" in entry:
            base, suffix = entry.split("/*", 1)
            if os.path.dirname(path) == base and path.endswith(suffix):
                return True
        elif path == entry:
            return True
    return False


def reachable(root: str) -> list[str]:
    """Every Zig file a test root reaches through relative `@import`s."""
    seen: set[str] = set()
    stack = [root]
    while stack:
        path = stack.pop()
        if path in seen or not (ROOT / path).is_file():
            continue
        seen.add(path)
        text = (ROOT / path).read_text(errors="replace")
        for name in IMPORT.findall(text):
            stack.append(os.path.normpath(os.path.join(os.path.dirname(path), name)))
    return sorted(seen)


def test_text(path: str) -> str:
    """The part of a file that is test code: all of a test file, else its test blocks."""
    text = (ROOT / path).read_text(errors="replace")
    name = Path(path).name
    if name.endswith("_test.zig") or name in ("tests.zig", "integration.zig", "root_test.zig"):
        return text
    lines = text.splitlines()
    kept = []
    inside = False
    for line in lines:
        if TEST_BLOCK.match(line):
            inside = True
        if inside:
            kept.append(line)
            if line == "}":
                inside = False
        else:
            kept.append("")
    return "\n".join(kept)


def named_paths(text: str) -> list[tuple[int, str]]:
    """(line, path) for every repository path a test names, placeholders cut off."""
    found = []
    for number, line in enumerate(text.splitlines(), 1):
        for literal in LITERAL.findall(line):
            found.append((number, literal))
        for head, rest in JOIN.findall(line):
            parts = [head] + re.findall(r'"([^"]+)"', rest)
            found.append((number, "/".join(parts)))
        for literal in ROOT_FILE.findall(line):
            found.append((number, literal))
    cleaned = []
    for number, path in found:
        cut = min((path.index(c) for c in "{*#" if c in path), default=len(path))
        path = path[:cut].rstrip("/") if cut < len(path) else path.rstrip("/")
        if path:
            cleaned.append((number, path))
    return cleaned


def gaps() -> list[str]:
    """Uncovered repository paths, one message each."""
    lists = declared_lists(INPUTS.read_text())
    problems = []
    for root, list_name in ROOTS.items():
        entries = lists.get(list_name)
        if entries is None:
            problems.append("build_test_inputs.zig declares no `{}` list for {}".format(list_name, root))
            continue
        for path in reachable(root):
            for number, named in named_paths(test_text(path)):
                if not (ROOT / named).exists():
                    continue  # written into a temporary directory by the test itself
                if (path, named) in NOT_READ:
                    continue
                target = named + "/" if (ROOT / named).is_dir() else named
                if covered(target, entries) or covered(named, entries):
                    continue
                message = "{}:{}: names {} but `{}` in build_test_inputs.zig does not cover it".format(path, number, named, list_name)
                if message not in problems:
                    problems.append(message)
    return problems


def self_test() -> int:
    """Check the parser and the coverage rules on fixed text."""
    lists = declared_lists('const a = "x/*.py";\npub const one = [_][]const u8{\n    "src/",\n    "docs/r.md",\n    a,\n};\n')
    assert lists["one"] == ["src/", "docs/r.md", "x/*.py"], lists
    assert covered("src/deep/file.zig", ["src/"])
    assert covered("docs/r.md", ["docs/r.md"]) and not covered("docs/other.md", ["docs/r.md"])
    assert covered("x/y.py", ["x/*.py"]) and not covered("x/z/y.py", ["x/*.py"])
    assert covered("d/a/b.md", ["d/**/*.md"]) and not covered("d/a/b.txt", ["d/**/*.md"])
    paths = [p for _, p in named_paths('const f = "tests/native/a.selka";\nx(&.{ root, "tests", "goldens" });\ny("docs/{s}");\n')]
    assert paths == ["tests/native/a.selka", "tests/goldens", "docs"], paths
    print("inputs coverage self-test: passed")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()
    problems = gaps()
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print("declare each path in build_test_inputs.zig (or run with -Dtest-rerun=true to bypass the cache once)", file=sys.stderr)
        return 1
    print("inputs coverage: every repository path the cached test roots name is declared")
    return 0


if __name__ == "__main__":
    sys.exit(main())

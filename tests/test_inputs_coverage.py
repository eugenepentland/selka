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

The public repository is the tree without `experiments/` and `velocity/` (the
internal evidence), so nothing a gate step reads may live there. The check also
fails, with one line naming the file, on a declared input, a test source, a
script a build step runs or a corpus root that names a path under either folder
(`internal_gaps`).
"""
from __future__ import annotations

import argparse
import ast
import json
import os
from pathlib import Path
import re
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
INPUTS = ROOT / "build_test_inputs.zig"
# Cached Zig test roots and the list in build_test_inputs.zig that covers each.
ROOTS = {
    "src/text_scalar_root_test.zig": "text_scalar_unit",
    "src/tooling_root_test.zig": "tooling_unit",
    "src/memory_budget.zig": "memory_budget",
    "src/root_test.zig": "unit",
    "test/integration.zig": "cli",
    "test/golden_parity.zig": "golden",
}
# Folders the public repository does not contain: no gate step may read a file there.
INTERNAL = ("experiments", "velocity")
TOP = ("tests", "test", "examples", "docs", "experiments", "velocity", "bench", "selfhost", "scripts", "vendor")
LITERAL = re.compile(r'"((?:%s)/[^"\s]*)"' % "|".join(TOP))
JOIN = re.compile(r'"(%s)"((?:\s*,\s*"[^"/\s{}]+")+)' % "|".join(TOP))
ROOT_FILE = re.compile(r'"(SPEC\.md|README\.md)"')
IMPORT = re.compile(r'@import\("([^"]+\.zig)"\)')
TEST_BLOCK = re.compile(r'^test "(?:[^"\\]|\\.)*" \{$', re.M)
# A list is array literals and earlier lists joined by `++`, or a string constant.
LIST_TERM = r'(?:\[_\]\[\]const u8\{.*?\}|\w+)'
DECL = re.compile(r'(?:pub )?const (\w+) = (?:(' + LIST_TERM + r'(?:\s*\+\+\s*' + LIST_TERM + r')*);|"([^"]*)";)', re.S)
STRING = re.compile(r'"([^"]*)"|\b([a-z_]+)\b')
# Paths a test spells out without opening them: compared as text, matched as a
# glob, or printed in a message. (file, path) -> why it is not an input.
NOT_READ = {
    ("src/doctest_command.zig", "docs"): "glob-matching cases in a pure `globMatches` test",
    ("src/doctest_command.zig", "docs/arenas.md"): "glob-matching cases in a pure `globMatches` test",
    ("src/doctest_command.zig", "README.md"): "historical-page test writes its own temporary checkout",
    ("src/doctest_command.zig", "SPEC.md"): "historical-page test writes its own temporary checkout",
    ("src/doctest_command.zig", "docs/tooling/incremental-contract.md"): "historical-page test writes its own temporary checkout",
    ("src/doctest_command.zig", "docs/bytes.md"): "historical-page test writes its own temporary checkout",
    ("src/doctest_command.zig", "docs/named-constraints-proposal.md"): "historical-page test writes its own temporary checkout",
    ("src/doctest_command.zig", "docs/plan.md"): "historical-page test writes its own temporary checkout",
    ("src/doctest_command.zig", "docs/experiments"): "historical-page test filters only its own temporary checkout",
    ("src/doc_coverage_command.zig", "docs/experiments"): "historical-pointer test creates this directory in a temporary checkout",
    ("src/doc_coverage_command.zig", "docs/tooling"): "historical-pointer test creates this directory in a temporary checkout",
}

# Paths under an internal folder that a gate-run source spells out without reading them from the repository: written into a
# temporary checkout, compared as text, or a script a developer runs by hand that stops with one line when the folder is
# absent. (file, text) -> why it is not an input.
INTERNAL_OK = {
    ("scripts/verify_cache_test.py", "experiments/new.my"): "a file the test writes into its own temporary checkout",
    ("scripts/migrate_embedded.py", "velocity/devspeed-trials-20260923/kit/PRIMER.md"): "compared with a relative path as text, never opened",
    ("scripts/migrate_embedded.py", "velocity/suites/idioms"): "an excluded prefix compared as text, never opened",
    ("scripts/migrate_embedded.py", "velocity/devspeed-trials-20260923/results"): "an excluded prefix compared as text, never opened",
    ("scripts/audit_cache_reads.py", "experiments"): "a folder of the evidence archive beside the repository, not of the repository",
    ("scripts/ownership_applications.py", "experiments/lox-eda-parity-20261013"): "run by hand; it ends with one line when the folder is absent",
    ("scripts/ownership_applications.py", "experiments/lox-eda-improvements-20261012"): "run by hand; it ends with one line when the folder is absent",
    ("scripts/ownership_applications.py", "experiments/lox-eda-zero-rc-20261012"): "run by hand; it ends with one line when the folder is absent",
}
# Zig test roots the complete gate compiles that `ROOTS` (the cached, input-declared ones) does not list.
INTERNAL_ROOTS = ("src/core/root_test.zig", "tools/test_runner/test_runner.zig", "selfhost/component_support_test.zig")


def declared_lists(text: str) -> dict[str, list[str]]:
    """Every string list (and string constant) `build_test_inputs.zig` declares, resolved."""
    constants: dict[str, str] = {}
    lists: dict[str, list[str]] = {}
    for name, body, value in DECL.findall(text):
        if value:
            constants[name] = value
            continue
        entries = []
        for term in re.finditer(LIST_TERM, body, re.S):
            if not term.group().startswith("["):
                entries.extend(lists.get(term.group(), []))
                continue
            for literal, ident in STRING.findall(term.group()):
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


def source_gaps(root: str, entries: list[str]) -> list[str]:
    """Require every local source imported by an independent root in its recipe."""
    return ["{}: imported source {} is outside its declared recipe".format(root, path)
            for path in reachable(root) if not covered(path, entries)]


def internal_folder(path: str) -> str | None:
    """The internal folder a path runs through (`docs/experiments` is a documentation folder, not this one), or None."""
    parts = [part for part in path.split("/") if part]
    for index, part in enumerate(parts):
        if part in INTERNAL and (index == 0 or parts[index - 1] != "docs"):
            return part
    return None


def zig_strings(text: str) -> list[tuple[int, str]]:
    """(line, content) of every double-quoted Zig literal outside `//` comments and without whitespace."""
    found = []
    for number, line in enumerate(text.splitlines(), 1):
        for match in re.finditer(r'"((?:[^"\\\n]|\\.)*)"|//', line):
            if match.group().startswith("//"):
                break
            if match.group(1) and not re.search(r"\s", match.group(1)):
                found.append((number, match.group(1)))
    return found


def build_hits(text: str) -> list[tuple[int, str]]:
    """(line, path) of every `experiments/` or `velocity/` path `build.zig` names in code, in a literal or a step label."""
    hits = []
    for number, line in enumerate(text.splitlines(), 1):
        code = line
        for match in re.finditer(r'"(?:[^"\\\n]|\\.)*"|//', line):
            if match.group() == "//":
                code = line[:match.start()]
                break
        for found in re.finditer(r'(?<![\w./-])((?:%s)/[^\s"]*)' % "|".join(INTERNAL), code):
            hits.append((number, found.group(1)))
    return hits


def python_hits(source: str) -> list[tuple[int, str]]:
    """(line, text) of every string constant of a Python source that is a path into an internal folder (`experiments/a`) or
    a join onto one (`root / "velocity"`); a bare folder name in a tuple of roots and comments are not reads."""
    try:
        tree = ast.parse(source)
    except (SyntaxError, ValueError):
        return []
    inside = re.compile(r"(?:%s)/\S+" % "|".join(INTERNAL))
    hits = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str) and inside.fullmatch(node.value):
            hits.append((node.lineno, node.value))
        elif isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
            right = node.right
            if isinstance(right, ast.Constant) and right.value in INTERNAL:
                hits.append((right.lineno, right.value))
    return hits


def run_scripts(lists: dict[str, list[str]], build_text: str) -> list[str]:
    """Every Python file a build step runs or declares as an input and that exists, in build order, without repeats."""
    found = []
    named = re.findall(r'(?<![\w/.-])((?:scripts|tests|selfhost|tools|test)/[\w/.-]+\.py)', build_text)
    declared = [entry for entries in lists.values() for entry in entries if entry.endswith(".py")]
    for path in named + declared:
        if path not in found and path != "tests/test_inputs_coverage.py" and (ROOT / path).is_file():
            found.append(path)
    return found


def internal_gaps(lists: dict[str, list[str]]) -> list[str]:
    """One message for each gate-read path that runs through `experiments/` or `velocity/`, which the public tree does not hold."""
    def line(where: str, path: str) -> str:
        return "{}: names {}, and the public repository has no {}/ (move the file to test/fixtures/<area>/ or scripts/)".format(
            where, path, internal_folder(path))
    problems = []
    for name, entries in lists.items():
        problems.extend(line("build_test_inputs.zig `{}`".format(name), entry) for entry in entries if internal_folder(entry))
    build_text = (ROOT / "build.zig").read_text(errors="replace")
    problems.extend(line("build.zig:{}".format(number), path) for number, path in build_hits(build_text))
    for root in list(ROOTS) + list(INTERNAL_ROOTS):
        for path in reachable(root):
            for number, content in zig_strings(test_text(path)):
                if internal_folder(content) and (path, content) not in INTERNAL_OK:
                    problems.append(line("{}:{}".format(path, number), content))
    for path in run_scripts(lists, build_text):
        for number, content in python_hits((ROOT / path).read_text(errors="replace")):
            if (path, content) not in INTERNAL_OK:
                problems.append(line("{}:{}".format(path, number), content))
    corpus = ROOT / "selfhost" / "corpus.json"
    if corpus.is_file():
        for entry in json.loads(corpus.read_text()).get("roots", []):
            if internal_folder(entry.get("path", "")):
                problems.append(line("selfhost/corpus.json root `{}`".format(entry.get("name", "")), entry["path"]))
    exclusions = ROOT / "scripts" / "my_format_exclusions.json"
    if exclusions.is_file():
        problems.extend(line("scripts/my_format_exclusions.json", key) for key in json.loads(exclusions.read_text()) if internal_folder(key))
    return sorted(set(problems))


def gaps() -> list[str]:
    """Uncovered repository paths, one message each."""
    lists = declared_lists(INPUTS.read_text())
    problems = []
    for root, list_name in ROOTS.items():
        entries = lists.get(list_name)
        if entries is None:
            problems.append("build_test_inputs.zig declares no `{}` list for {}".format(list_name, root))
            continue
        if list_name in ("tooling_unit", "text_scalar_unit"):
            problems.extend(source_gaps(root, entries))
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
    assert internal_folder("experiments/a/b.py") == "experiments" and internal_folder("../../velocity/x.c") == "velocity"
    assert internal_folder("docs/experiments/a.md") is None and internal_folder("src/experiments_note.zig") is None
    assert [h for _, h in zig_strings('const a = "../../experiments/x.c"; // "velocity/y"\nconst b = "two words experiments/z";\n')] == ["../../experiments/x.c"]
    assert [h for _, h in build_hits('x("experiments/a/t.py", "scripts/b.py"); // velocity/c.py\ny("docs/experiments/d.md");\n')] == ["experiments/a/t.py"]
    assert sorted(h for _, h in python_hits('a = ROOT / "velocity" / "friction"\nb = "experiments/a/b.py"\nc = ("experiments", "velocity")\n# experiments/x\n')) == ["experiments/a/b.py", "velocity"]
    global ROOT
    previous = ROOT
    with tempfile.TemporaryDirectory(prefix="source-closure-") as scratch:
        ROOT = Path(scratch)
        try:
            (ROOT / "root.zig").write_text('test { _ = @import("child.zig"); }')
            (ROOT / "child.zig").write_text('const std = @import("std");')
            assert source_gaps("root.zig", ["root.zig", "child.zig"]) == []
            assert len(source_gaps("root.zig", ["root.zig"])) == 1
            (ROOT / "build.zig").write_text('const a = "experiments/x/t_test.py";\n')
            found = internal_gaps({"one": ["src/", "velocity/friction/"]})
            assert len(found) == 2 and found[0].startswith("build.zig:1: names experiments/x/t_test.py"), found
            assert found[1].startswith("build_test_inputs.zig `one`: names velocity/friction/"), found
        finally:
            ROOT = previous
    print("inputs coverage self-test: passed")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()
    problems = internal_gaps(declared_lists(INPUTS.read_text())) + gaps()
    for problem in problems:
        print(problem, file=sys.stderr)
    if any("the public repository has no" in problem for problem in problems):
        print("experiments/ and velocity/ are left out of the public repository: move what a gate step reads out of them first", file=sys.stderr)
    if any("does not cover it" in problem or "outside its declared recipe" in problem for problem in problems):
        print("declare each path in build_test_inputs.zig (or run with -Dtest-rerun=true to bypass the cache once)", file=sys.stderr)
    if problems:
        return 1
    print("inputs coverage: every repository path the cached test roots name is declared")
    return 0


if __name__ == "__main__":
    sys.exit(main())

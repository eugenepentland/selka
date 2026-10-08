#!/usr/bin/env python3
"""Run the cheapest set of tests that covers what changed. NOT the gate.

    python3 scripts/affected_tests.py              # diff against merge-base(HEAD, main) + uncommitted
    python3 scripts/affected_tests.py --base HEAD  # only uncommitted changes
    python3 scripts/affected_tests.py --dry-run    # print the selection, run nothing

This is the inner loop for work on mylang itself. It reads ``git diff`` against a
base (default: the merge-base with ``main``, plus staged, unstaged and untracked
files), maps every changed file to the tests that most directly exercise it, and
runs only those:

* ``src/<name>.zig``: the Zig tests in ``src/<name>_test.zig`` and inline in the
  file, the test files that import it directly, tests tagged with a ``spec:``
  tag the diff touches, tests whose body names a function or diagnostic code
  the diff touches, and a small guest smoke for compiler sources;
* the new core (``src/core/``, including its C runtime under
  ``src/core/runtime/``) and its fixtures (``test/core/``): ``test-core``, plus
  the guest smoke;
* ``tests/lang/*.my`` / ``tests/guest/*.my``: ``mylang test`` on that file;
* ``test/integration.zig``: the CLI tests whose bodies the diff touches;
* Markdown pages: ``mylang doctest`` on each changed page and ``doc-coverage``;
* a Python driver under ``tests/``: the build step that runs it.

A passing run means only that the selected tests pass. The full gate
(``CLAUDE.md``, "Full gate") is still required before finishing, and the
script says so on every run. Output of every command is saved under
``.mylang-cache/affected-tests/``.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import focused_test  # noqa: E402  (shares the zig/zigw choice)

LOG_DIR = ROOT / ".mylang-cache" / "affected-tests"
UNIT_ROOT = "src/root_test.zig"
CLI_ROOT = "test/integration.zig"
LANG_CACHE = ".mylang-cache/lang-tests"
# `test-lang` runs tests/lang twice: at debug, and at release with its facts
# verified and the runtime's leak check on (MYL_CORE_LEAKCHECK=1), as the gate does.
LANG_RELEASE_CACHE = ".mylang-cache/lang-tests-release"
GUEST_CACHE = ".mylang-cache/guest-tests"
GATE = (
    "zig build test --summary all",
    "zig build fmt-check",
)
# Broad guest areas one compiler edit is most likely to break. The whole suite
# is `zig build test-lang`, which the gate runs; `--guest-full` runs it here.
GUEST_SMOKE = (
    "tests/lang/python_core.my",
    "tests/lang/python_collections.my",
    "tests/lang/python_strings.my",
    "tests/lang/python_values.my",
    "tests/lang/python_variants.my",
    "tests/lang/callbacks.my",
    "tests/lang/option_methods.my",
    "tests/lang/print_rendering.my",
)
# A diagnostic code or function name that ties more tests than this to the diff
# is too common to say anything about the change; it selects nothing.
TOKEN_LIMIT = 40
# Paths owned by one build step. Checked in order; the first prefix that
# matches a changed path owns it.
HOST_STEPS = (
    ("src/core/", "test-core"),
    ("test/core/", "test-core"),
    ("test/golden_parity.zig", "test-golden"),
    ("tests/goldens/", "test-golden"),
    ("tests/idiom_probes.py", "test-idioms"),
    ("tests/fixtures/idioms/", "test-idioms"),
    ("tests/parser_hints.py", "test-agent-usefulness"),
    ("tests/test_friction_harvest.py", "test-agent-usefulness"),
    ("velocity/", "test-agent-usefulness"),
    ("tests/compiler_identity_cache.py", "test-compiler-identity"),
    ("build_identity.zig", "test-compiler-identity"),
    ("scripts/affected_tests.py", "test-affected-selection"),
    ("tests/test_affected_tests.py", "test-affected-selection"),
    ("tests/test_inputs_coverage.py", "test-inputs-coverage"),
    ("scripts/merge_spec.py", "test-spec-merge"),
    ("scripts/setup-git.sh", "test-spec-merge"),
    ("tests/test_spec_merge.py", "test-spec-merge"),
    ("build_test_inputs.zig", "test-inputs-coverage"),
    ("tests/input_manifest.py", "test-inputs-coverage"),
)
TEST_DECL = re.compile(r'^test "((?:[^"\\]|\\.)*)" \{', re.M)
SPEC_COMMENT = re.compile(r'(?://|#)\s*spec(?:-case)?:\s*([A-Z][A-Z0-9_-]*)')
SPEC_BULLET = re.compile(r'^\s*- \[([A-Z][A-Z0-9_-]*)\]')
DIAGNOSTIC = re.compile(r'\b([ER]_[A-Z][A-Z0-9_]+)\b')
ZIG_FN = re.compile(r'\bfn ([A-Za-z_][A-Za-z0-9_]*)\s*\(')
IMPORT = re.compile(r'@import\("([^"]+\.zig)"\)')
GUEST_TEST = re.compile(r'^(?:public )?def (test_[A-Za-z0-9_]*)\s*\(', re.M)


class Selection:
    """What to run and why: every entry maps a target to the reasons it was chosen."""

    def __init__(self) -> None:
        self.unit: dict[str, list[str]] = {}
        self.cli: dict[str, list[str]] = {}
        self.steps: dict[str, list[str]] = {}
        self.guest: dict[str, list[str]] = {}
        self.doctest: dict[str, list[str]] = {}
        self.doc_coverage: list[str] = []
        self.notes: list[str] = []

    def add(self, table: dict[str, list[str]], key: str, reason: str) -> None:
        reasons = table.setdefault(key, [])
        if reason not in reasons:
            reasons.append(reason)

    def empty(self) -> bool:
        return not (self.unit or self.cli or self.steps or self.guest or self.doctest or self.doc_coverage)


# ── git ──────────────────────────────────────────────────────────────────────

def git(*args: str) -> str:
    """Run git in the repository and return its standard output."""
    return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True, text=True).stdout


def resolve_base(requested: str | None) -> tuple[str, str]:
    """The commit to diff against and a description of how it was chosen."""
    if requested:
        return git("rev-parse", "--verify", requested + "^{commit}").strip(), requested
    for main in ("main", "origin/main"):
        try:
            return git("merge-base", "HEAD", main).strip(), "merge-base(HEAD, {})".format(main)
        except subprocess.CalledProcessError:
            continue
    return git("rev-parse", "HEAD").strip(), "HEAD (no main branch found)"


def changed_files(base: str) -> list[str]:
    """Tracked files that differ from ``base`` in the working tree, plus untracked files."""
    tracked = git("diff", "--name-only", "--no-renames", base).split()
    untracked = git("ls-files", "--others", "--exclude-standard").split()
    return sorted(set(tracked) | set(untracked))


def diff_lines(base: str, files: list[str]) -> dict[str, list[str]]:
    """Changed lines per file: removed and added lines, and the hunk headers' context."""
    out: dict[str, list[str]] = {path: [] for path in files}
    text = git("diff", "-U0", "--no-color", "--no-renames", base)
    current = None
    for line in text.splitlines():
        if line.startswith("+++ "):
            name = line[4:]
            current = name[2:] if name.startswith("b/") else None
        elif line.startswith("--- "):
            continue
        elif current is not None and line.startswith("@@"):
            out.setdefault(current, []).append(line.split("@@", 2)[-1])
        elif current is not None and line[:1] in "+-":
            out.setdefault(current, []).append(line[1:])
    for path in files:
        if not out.get(path) and (ROOT / path).is_file():
            try:
                out[path] = (ROOT / path).read_text(errors="replace").splitlines()
            except OSError:
                pass
    return out


# ── source facts ─────────────────────────────────────────────────────────────

def read(path: Path) -> str:
    try:
        return path.read_text(errors="replace")
    except OSError:
        return ""


def zig_tests(text: str) -> list[tuple[str, set[str], str]]:
    """Every ``test "name" {`` in a Zig file with its spec tags and body."""
    tests = []
    lines = text.splitlines()
    for index, line in enumerate(lines):
        match = TEST_DECL.match(line)
        if not match:
            continue
        tags: set[str] = set()
        above = index - 1
        while above >= 0 and lines[above].lstrip().startswith("//"):
            tags.update(SPEC_COMMENT.findall(lines[above]))
            above -= 1
        end = index + 1
        while end < len(lines) and lines[end] != "}":
            end += 1
        tests.append((match.group(1), tags, "\n".join(lines[index + 1:end])))
    return tests


def guest_tests(text: str) -> list[tuple[str, set[str]]]:
    """Every ``def test_*`` in a guest file with its ``# spec:`` tags."""
    tests = []
    lines = text.splitlines()
    for index, line in enumerate(lines):
        match = GUEST_TEST.match(line)
        if not match:
            continue
        tags: set[str] = set()
        above = index - 1
        while above >= 0 and (lines[above].lstrip().startswith("#") or lines[above].lstrip().startswith("@")):
            tags.update(SPEC_COMMENT.findall(lines[above]))
            above -= 1
        tests.append((match.group(1), tags))
    return tests


def reachable(root: str) -> set[str]:
    """Repository paths of every Zig file a test root reaches through ``@import``."""
    seen: set[str] = set()
    stack = [root]
    while stack:
        path = stack.pop()
        if path in seen:
            continue
        seen.add(path)
        base = os.path.dirname(path)
        for name in IMPORT.findall(read(ROOT / path)):
            target = os.path.normpath(os.path.join(base, name))
            if (ROOT / target).is_file():
                stack.append(target)
    return seen


class Corpus:
    """The Zig and guest tests the mapping can select from, indexed once."""

    def __init__(self) -> None:
        self.unit_files = sorted(p for p in reachable(UNIT_ROOT) if p.startswith("src/"))
        self.unit_tests = {path: zig_tests(read(ROOT / path)) for path in self.unit_files}
        self.cli_tests = zig_tests(read(ROOT / CLI_ROOT))
        self.guest_files = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "tests" / "lang").rglob("*.my"))
        self.guest_files += sorted(str(p.relative_to(ROOT)) for p in (ROOT / "tests" / "guest").rglob("*.my"))
        self.guest_tests = {path: guest_tests(read(ROOT / path)) for path in self.guest_files}
        self.importers: dict[str, set[str]] = {}
        for path in self.unit_files:
            base = os.path.dirname(path)
            for name in IMPORT.findall(read(ROOT / path)):
                self.importers.setdefault(os.path.normpath(os.path.join(base, name)), set()).add(path)


def namespace(path: str) -> str:
    """The prefix Zig gives a test declared in ``path`` under the unit root."""
    return Path(path).stem + ".test."


# ── mapping ──────────────────────────────────────────────────────────────────

def select_zig_file(sel: Selection, corpus: Corpus, path: str) -> None:
    """A changed compiler source: its own tests, its test file, direct importers' tests."""
    if path not in corpus.unit_tests:
        sel.notes.append("{}: not reached from {}; only the gate covers it".format(path, UNIT_ROOT))
        return
    before = len(sel.unit)
    if corpus.unit_tests[path]:
        sel.add(sel.unit, namespace(path), "tests declared in {}".format(path))
    stem = Path(path).stem
    if not stem.endswith("_test"):
        # A module split out of a facade (`sema_places.zig` behind `sema.zig`) is
        # tested through the facade: its test file and the test files importing it.
        owners = [path] + facade_of(corpus, path)
        for owner in owners:
            via = "" if owner == path else " (through {}, which imports {})".format(owner, path)
            companion = str(Path(owner).with_name(Path(owner).stem + "_test.zig"))
            if corpus.unit_tests.get(companion):
                sel.add(sel.unit, namespace(companion), "{} is the test file for {}{}".format(companion, owner, via))
            for importer in sorted(corpus.importers.get(owner, ())):
                if importer.endswith("_test.zig") and corpus.unit_tests.get(importer):
                    sel.add(sel.unit, namespace(importer), "{} imports {}{}".format(importer, owner, via))
        if len(sel.unit) == before:
            sel.notes.append("{}: no test file declares or imports it; only tests the diff names by spec tag, "
                             "diagnostic code or function are selected, and the gate covers the rest".format(path))
        guest_smoke(sel, "compiler source {}".format(path))


def facade_of(corpus: Corpus, path: str) -> list[str]:
    """The family module (`src/sema.zig` for `src/sema_places.zig`) when it imports `path`."""
    family = Path(path).stem.split("_")[0]
    facade = str(Path(path).with_name(family + ".zig"))
    if facade != path and facade in corpus.importers.get(path, set()):
        return [facade]
    return []


def guest_smoke(sel: Selection, reason: str) -> None:
    for entry in GUEST_SMOKE:
        if (ROOT / entry).is_file():
            sel.add(sel.guest, entry, reason + " (guest smoke)")


def select_cli(sel: Selection, corpus: Corpus, changed: list[str]) -> None:
    """``test/integration.zig``: the CLI tests whose declaration or body changed."""
    names = {name for name, _, _ in corpus.cli_tests}
    hit = False
    for line in changed:
        for name in names:
            if name and ('test "{}"'.format(name) in line or name in line and line.lstrip().startswith("test ")):
                sel.add(sel.cli, "integration.test." + name, "its test in {} changed".format(CLI_ROOT))
                hit = True
    if not hit:
        sel.notes.append("{}: changed lines lie outside any test; `python3 scripts/focused_test.py cli <name>` or the gate covers it".format(CLI_ROOT))


def select_by_tokens(sel: Selection, corpus: Corpus, lines_by_file: dict[str, list[str]]) -> None:
    """Tests tied to the diff by spec tag, diagnostic code or changed function name."""
    tags: set[str] = set()
    codes: set[str] = set()
    functions: set[str] = set()
    for path, lines in lines_by_file.items():
        for line in lines:
            tags.update(SPEC_COMMENT.findall(line))
            if path == "SPEC.md":
                tags.update(SPEC_BULLET.findall(line))
            if path.endswith(".zig") and path.startswith("src/") and not path.endswith("_test.zig"):
                codes.update(DIAGNOSTIC.findall(line))
                functions.update(name for name in ZIG_FN.findall(line) if len(name) > 5)
    zig_tests = [(namespace(path) + name, test_tags, body, sel.unit) for path, tests in corpus.unit_tests.items()
                 for name, test_tags, body in tests]
    zig_tests += [("integration.test." + name, test_tags, body, sel.cli) for name, test_tags, body in corpus.cli_tests]
    for key, test_tags, _, table in zig_tests:
        shared = sorted(tags & test_tags)
        if shared:
            sel.add(table, key, "tagged spec: {}".format(", ".join(shared)))
    for token, pattern, why in [(c, c, "asserts {}, which the diff touches") for c in sorted(codes)] + \
            [(f, f + "(", "calls {}(), which the diff touches") for f in sorted(functions)]:
        hits = [(key, table) for key, _, body, table in zig_tests if pattern in body]
        if len(hits) > TOKEN_LIMIT:
            sel.notes.append("{} appears in {} tests; too common to select by".format(token, len(hits)))
            continue
        for key, table in hits:
            sel.add(table, key, why.format(token))
    for entry, tests in corpus.guest_tests.items():
        for _, test_tags in tests:
            shared = sorted(tags & test_tags)
            if shared:
                sel.add(sel.guest, entry, "declares a test tagged spec: {}".format(", ".join(shared)))


def select(files: list[str], lines_by_file: dict[str, list[str]], corpus: Corpus, guest_full: bool = False) -> Selection:
    """Map changed files (and their changed lines) to the tests that cover them."""
    sel = Selection()
    for path in files:
        exists = (ROOT / path).exists()
        host = next((step for prefix, step in HOST_STEPS if path.startswith(prefix)), None)
        if host:
            sel.add(sel.steps, host, path)
            if host == "test-core":
                guest_smoke(sel, "new core {}".format(path))
            continue
        if path.startswith("src/") and path.endswith(".zig"):
            if exists:
                select_zig_file(sel, corpus, path)
            continue
        if path.startswith(("tests/lang/", "tests/guest/")) and path.endswith(".my"):
            if exists and path in corpus.guest_tests and corpus.guest_tests[path]:
                sel.add(sel.guest, path, "changed test file")
            elif exists:
                owners = [e for e in corpus.guest_files if Path(path).stem.split("_case_")[0] == Path(e).stem]
                for owner in owners:
                    sel.add(sel.guest, owner, "imports changed module {}".format(path))
                if not owners:
                    sel.add(sel.guest, str(Path(path).parent) if path.startswith("tests/guest/") else "tests/lang", "changed module {}".format(path))
            continue
        if path == CLI_ROOT:
            select_cli(sel, corpus, lines_by_file.get(path, []))
            continue
        if path.endswith(".md") and (path.startswith("docs/") or path in ("README.md", "SPEC.md")):
            if exists and not path.startswith("docs/legacy/"):
                sel.add(sel.doctest, path, "changed page")
            if path.startswith("docs/") or path == "src/features.json":
                sel.doc_coverage.append(path)
            continue
        if path == "src/features.json":
            sel.doc_coverage.append(path)
            continue
        if path in ("build.zig", "build.zig.zon", "guardian.toml") or path.startswith("build_"):
            sel.notes.append("{}: the build graph itself; run `zig build test-compile` and the full gate".format(path))
            continue
        if path.startswith(("test/fixtures/", "examples/")):
            referencing = [
                (f, n) for f, tests in corpus.unit_tests.items() for n, _, body in tests if path in body
            ]
            for f, n in referencing:
                sel.add(sel.unit, namespace(f) + n, "reads {}".format(path))
            for n, _, body in corpus.cli_tests:
                if path in body or os.path.dirname(path) in body:
                    sel.add(sel.cli, "integration.test." + n, "reads {}".format(path))
            continue
        sel.notes.append("{}: no mapping; the gate covers it".format(path))
    select_by_tokens(sel, corpus, lines_by_file)
    if guest_full and sel.guest:
        sel.guest = {"tests/lang": ["--guest-full"]}
    return sel


# ── running ──────────────────────────────────────────────────────────────────

class Command:
    """One command the selection runs, and what its output said."""

    def __init__(self, label: str, argv: list[str], env: dict[str, str] | None = None) -> None:
        self.label = label
        self.argv = argv
        self.env = env
        self.status: int | None = None
        self.seconds = 0.0
        self.summary = ""
        self.log: Path | None = None


def plan(sel: Selection, zig: str, shards: int = 8) -> tuple[list[Command], list[Command]]:
    """Build commands (run first, concurrently) and guest commands (run after).

    The Zig selections run through the sharded focused steps, so a filter that
    names a hundred slow tests still finishes in the time of its slowest slice.
    """
    builds: list[Command] = []
    for table, step, label in ((sel.unit, "test-units-sharded", "unit"), (sel.cli, "test-cli-sharded", "CLI")):
        if table:
            argv = [zig, "build", step, "--summary", "line", "-Dtest-shards={}".format(shards)]
            argv += ["-Dtest-filter=" + f for f in sorted(table)]
            builds.append(Command("zig {} tests ({} filter(s))".format(label, len(table)), argv))
    needs_compiler = bool(sel.guest or sel.doctest or sel.doc_coverage)
    steps = sorted(sel.steps)
    if needs_compiler:
        steps = ["affected-compiler"] + steps
    if steps:
        builds.append(Command("zig build " + " ".join(steps), [zig, "build", *steps, "--summary", "line"]))
    compiler = str(ROOT / "zig-out" / "focus" / "mylang")
    env = dict(os.environ)
    guests: list[Command] = []
    for entry in sorted(sel.guest):
        if entry.startswith("tests/guest"):
            guests.append(Command("mylang test " + entry, [compiler, "test", entry, "--cache-dir", GUEST_CACHE], env))
            continue
        guests.append(Command("mylang test " + entry, [compiler, "test", entry, "--cache-dir", LANG_CACHE], env))
        release = [compiler, "test", entry, "--release", "--verify-facts", "--cache-dir", LANG_RELEASE_CACHE]
        guests.append(Command("mylang test {} (release, leak check)".format(entry), release, dict(env, MYL_CORE_LEAKCHECK="1")))
    for page in sorted(sel.doctest):
        guests.append(Command("mylang doctest " + page, [compiler, "doctest", ".", "--filter", page], env))
    if sel.doc_coverage:
        guests.append(Command("mylang doc-coverage", [compiler, "doc-coverage", "."], env))
    return builds, guests


SELECTED = re.compile(r"(\d+) test\(s\) selected")
MATCHED = re.compile(r"(\d+) match by name")
GUEST_SUMMARY = re.compile(r"^\d+ passed, \d+ cached, \d+ failed, \d+ skipped.*$", re.M)


def execute(command: Command, stamp: str, index: int) -> Command:
    started = time.time()
    completed = subprocess.run(command.argv, cwd=ROOT, env=command.env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    command.seconds = time.time() - started
    command.status = completed.returncode
    output = completed.stdout or ""
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    command.log = LOG_DIR / "{}-{:02d}.log".format(stamp, index)
    command.log.write_text("$ " + " ".join(command.argv) + "\n" + output, encoding="utf-8")
    selected = SELECTED.findall(output)
    guest = GUEST_SUMMARY.findall(output)
    matched = MATCHED.findall(output)
    if selected:
        # Every shard reports its own slice; the name-match count is the root's.
        command.summary = "{} test(s) selected across {} process(es)".format(sum(int(n) for n in selected), len(selected))
        if matched:
            command.summary += ", {} named by the filters".format(matched[0])
    elif guest:
        command.summary = guest[-1]
    elif "cached" in output and command.status == 0 and "zig build" in command.label:
        command.summary = "up to date"
    return command


def describe(sel: Selection) -> list[str]:
    lines = []
    for title, table in (("zig unit filter", sel.unit), ("zig CLI filter", sel.cli), ("build step", sel.steps),
                         ("guest tests", sel.guest), ("doctest page", sel.doctest)):
        for key in sorted(table):
            lines.append("  {:<16} {}".format(title, key))
            for reason in table[key][:3]:
                lines.append("  {:<16}   <- {}".format("", reason))
            if len(table[key]) > 3:
                lines.append("  {:<16}   <- ... and {} more".format("", len(table[key]) - 3))
    if sel.doc_coverage:
        lines.append("  {:<16} {}".format("doc-coverage", ", ".join(sorted(set(sel.doc_coverage)))))
    for note in sel.notes:
        lines.append("  note: " + note)
    return lines


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base", help="commit to diff against (default: merge-base of HEAD and main)")
    parser.add_argument("--dry-run", action="store_true", help="print the selection and run nothing")
    parser.add_argument("--serial", action="store_true", help="run the zig build commands one at a time")
    parser.add_argument("--guest-full", action="store_true", help="run all of tests/lang instead of the selected guest files")
    parser.add_argument("--shards", type=int, default=8, help="processes each selected Zig root is split into (default 8)")
    parser.add_argument("--zig", default=None, help="zig driver to invoke (default: $ZIG, else as scripts/focused_test.py)")
    args = parser.parse_args(argv)

    base, how = resolve_base(args.base)
    files = changed_files(base)
    print("affected tests: the inner loop, NOT the gate")
    print("base: {} ({}) plus uncommitted and untracked files; {} changed file(s)".format(base[:12], how, len(files)))
    if not files:
        print("nothing changed; nothing to run")
        return 0
    corpus = Corpus()
    sel = select(files, diff_lines(base, files), corpus, args.guest_full)
    print("selected:")
    for line in describe(sel):
        print(line)
    if sel.empty():
        print("no tests map to these changes")
    if args.dry_run or sel.empty():
        print_gate_reminder()
        return 0

    zig = args.zig or os.environ.get("ZIG") or focused_test.zig_program()
    builds, guests = plan(sel, zig, max(1, args.shards))
    stamp = time.strftime("%Y%m%d-%H%M%S")
    started = time.time()
    print("running:")
    # The build commands share one Zig cache, which serialises identical work
    # between them; the guest commands need the compiler the builds installed.
    workers = 1 if args.serial else max(1, len(builds))
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        done = list(pool.map(lambda pair: execute(pair[1], stamp, pair[0]), enumerate(builds)))
    report(done)
    compiler_ok = all(c.status == 0 for c in done if "affected-compiler" in c.argv)
    skipped = 0
    if guests and not compiler_ok:
        skipped = len(guests)
        print("  skipped {} guest command(s): the compiler did not build".format(skipped))
        guests = []
    ran = done + [execute(c, stamp, len(done) + i) for i, c in enumerate(guests)]
    report(ran[len(done):])
    failed = [c for c in ran if c.status != 0]
    verdict = "PASS" if not failed and not skipped else "FAIL"
    print("result: {} - {} command(s) in {:.1f}s; full output in {}/{}-*.log".format(
        verdict, len(ran), time.time() - started, LOG_DIR.relative_to(ROOT), stamp))
    for command in failed:
        print("--- {} failed; last lines of {} ---".format(command.label, command.log.relative_to(ROOT) if command.log else "?"))
        tail = command.log.read_text(errors="replace").splitlines()[-40:] if command.log else []
        for line in tail:
            print(line)
    print_gate_reminder()
    return 0 if verdict == "PASS" else 1


def report(commands: list[Command]) -> None:
    for command in commands:
        status = "PASS" if command.status == 0 else "FAIL"
        extra = " - " + command.summary if command.summary else ""
        print("  [{} {:6.1f}s] {}{}".format(status, command.seconds, command.label, extra))


def print_gate_reminder() -> None:
    print("This selection is NOT the gate. Before finishing, run the full gate:")
    for line in GATE:
        print("  " + line)


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""handback.py (run through handback.sh): the hand-back checks of a lane, one command (docs/tooling/lane-kit.md).

It works out the files changed since BASE (the merge base with main, or the commit you name; the working tree counts,
committed or not, untracked files too) and runs the checks of BRIEF-REPAIR-COMMON that apply to them, one line each:
`PASS name (Ns)`, `FAIL name (Ns): why`, `SKIP name: why it does not apply`, `LATER name: why it did not run`. Then at most
ten lines of detail per failure, then `handback: N passed, M failed, K skipped, L later; exit E; log PATH`. Exit 0 when every
check that applies passed, 1 when one failed, 2 on a host problem (no compiler, no Zig, no such base), 3 when nothing failed
but something is still to run. It never builds, never runs the gate, the edit check or a test root.

Compiler processes: at most three at once; the checks that need none run beside them. The whole run stays inside one
command's 280 seconds: a check whose estimate does not fit in what is left is not started but listed LATER with the command
for it (`--only NAME --bg` for the slow ones, then `--wait`).
"""
from __future__ import annotations

import argparse
import ast
import concurrent.futures
import dataclasses
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Callable

LANE_DIR = Path(__file__).resolve().parent
KIT_ROOT = Path(os.environ.get("KIT_ROOT", str(Path.home() / "ai/.home-cache/aw/kit")))
HOME = Path(os.environ.get("HANDBACK_HOME", str(KIT_ROOT / "handback-logs")))
BUDGET = 270  # seconds of checks started in one run; the lane card allows one command 280
GRACE = int(os.environ.get("HANDBACK_GRACE", "8"))  # seconds past the budget a running check gets before it is ended
SLOTS = 3  # compiler processes at once
DETAIL = 10  # lines of detail for one failure
WIDTH = 170  # a printed line is cut here
PASS, FAIL, SKIP, LATER = "PASS", "FAIL", "SKIP", "LATER"
LIVE_ROOTS = ("bench", "benchmarks", "docs", "examples", "selfhost", "src", "test", "tests")  # check_my_format
LANG_INPUTS = ("src/", "selfhost/", "bench/", "benchmarks/", "examples/")  # what check_noalloc and check_programs read
DOC_INPUTS = ("docs/", "src/", "selfhost/")  # what doc-coverage reads, with README.md and SPEC.md
ORDER = ("zig-fmt", "precommit", "cheap-checks", "my-fmt", "my-lint", "union-tags", "noalloc", "programs", "doc-coverage",
         "doctest", "producers", "shard-plans", "incremental-diff", "newly-refused")
PROBLEM = re.compile(r"error|fail|mismatch|refused|expected|not formatted|cannot|differ|blocking|unformatted", re.I)


@dataclasses.dataclass
class Result:
    """What one check found: PASS, FAIL, SKIP or LATER, the words after its name, the detail lines of a failure."""
    status: str
    text: str = ""
    detail: list = dataclasses.field(default_factory=list)
    seconds: float = 0.0


@dataclasses.dataclass
class Entry:
    """One line of the plan: a check that applies (`run` is set) or a skip (`why` says why not)."""
    name: str
    why: str
    run: Callable | None = None
    est: int = 10
    weight: int = 1


@dataclasses.dataclass
class Ctx:
    """What every check reads: the tree, the base, the changed files, the tools and where the logs go."""
    root: Path
    base: str
    changes: list
    compiler: Path
    zig: str
    logdir: Path
    only: set
    forced: set
    bg: bool = False
    stores: Path = dataclasses.field(default_factory=lambda: KIT_ROOT / "stores" / "handback")


# ---------------------------------------------------------------- git

def git(root, *args, check=True):
    out = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, errors="replace")
    if check and out.returncode != 0:
        raise SystemExit("handback: git %s: %s" % (" ".join(args[:2]), (out.stderr.strip().splitlines() or ["failed"])[0]))
    return out.stdout


def merge_base(root):
    for main in ("main", "origin/main"):
        out = subprocess.run(["git", "-C", str(root), "merge-base", "HEAD", main], capture_output=True, text=True)
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip()
    raise SystemExit("handback: no merge base with main; name the base: scripts/lane/handback.sh COMMIT")


def changed_files(root, base):
    """[(status, path)] since BASE: A (added or untracked), M, D; renames count as a delete and an add."""
    git(root, "rev-parse", "--verify", base + "^{commit}")
    rows = {}
    for line in git(root, "diff", "--name-status", "--no-renames", base).splitlines():
        status, _, path = line.partition("\t")
        rows[path] = status[:1]
    for path in git(root, "ls-files", "-o", "--exclude-standard").splitlines():
        rows.setdefault(path, "A")
    return sorted((s, p) for p, s in rows.items())


def added_test_blocks(ctx):
    """The Zig `test` declarations the change adds (lines at column 0 of added lines, and of untracked files)."""
    found = []
    diff = git(ctx.root, "diff", "-U0", "--no-renames", ctx.base, "--", "*.zig")
    found += [l[1:].strip() for l in diff.splitlines() if re.match(r"^\+test\b", l)]
    for status, path in ctx.changes:
        if status == "A" and path.endswith(".zig") and not git(ctx.root, "ls-files", "--", path).strip():
            text = (ctx.root / path).read_text(errors="replace") if (ctx.root / path).is_file() else ""
            found += [l.strip() for l in text.splitlines() if re.match(r"^test\b", l)]
    return found


# ---------------------------------------------------------------- selection helpers

def present(ctx, *, status="AM", suffix=None, under=None, pred=None):
    """Paths of changed files that exist: by status letters, suffix, folder prefixes and a predicate."""
    out = []
    for s, p in ctx.changes:
        if s not in status or not (ctx.root / p).is_file():
            continue
        if suffix and not p.endswith(suffix):
            continue
        if under and not p.startswith(under):
            continue
        if pred and not pred(p):
            continue
        out.append(p)
    return out


def any_changed(ctx, prefixes=(), names=(), suffixes=()):
    """True when a changed path (deleted ones too) starts with a prefix, is a name or ends with a suffix."""
    return any(p.startswith(tuple(prefixes)) or p in names or p.endswith(tuple(suffixes)) for _, p in ctx.changes)


def closures_of(root, which):
    """CLOSURES[which] of scripts/verification_producers.py, read without importing it (a tuple of paths)."""
    path = root / "scripts" / "verification_producers.py"
    if not path.is_file():
        return ()
    for node in ast.parse(path.read_text()).body:
        if isinstance(node, ast.Assign) and any(getattr(t, "id", "") == "CLOSURES" for t in node.targets):
            try:
                return tuple(ast.literal_eval(node.value).get(which, ()))
            except (ValueError, SyntaxError):
                return ()
    return ()


def zig_imports(root, start):
    """Every .zig file `start` reaches by `@import("x.zig")`, itself included, as paths from the root."""
    seen, stack = [], [start]
    while stack:
        rel = stack.pop()
        if rel in seen or not (root / rel).is_file():
            continue
        seen.append(rel)
        for name in re.findall(r'@import\("([^"]+\.zig)"\)', (root / rel).read_text(errors="replace")):
            stack.append(os.path.normpath(os.path.join(os.path.dirname(rel), name)))
    return seen


def is_test_file(path):
    base = os.path.basename(path)
    return base.endswith(("_test.zig", "_tests.zig")) or base.startswith("test_")


def decides_verdict(ctx, path):
    """Compiler source whose change can alter what `selka check` accepts or prints: Zig under src/ that is no test file, no C
    runtime and no pure tooling unit (the closure of src/tooling_root_test.zig), and the Selka sources of the standard library
    and of the self-hosted components. This is the rule `newly-refused` and `incremental-diff` are selected by."""
    if path.endswith(".selka"):
        return path.startswith(("src/stdlib/", "selfhost/components/"))
    if not (path.startswith("src/") and path.endswith(".zig")) or is_test_file(path) or path.startswith("src/core/runtime/"):
        return False
    return path not in set(closures_of(ctx.root, "tooling-units"))


def live_my(root, path):
    """Whether check_my_format would format-check this .selka file: under a live root and not in the exclusion manifest."""
    if path.split("/", 1)[0] not in LIVE_ROOTS:
        return False, "%s is under no live root (experiments/ and the like are historical)" % path
    manifest = root / "scripts" / "my_format_exclusions.json"
    entries = json.loads(manifest.read_text()) if manifest.is_file() else {}
    for prefix, reason in entries.items():
        if path == prefix or (prefix.endswith("/") and path.startswith(prefix)):
            return False, "%s is excluded from the formatter: %s" % (path, reason)
    return True, ""


# ---------------------------------------------------------------- running a command

def selected(only, name):
    """Whether `--only` (empty: everything) names this check, or the family of a `doctest:PAGE` name."""
    return not only or name in only or name.split(":")[0] in only


def last_line(output, width=90):
    lines = [l for l in output.splitlines() if l.strip()]
    return cut(lines[-1], width) if lines else ""


def cut(text, width=WIDTH):
    text = text.replace("\t", " ").rstrip()
    return text if len(text) <= width else text[: width - 3] + "..."


def tool_env(ctx, stores=False):
    """The environment of a compiler command: the compiler's own component directory (never the watcher's), and with
    `stores` the three cache variables under the kit's own folder (a command that builds guest programs)."""
    env = dict(os.environ)
    comps = ctx.compiler.parent.parent / "libexec" / "selka" / "components"
    if comps.is_dir():
        env["SELKA_COMPONENT_DIR"] = str(comps)
    else:
        env.pop("SELKA_COMPONENT_DIR", None)
    if stores:
        for var in ("SELKA_COMPILER_SHARED_CACHE", "SELKA_TEST_SHARED_CACHE"):
            env.pop(var, None)
        env.update(XDG_CACHE_HOME=str(ctx.stores / "xdg"), SELKA_CORE_RUNTIME_CACHE=str(ctx.stores / "rt"),
                   SELKA_STAGE_SHARED_CACHE=str(ctx.stores / "stage"))
        for sub in ("xdg", "rt", "stage"):
            (ctx.stores / sub).mkdir(parents=True, exist_ok=True)
    return env


def run_cmd(ctx, name, argv, *, cwd=None, env=None, deadline=None):
    """Run one command; (exit status or None when ended at the deadline, its output). Output and status go to NAME.log."""
    argv = [str(a) for a in argv]
    started = time.time()
    with open(ctx.logdir / (name.replace("/", "_").replace(":", "_") + ".log"), "a") as log:
        log.write("$ %s\n" % " ".join(argv))
        try:
            proc = subprocess.Popen(argv, cwd=cwd or ctx.root, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True, errors="replace", start_new_session=True)
        except OSError as error:
            log.write("could not start: %s\n" % error)
            return 127, "could not start %s: %s" % (argv[0], error)
        timeout = None if deadline is None else max(1.0, deadline - started)
        try:
            out, _ = proc.communicate(timeout=timeout)
            rc = proc.returncode
        except subprocess.TimeoutExpired:
            for sig in (signal.SIGTERM, signal.SIGKILL):
                try:
                    os.killpg(proc.pid, sig)
                except (ProcessLookupError, PermissionError):
                    break
                try:
                    out, _ = proc.communicate(timeout=3)
                    break
                except subprocess.TimeoutExpired:
                    out = ""
            rc = None
        log.write(out or "")
        log.write("\nexit %s after %.1f s\n" % ("none (ended at the deadline)" if rc is None else rc, time.time() - started))
    return rc, out or ""


DIAGNOSTIC = re.compile(r"^(?P<file>[^\s:]+):(?P<line>\d+)(?::\d+)?: (?:error|warning)\[(?P<code>\w+)\]: (?P<msg>.*)$")


def tidy(ctx, line, swaps=()):
    """A command's line made short at the front, so that the cut at WIDTH can only take its tail: the tree's and the log folder's
    absolute prefixes are dropped, a path SWAPS names (the stand-in copy is the file it copies, a bare file name the path that
    was checked), and a compiler diagnostic `file:line:col: error[CODE]: message` leads with its code: `CODE file:line: message`."""
    for prefix in (str(ctx.root) + "/", str(ctx.logdir) + "/"):
        line = line.replace(prefix, "")
    for old, new in swaps:
        if line.startswith(old):
            line = new + line[len(old):]
    m = DIAGNOSTIC.match(line)
    return "%s %s:%s: %s" % (m.group("code"), m.group("file"), m.group("line"), m.group("msg")) if m else line


def problem_lines(ctx, output, pick=None, swaps=()):
    """The lines worth showing for a failed command: from the first that names a problem (or the first line), at most DETAIL,
    each `tidy` and cut."""
    lines = [l for l in output.splitlines() if l.strip()]
    if not lines:
        return []
    start = 0
    if pick is None:
        start = next((i for i, l in enumerate(lines) if PROBLEM.search(l)), 0)
    return [cut(tidy(ctx, l, swaps)) for l in lines[start:start + DETAIL]]


def fail_of(ctx, rc, output, pick=None, prefix=""):
    """A FAIL result from a command that exited non-zero: the first problem line as text, a few more as detail."""
    lines = problem_lines(ctx, output, pick)
    if not lines:
        return Result(FAIL, "%sexit %s with no output" % (prefix, rc))
    return Result(FAIL, prefix + lines[0], lines[1:])


def later_of(name, seconds):
    return Result(LATER, "did not finish in %d s and was ended; run: scripts/lane/handback.sh --only %s --bg" % (seconds, name))


def simple(ctx, name, argv, *, cwd=None, env=None, deadline=None, ok=None, pick=None):
    """A check that is one command: exit 0 is the pass, anything else a failure; the output chooses only what to print."""
    t0 = time.time()
    rc, out = run_cmd(ctx, name, argv, cwd=cwd, env=env, deadline=deadline)
    spent = time.time() - t0
    if rc is None:
        return later_of(name, int(spent))
    if rc != 0:
        return fail_of(ctx, rc, out, pick)
    return Result(PASS, ok(out) if ok else "")


# ---------------------------------------------------------------- the checks

def check_zig_fmt(ctx, files):
    def run(deadline):
        if not files:
            return Result(SKIP, "no changed Zig file")
        rc, out = run_cmd(ctx, "zig-fmt", [ctx.zig, "fmt", "--check", *files], deadline=deadline)
        if rc is None:
            return later_of("zig-fmt", 60)
        if rc != 0:
            names = [l for l in out.splitlines() if l.strip()]
            return Result(FAIL, "needs `zig fmt`: " + ", ".join(names[:3]) if names else "exit %d" % rc, names[3:3 + DETAIL])
        return Result(PASS, "%d file(s)" % len(files))
    return run


def check_precommit(ctx):
    def run(deadline):
        rc, out = run_cmd(ctx, "precommit", [ctx.root / "scripts" / "precommit.sh"], deadline=deadline)
        if rc is None:
            return later_of("precommit", 60)
        if rc != 0:
            lines = [l for l in out.splitlines() if l.strip() and "report-only" not in l]
            return Result(FAIL, cut(lines[0]) if lines else "exit %d" % rc, [cut(l) for l in lines[1:1 + DETAIL]])
        return Result(PASS)
    return run


def check_cheap(ctx):
    def run(deadline):
        argv = [sys.executable, ctx.root / "scripts" / "gate_cheap_checks.py", "--compiler", ctx.compiler, "--zig", ctx.zig]
        return simple(ctx, "cheap-checks", argv, env=tool_env(ctx), deadline=deadline, ok=last_line)
    return run


def per_file(ctx, name, files, argv_of, deadline, stores=False, ok_note=""):
    """One compiler command for each file, in turn; the first failing files are named, the rest counted."""
    bad, t0 = [], time.time()
    if not files:
        return Result(SKIP, "no changed .selka file under a live root")
    for path in files:
        rc, out = run_cmd(ctx, name, argv_of(path), env=tool_env(ctx, stores), deadline=deadline)
        if rc is None:
            return later_of(name, int(time.time() - t0))
        if rc != 0:
            bad.append((path, problem_lines(ctx, out, swaps=[(os.path.basename(path) + ":", path + ":")])))
    if not bad:
        return Result(PASS, "%d file(s)%s" % (len(files), ok_note))
    first = bad[0][1][0] if bad[0][1] else "exit non-zero"
    detail = [cut("%s [%s]" % ((ls or ["no output"])[0], p)) for p, ls in bad[1:DETAIL]]
    return Result(FAIL, "%d of %d file(s): %s" % (len(bad), len(files), cut(first)), detail)


def check_my_fmt(ctx, files):
    def run(deadline):
        return per_file(ctx, "my-fmt", files, lambda p: [ctx.compiler, "fmt", p, "--check"], deadline)
    return run


def check_my_lint(ctx, files):
    def run(deadline):
        return per_file(ctx, "my-lint", files, lambda p: [ctx.compiler, "lint", p, "--gate"], deadline)
    return run


TEST_FUNC = re.compile(r"^public func (test_\w+)\(([^)]*)\)\s*->\s*bool(?:\s+fails\s+(\w+))?\s*:", re.M)
HAS_MAIN = re.compile(r"^(?:public )?func main\b", re.M)
LOCAL_IMPORT = re.compile(r"^import (\w+)", re.M)


def stand_in(ctx, path, work):
    """What `selka build --stats` is run on for a guest test file: the file itself when it has a `main`, else a copy in WORK
    (with the sibling modules it imports) whose `main` calls every test that takes no parameter, so that the code of the tests
    is lowered and counted (an empty `main` would lower nothing and count 0 whatever the tests hold).
    Returns (file to build, tests called, tests not called, or a reason string when there is nothing to build)."""
    source = ctx.root / path
    text = source.read_text(errors="replace")
    tests = TEST_FUNC.findall(text)
    if HAS_MAIN.search(text):
        return source, len(tests), 0, ""
    fails = {t[2] for t in tests if t[1].strip() == "" and t[2]}
    kind = sorted(fails)[0] if fails else ""
    calls = [t for t in tests if t[1].strip() == "" and (t[2] == kind or not t[2])]
    work.mkdir(parents=True, exist_ok=True)
    todo, copied = [source], set()
    while todo:
        here = todo.pop()
        if here in copied:
            continue
        copied.add(here)
        shutil.copy(here, work / here.name)
        for name in LOCAL_IMPORT.findall(here.read_text(errors="replace")):
            if (here.parent / (name + ".selka")).is_file():
                todo.append(here.parent / (name + ".selka"))
    if not calls:
        return None, 0, len(tests), "no test function without a parameter to call"
    body = "".join("    _ = %s%s()\n" % ("try " if kind and t[2] else "", t[0]) for t in calls)
    head = "\n\nfunc main() -> int%s:\n" % (" fails " + kind if kind else "")
    with open(work / source.name, "a") as out:
        out.write(head + body + "    return 0\n")
    return work / source.name, len(calls), len(tests) - len(calls), ""


UNION_TAGS = re.compile(r"union-tags: (\d+) payload reads not justified")


def check_union_tags(ctx, files):
    def run(deadline):
        bad, notes, built, t0 = [], [], 0, time.time()
        if not files:
            return Result(SKIP, "no new guest test file")
        for n, path in enumerate(files):
            target, called, left, reason = stand_in(ctx, path, ctx.logdir / "standin" / str(n))
            if target is None:
                notes.append("%s: %s" % (path, reason))
                continue
            built += 1
            out_bin = ctx.logdir / ("union-tags-%d.bin" % n)
            rc, out = run_cmd(ctx, "union-tags", [ctx.compiler, "build", target, "--stats", "-o", out_bin], cwd=target.parent,
                              env=tool_env(ctx, True), deadline=deadline)
            if rc is None:
                return later_of("union-tags", int(time.time() - t0))
            found = UNION_TAGS.search(out)
            if rc != 0:  # the diagnostic leads, with the file of the tree in place of the stand-in copy
                swaps = [(os.path.relpath(target, ctx.logdir), path)]
                why = problem_lines(ctx, out, swaps=swaps)[:1] or ["exit %s with no output" % rc]
                bad.append("%s [the build of %s was refused]" % (why[0], path))
            elif not found:
                bad.append("%s: build printed no count (no `union-tags:` line in the --stats output)" % path)
            elif int(found.group(1)) != 0:
                bad.append("%s: union-tags: %s payload reads not justified (bind the element to a local first)" % (path, found.group(1)))
            if left:
                notes.append("%s: %d of %d tests take parameters and are not called" % (path, left, called + left))
        if bad:
            return Result(FAIL, cut(bad[0]), [cut(b) for b in bad[1:1 + DETAIL]])
        if not built:  # nothing was built: a count of 0 would be a claim about nothing
            return Result(SKIP, "; ".join(notes))
        return Result(PASS, "%d file(s), 0 payload reads not justified%s" % (built, ("; " + "; ".join(notes)) if notes else ""))
    return run


def script_check(ctx, name, script, extra=()):
    def run(deadline):
        argv = [sys.executable, ctx.root / "scripts" / script, "--compiler", ctx.compiler, *extra]
        return simple(ctx, name, argv, env=tool_env(ctx), deadline=deadline, ok=last_line)
    return run


def check_doc_coverage(ctx):
    def run(deadline):
        return simple(ctx, "doc-coverage", [ctx.compiler, "doc-coverage", "."], env=tool_env(ctx), deadline=deadline,
                      ok=lambda o: last_line(o, 90))
    return run


def check_doctest(ctx, page):
    name = "doctest:" + page

    def run(deadline):
        argv = [ctx.compiler, "doctest", ".", "--filter", page, "--jobs", "1"]
        rc, out = run_cmd(ctx, name, argv, env=tool_env(ctx, True), deadline=deadline)
        if rc is None:
            return later_of(name, 60)
        summary = [l.strip() for l in out.splitlines() if "files scanned" in l]
        if rc == 0:
            return Result(PASS, cut(summary[-1].replace("Doc examples: ", ""), 100) if summary else "")
        if "0 files scanned" in out:
            return Result(SKIP, "doctest scans no such page (historical or outside README.md, SPEC.md, docs/)")
        if "no executable blocks found" in out and re.search(r"[1-9]\d* files scanned", out) and " 0 failed" in out:
            return Result(SKIP, "the page has no selka example to run")
        return fail_of(ctx, rc, out)
    return run


def check_unittest(ctx, name, module, extra=None):
    """`cd scripts && python3 -m unittest MODULE`, and for `producers` first the closure's names (extra returns lines)."""
    def run(deadline):
        problems = extra() if extra else []
        rc, out = run_cmd(ctx, name, [sys.executable, "-m", "unittest", module], cwd=ctx.root / "scripts", deadline=deadline)
        if rc is None:
            return later_of(name, 60)
        if problems:
            return Result(FAIL, cut(problems[0]), [cut(p) for p in problems[1:1 + DETAIL]])
        if rc != 0:
            return fail_of(ctx, rc, out)
        tail = [l for l in out.splitlines() if l.startswith("Ran ")]
        return Result(PASS, tail[0] if tail else "")
    return run


def closure_problems(ctx):
    """Files reached from src/tooling_root_test.zig that CLOSURES['tooling-units'] does not name (the gate fails on one)."""
    named = set(closures_of(ctx.root, "tooling-units"))
    reached = [p for p in zig_imports(ctx.root, "src/tooling_root_test.zig")]
    return ["%s is reached from src/tooling_root_test.zig but not named in CLOSURES['tooling-units'] of "
            "scripts/verification_producers.py (and the count in verification_producers_test.py)" % p
            for p in reached if p not in named]


def check_incremental(ctx):
    def run(deadline):
        argv = [sys.executable, ctx.root / "tests" / "incremental_diff.py", "--steps", "120", ctx.compiler]
        return simple(ctx, "incremental-diff", argv, env=tool_env(ctx, True), deadline=deadline,
                      ok=lambda o: last_line(o, 110))
    return run


REFUSED_LINE = re.compile(r"^(\S+): newly refused (\d+), no longer refused (\d+)", re.M)


def refused_summary(output):
    """`newly-refused.sh` prints one line a project; the one line for the answer: how many projects, the sums."""
    rows = REFUSED_LINE.findall(output)
    if not rows:
        return "no project line in its output"
    return "%d projects, newly refused %d, no longer refused %d" % (len(rows), sum(int(r[1]) for r in rows), sum(int(r[2]) for r in rows))


def check_refused(ctx):
    def run(deadline):
        t0 = time.time()
        rc, out = run_cmd(ctx, "newly-refused", [LANE_DIR / "newly-refused.sh", ctx.compiler], deadline=deadline)
        if rc is None:
            return later_of("newly-refused", int(time.time() - t0))
        if rc != 0:
            new = [l for l in out.splitlines() if l.startswith("NEW ") or "newly refused" in l]
            return fail_of(ctx, rc, "\n".join(new) + "\n" + out if new else out)
        return Result(PASS, refused_summary(out))
    return run


# ---------------------------------------------------------------- the plan

def build_plan(ctx):
    """[Entry] in the order the checks run: each applies or is skipped with the reason; --with forces, --only selects."""
    plan, forced = [], ctx.forced

    def add(name, applies, why, run=None, est=10, weight=1):
        on = (applies or name in forced or name.split(":")[0] in forced) and run is not None
        if on and not applies:
            why = "forced (--with or --only); it would not apply: " + why
        plan.append(Entry(name, why, run if on else None, est, weight))

    zigs = present(ctx, suffix=".zig")
    add("zig-fmt", bool(zigs), "%d changed Zig file(s)" % len(zigs) if zigs else "no Zig file changed", check_zig_fmt(ctx, zigs), 5, 0)
    add("precommit", True, "always (scripts/precommit.sh; Guardian is off since GH-2, so it passes)", check_precommit(ctx), 8, 0)
    add("cheap-checks", True, "always (the gate's cheap phase)", check_cheap(ctx), 15, SLOTS)
    mine = [p for p in present(ctx, suffix=".selka") if live_my(ctx.root, p)[0]]
    skipped = [live_my(ctx.root, p)[1] for p in present(ctx, suffix=".selka") if not live_my(ctx.root, p)[0]]
    note = " (%s)" % skipped[0] if skipped and not mine else ""
    add("my-fmt", bool(mine), "%d changed .selka file(s)" % len(mine) if mine else "no live .selka file changed" + note,
        check_my_fmt(ctx, mine), 2 + len(mine), 1)
    add("my-lint", bool(mine), "%d changed .selka file(s)" % len(mine) if mine else "no live .selka file changed" + note,
        check_my_lint(ctx, mine), 2 + 2 * len(mine), 1)
    tests = [p for p in present(ctx, status="A", suffix=".selka") if re.search(r"^public func test_", (ctx.root / p).read_text(errors="replace"), re.M)]
    add("union-tags", bool(tests), "%d new guest test file(s)" % len(tests) if tests else "no new guest test file",
        check_union_tags(ctx, tests), 20 * len(tests), 1)
    lang = any_changed(ctx, LANG_INPUTS, ("build.zig",), (".selka",))
    why = "a .selka file or src/, selfhost/, bench*/, examples/ changed" if lang else "no .selka file and nothing under src/, selfhost/, bench*/, examples/ changed"
    add("noalloc", lang, why, script_check(ctx, "noalloc", "check_noalloc.py"), 12, 1)
    add("programs", lang, why, script_check(ctx, "programs", "check_programs.py"), 30, 1)
    docs = any_changed(ctx, DOC_INPUTS, ("README.md", "SPEC.md"))
    add("doc-coverage", docs, "docs/, src/ or selfhost/ changed" if docs else "nothing under docs/, src/, selfhost/ changed",
        check_doc_coverage(ctx), 3, 1)
    pages = present(ctx, suffix=".md", pred=lambda p: p in ("README.md", "SPEC.md") or p.startswith("docs/"))
    pages += [n[8:] for n in sorted(forced) if n.startswith("doctest:") and n[8:] not in pages and (ctx.root / n[8:]).is_file()]
    if pages:
        for page in pages:
            add("doctest:" + page, True, "page changed", check_doctest(ctx, page), 40, 1)
    else:
        add("doctest", False, "no guide page (README.md, SPEC.md, docs/**/*.md) changed", None)
    tooling = [p for p in present(ctx, status="A", suffix=".zig", under="src/") if p in zig_imports(ctx.root, "src/tooling_root_test.zig")]
    prod = bool(tooling) or any_changed(ctx, (), ("src/tooling_root_test.zig", "scripts/verification_producers.py", "scripts/verification_producers_test.py"))
    add("producers", prod, ("Zig file added to the tooling root: " + ", ".join(tooling)) if tooling else
        ("the tooling root or its closure list changed" if prod else "no Zig file added under the tooling root"),
        check_unittest(ctx, "producers", "verification_producers_test", lambda: closure_problems(ctx)), 8, 0)
    blocks = added_test_blocks(ctx)
    shard = bool(blocks) or any_changed(ctx, ("tests/shard-plans/",), ("scripts/verification_shard_plan.py", "scripts/verification_shard_plan_test.py"))
    add("shard-plans", shard, "%d Zig test block(s) added" % len(blocks) if blocks else ("a shard plan changed" if shard else "no Zig test added"),
        check_unittest(ctx, "shard-plans", "verification_shard_plan_test"), 5, 0)
    verdict = [p for _, p in ctx.changes if decides_verdict(ctx, p)]
    reason = "compiler source that decides a verdict changed: " + ", ".join(verdict[:3]) if verdict else \
        "no compiler source that decides a verdict changed (non-test Zig under src/, src/stdlib/*.selka)"
    add("incremental-diff", bool(verdict), reason, check_incremental(ctx), 40, 1)
    add("newly-refused", bool(verdict), reason, check_refused(ctx), 420, SLOTS)
    return plan


# ---------------------------------------------------------------- running the plan

class Slots:
    """A counter of compiler processes: a check takes its weight before it starts and gives it back when it ends."""

    def __init__(self, n):
        self.free, self.cv = n, threading.Condition()

    def take(self, weight):
        with self.cv:
            while self.free < weight:
                self.cv.wait()
            self.free -= weight

    def give(self, weight):
        with self.cv:
            self.free += weight
            self.cv.notify_all()


def execute(ctx, plan, budget):
    """Run what applies, at most SLOTS compiler processes at once, starting nothing that will not fit in the budget."""
    t_start = time.time()
    deadline = t_start + budget + GRACE
    results, slots = {}, Slots(SLOTS)

    def worker(entry):
        t0 = time.time()
        try:
            res = entry.run(None if ctx.bg else deadline)
        except Exception as error:  # a bug in a check must show as a failure, never as a pass
            res = Result(FAIL, "the check itself broke: %s: %s" % (type(error).__name__, error))
        res.seconds = time.time() - t0
        results[entry.name] = res
        slots.give(min(entry.weight, SLOTS))

    with concurrent.futures.ThreadPoolExecutor(max_workers=len(plan) + 1) as pool:
        for entry in plan:
            if entry.run is None:
                if selected(ctx.only, entry.name):
                    results[entry.name] = Result(SKIP, entry.why)
                continue
            if not selected(ctx.only, entry.name):
                continue  # not asked for by --only: not run, not printed, not counted
            weight = min(entry.weight, SLOTS)
            slots.take(weight)
            if not ctx.bg and time.time() + entry.est > t_start + budget:
                slots.give(weight)
                results[entry.name] = Result(LATER, "about %d s, more than the %d s left of this command; run: scripts/lane/handback.sh --only %s --bg"
                                             % (entry.est, max(0, int(t_start + budget - time.time())), entry.name))
                continue
            pool.submit(worker, entry)
    return results


def report(ctx, plan, results, log_path):
    """The lines of the answer, in plan order, and the exit status."""
    lines, details = [], []
    counts = {PASS: 0, FAIL: 0, SKIP: 0, LATER: 0}
    for entry in plan:
        res = results.get(entry.name)
        if res is None:
            continue
        counts[res.status] += 1
        if res.status == PASS:
            lines.append("PASS %s (%ds)%s" % (entry.name, round(res.seconds), (": " + res.text) if res.text else ""))
        elif res.status == FAIL:
            lines.append("FAIL %s (%ds): %s" % (entry.name, round(res.seconds), res.text))
            if res.detail:
                details.append("-- %s" % entry.name)
                details += ["   " + d for d in res.detail[:DETAIL]]
        else:
            lines.append("%s %s: %s" % (res.status, entry.name, res.text))
    lines = [cut(l) for l in lines]
    code = 1 if counts[FAIL] else 3 if counts[LATER] else 0
    last = "handback: %d passed, %d failed, %d skipped, %d later; exit %d; log %s" % (
        counts[PASS], counts[FAIL], counts[SKIP], counts[LATER], code, log_path)
    return lines + details + [last], code, [e.name for e in plan if e.name in results and results[e.name].status == LATER]


# ---------------------------------------------------------------- stale compiler, state, background

def stale_reason(root, compiler):
    """None when the compiler is newer than every compiler input of the tree, else one line saying why it is not."""
    rel = os.path.relpath(compiler, root) if str(compiler).startswith(str(root)) else str(compiler)
    if not compiler.is_file():
        return "%s is missing" % rel
    built = compiler.stat().st_mtime
    out = subprocess.run(["git", "-C", str(root), "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "src", "selfhost",
                          "build.zig", "build_*.zig", "build.zig.zon", ".zigversion"], capture_output=True, text=True, errors="replace").stdout
    newest, name = 0.0, ""
    for p in out.split("\0"):
        if not p or is_test_file(p):
            continue
        try:
            m = (root / p).stat().st_mtime
        except OSError:
            continue
        if m > newest:
            newest, name = m, p
    if newest > built + 1:
        return "%s is older than %s by %d s" % (rel, name, round(newest - built))
    return None


def remember_later(state, ran, later, base, logdir):
    """last.json: what `--rest` runs. A run replaces the entries of the checks it ran and keeps the others', so a rerun with
    `--only` of one check does not forget the rest."""
    path = state / "last.json"
    try:
        old = json.loads(path.read_text())["later"]
    except (OSError, ValueError, KeyError):
        old = []
    kept = [n for n in old if n not in ran and n.split(":")[0] not in ran]
    path.write_text(json.dumps({"later": kept + [n for n in later if n not in kept], "base": base, "log": str(logdir)}))


def state_dir(root):
    d = HOME / root.name
    d.mkdir(parents=True, exist_ok=True)
    return d


def bg_start(args, ctx, names, state):
    """Start the named checks as a detached run of this script; print how to wait for it."""
    log = ctx.logdir
    out, rcf = log / "bg.out", log / "bg.rc"
    cmd = [sys.executable, str(Path(__file__).resolve()), "--root", str(ctx.root), "--compiler", str(ctx.compiler), "--base", ctx.base,
           "--bg-child", str(rcf), "--only", ",".join(names), "--log-dir", str(log)]
    if ctx.zig:
        cmd += ["--zig", ctx.zig]
    for f in sorted(ctx.forced):
        cmd += ["--with", f]
    with open(out, "w") as fh:
        proc = subprocess.Popen(cmd, stdout=fh, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, start_new_session=True)
    entry = {"pid": proc.pid, "names": names, "out": str(out), "rc": str(rcf), "started": time.time(), "log": str(log)}
    (state / ("bg-%d.json" % proc.pid)).write_text(json.dumps(entry))
    print("RUNNING %s: pid %d, log %s" % (",".join(names), proc.pid, log))
    print("wait for it (up to 270 s; run again if it says still running): scripts/lane/handback.sh --wait")
    print("handback: started in the background; exit 3; log %s" % log)
    return 3


def wait_bg(state, pid, limit=BUDGET):
    """Wait up to LIMIT seconds for the background runs of this worktree; print each one's answer when it is done."""
    entries = sorted(state.glob("bg-*.json"))
    entries = [e for e in entries if pid is None or e.name == "bg-%d.json" % pid]
    if not entries:
        print("handback: no background run to wait for (start one with --only NAME --bg)")
        return 2
    end, code, running = time.time() + limit, 0, 0
    for path in entries:
        info = json.loads(path.read_text())
        while not Path(info["rc"]).exists() and time.time() < end and alive(info["pid"]):
            time.sleep(1)
        if Path(info["rc"]).exists():
            sys.stdout.write(Path(info["out"]).read_text())
            code = max(code, int(Path(info["rc"]).read_text().strip() or 1))
            path.unlink()
        elif not alive(info["pid"]):
            print("LOST %s: pid %d ended without an answer; log %s" % (",".join(info["names"]), info["pid"], info["log"]))
            code = max(code, 1)
            path.unlink()
        else:
            running += 1
            print("STILL RUNNING %s: pid %d, %d s so far; the same command waits again: scripts/lane/handback.sh --wait %d"
                  % (",".join(info["names"]), info["pid"], time.time() - info["started"], info["pid"]))
    return 3 if running and code == 0 else code


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


# ---------------------------------------------------------------- main

def find_zig(args):
    zig = args.zig or os.environ.get("ZIG", "")
    if zig and (os.path.isfile(zig) and os.access(zig, os.X_OK)):
        return zig
    return ""


def main(argv=None):
    ap = argparse.ArgumentParser(prog="handback.sh", description=__doc__.split("\n\n")[0], add_help=True)
    ap.add_argument("base", nargs="?", help="the commit to compare with (default: the merge base with main)")
    ap.add_argument("--base", dest="base_opt", help=argparse.SUPPRESS)
    ap.add_argument("--root", help=argparse.SUPPRESS)
    ap.add_argument("--compiler", help="the compiler (default: zig-out/bin/selka of the tree)")
    ap.add_argument("--zig", help="the pinned Zig (default: $ZIG)")
    ap.add_argument("--with", dest="with_", action="append", default=[], metavar="NAME", help="run a check even when it does not apply")
    ap.add_argument("--only", metavar="NAME[,NAME]", help="run only these checks (a doctest page: doctest:docs/x.md)")
    ap.add_argument("--rest", action="store_true", help="run the checks the last run left LATER")
    ap.add_argument("--plan", action="store_true", help="print which checks apply and why; run nothing")
    ap.add_argument("--bg", action="store_true", help="with --only: run detached, then --wait")
    ap.add_argument("--wait", nargs="?", const="all", metavar="PID", help="wait up to --budget (270) s for the background runs and print them")
    ap.add_argument("--budget", type=int, default=BUDGET, help="seconds of checks to start (default %d)" % BUDGET)
    ap.add_argument("--log-dir", help=argparse.SUPPRESS)
    ap.add_argument("--bg-child", help=argparse.SUPPRESS)
    args = ap.parse_args(argv)
    root = Path(args.root).resolve() if args.root else Path(git(LANE_DIR, "rev-parse", "--show-toplevel").strip())
    state = state_dir(root)
    if args.wait:
        return wait_bg(state, None if args.wait == "all" else int(args.wait), args.budget)
    base = args.base_opt or args.base or merge_base(root)
    changes = changed_files(root, base)
    only = {n for n in (args.only or "").split(",") if n}
    if args.rest:
        last = state / "last.json"
        if not last.is_file():
            print("handback: no earlier run in this worktree to continue (run scripts/lane/handback.sh first)")
            return 2
        only = set(json.loads(last.read_text())["later"]) or only
        if not only:
            print("handback: the last run left nothing to run; exit 0")
            return 0
    compiler = Path(args.compiler).resolve() if args.compiler else root / "zig-out" / "bin" / "selka"
    logdir = Path(args.log_dir) if args.log_dir else state / time.strftime("%y%m%d-%H%M%S", time.gmtime())
    ctx = Ctx(root, base, changes, compiler, find_zig(args), logdir, only, set(args.with_) | only, bg=bool(args.bg_child) or args.bg)
    if args.plan:
        for e in build_plan(ctx):
            on = e.run is not None and selected(only, e.name)
            print("%s %s: %s%s" % ("RUN " if on else "SKIP", e.name, e.why, (" (about %d s, %d compiler slot(s))" % (e.est, e.weight)) if on else ""))
        print("base %s; %d changed file(s)" % (base[:10], len(changes)))
        return 0
    why = stale_reason(root, compiler)
    if why:
        print("handback: %s; build it (source ~/.config/selka/dev-env.sh; scripts/build-slot.sh build zig build) and run again; nothing was run" % why)
        return 2
    if not ctx.zig:
        print("handback: no pinned Zig: source ~/.config/selka/dev-env.sh (sets $ZIG) or pass --zig PATH; nothing was run")
        return 2
    logdir.mkdir(parents=True, exist_ok=True)
    plan = build_plan(ctx)
    if args.bg and not args.bg_child:
        names = [e.name for e in plan if e.run is not None and selected(only, e.name)]
        if not only or not names:
            print("handback: --bg needs --only NAME naming a check that applies (--with NAME forces one)")
            return 2
        return bg_start(args, ctx, names, state)
    results = execute(ctx, plan, args.budget)
    lines, code, later = report(ctx, plan, results, logdir)
    text = "\n".join(lines) + "\n"
    (logdir / "handback.log").write_text(text)
    remember_later(state, [n for n in results if results[n] is not None], later, base, logdir)
    sys.stdout.write(text)
    sys.stdout.flush()  # the answer is in the file before the status file says it is there
    if args.bg_child:
        Path(args.bg_child).write_text("%d\n" % code)
    return code


if __name__ == "__main__":
    sys.exit(main())

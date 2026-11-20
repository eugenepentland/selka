#!/usr/bin/env python3
"""The patch gate: the landing check for a compiler fix on ``projects/fixes``. NOT the complete verification.

    python3 scripts/patch_gate.py                  # base = merge-base of HEAD and main
    python3 scripts/patch_gate.py --base HEAD      # judge only the uncommitted edit
    python3 scripts/patch_gate.py --dry-run        # print the path verdict and the steps, run nothing
    python3 scripts/patch_gate.py --parallel       # run the seven slow checks at the same time (--jobs N at most)
    python3 scripts/patch_gate.py --log-dir DIR    # write the step logs to DIR

Source ``~/.config/selka/dev-env.sh`` first, as for every build in this repository.

Path rule (checked first). The changed paths are the committed diff ``base..HEAD``,
the staged and unstaged changes, and the untracked files that are not ignored. The
gate is enough only when every one of them is under ``src/``, ``docs/``, ``tests/``,
``test/``, ``examples/`` or ``experiments/project-ladder-20261018/``, or is
``SPEC.md``, and none of them is verification machinery (``MACHINERY`` below). Any
other path, such as ``scripts/``, a ``build*.zig`` or ``selfhost/``, needs the complete verification, so the script lists those paths,
prints ``complete verification required: ...`` and exits 3 without running a step.

Steps. Each runs through ``scripts/build-slot.sh build`` (so admission is shared with
the other agents), in this order, and the run stops at the first failure: the Debug
install, the affected tests, then ``test-units``, ``test-core``,
``test-cli``, ``test-lang``, ``test-docs``, ``doc-coverage`` and ``fmt-check``. The three
compiler suites run as the sharded, cached steps ``test-units-gate``, ``test-core-gate``
and ``test-cli-gate`` (the shards ``zig build test`` runs), so a shard whose test binary,
compiler, environment and declared inputs are unchanged is not run again: a docs or
``tests/lang`` edit reruns none of them, and a rerun of an unchanged tree reruns none.

``--parallel`` is an opt-in speed-up that keeps the same checks.
- The first step (the install) still runs first and stops the run when it fails. (Guardian,
  the second step until GH-2, was turned off on 18 November 2026.)
- The other seven run as one ``suites`` step: a single ``zig build`` over
  ``test-units-gate``, ``test-core-gate``, ``test-cli-gate``, ``test-lang``, ``test-docs``,
  ``test-doc-coverage`` and ``fmt-check`` behind one build slot. Zig's own scheduler runs
  them at the same time, every failure is reported rather than only the first, and the gate
  holds one slot instead of up to three (separate steps queued behind other agents' jobs: a
  0.3 s check once waited 196 s).
- The affected tests run beside the ``suites`` step, not before it, with
  ``--skip-gate-suites``: they drop what ``suites`` reruns in full (the unit, tooling,
  text-scalar, core and CLI roots, ``tests/lang``, ``tests/value_semantics``,
  ``tests/ported``, doctests, doc-coverage) and keep the rest (``tests/guest``, the golden,
  juice, idioms and identity roots, the Python drivers). On 19 October 2026 a core edit made
  them run all 1,369 core tests (36 s) in a second build, beside the suites' own run, so
  overlapping the two gained nothing until the duplicate went.

The cost: a failing affected test no longer stops the suites, and both verdicts are
reported. The wall time becomes the slowest check instead of the sum. ``--jobs`` is
accepted for old callers and has no effect.

Every step's combined output goes to ``<log dir>/<NN>-<step>.log``. One JSON line per
run is appended to ``experiments/project-ladder-20261018/gates.jsonl``. Exit status:
0 green, 1 red, 2 usage error, 3 complete verification required. ``--dry-run`` exits
3 if the path rule fails and 0 otherwise; it writes no record.

This is a developer script outside the install graph; nothing under ``src/`` runs it.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import dataclasses
import datetime
import json
import os
from pathlib import Path
import re
import shlex
import signal
import subprocess
import sys
import threading
import time
from typing import Callable, Mapping, Optional, Sequence

ROOT = Path(__file__).resolve().parents[1]
VERSION = "patch-gate-v1"
RECORD_REL = "experiments/project-ladder-20261018/gates.jsonl"
COMPLETE_LINE = "complete verification required: python3 scripts/verify_cache.py --profile complete"
DEFAULT_LOG_ROOT = Path("~/.cache/selka-projects/patch-gate-logs")

EXIT_GREEN, EXIT_RED, EXIT_USAGE, EXIT_COMPLETE = 0, 1, 2, 3

# A diff confined to these is covered by the patch gate.
ALLOWED_PREFIXES = ("src/", "docs/", "tests/", "test/", "examples/", "experiments/project-ladder-20261018/")
ALLOWED_FILES = frozenset({"SPEC.md"})
# Files inside the allowed prefixes that still belong to the verification
# machinery, so an edit to one needs the complete verification:
#
# * the four `src/` files that `build_env.zig` and `build_identity.zig` (the host
#   tools every cached test step runs through) import, plus the data file the
#   environment contract is read from (`build_test_inputs.environment_contract`),
#   and the unit tests that pin them;
# * the Python drivers under `tests/` that prove the gate's own input coverage and
#   compiler identity.
#
# `src/user_docs.zig`, `src/semantic_cache_format.zig` and `src/product.zig` are
# also read by `build.zig`, but only as data (the list of embedded guides, the cache
# version string, the product's names); they are compiler content, so they are not
# listed. The check in
# `patch_gate_test.py` fails when a root `build*.zig` starts importing another
# `src/` file, so the next import gets a decision.
MACHINERY = frozenset({
    "src/environment_identity.zig",
    "src/environment_identity.zon",
    "src/build_env_rules.zig",
    "src/build_identity_rules.zig",
    "src/environment_identity_test.zig",
    "src/build_env_rules_test.zig",
    "src/build_identity_rules_test.zig",
    "src/environment_test.zig",
    "tests/input_manifest.py",
    "tests/test_inputs_coverage.py",
    "tests/compiler_identity_cache.py",
})
BUILD_READ_BUT_NOT_MACHINERY = frozenset({"src/user_docs.zig", "src/semantic_cache_format.zig", "src/product.zig"})

ADMISSION_LINE = re.compile(r"build-slot: \w+ slot \d+, FIFO ticket \d+ after ([0-9.]+)s")
FR_SUBJECT = re.compile(r"^FR-[0-9]+")
TAIL_LINES = 40
# The named steps before the grouped `suites` step in the --parallel plan.
SEQUENTIAL_PREFIX = 2
# With --parallel, this leading step (the install) still runs first and stops the run when it
# fails; the affected tests then run beside the `suites` step.
PARALLEL_PREFIX = 1
# Build slots on the shared machine (SELKA_BUILD_SLOTS); more concurrent steps than that only queue.
DEFAULT_JOBS = 3


class UsageError(Exception):
    """A base that does not resolve, or another bad invocation."""


class Interrupted(BaseException):
    """SIGTERM arrived while a step was running."""


@dataclasses.dataclass(frozen=True)
class Step:
    """One gate step: a short name for logs, the command, and the admission slot kind."""

    name: str
    argv: tuple[str, ...]
    slot: str = "build"

    def command(self, root: Path) -> list[str]:
        """The command actually spawned: the same argv behind the admission wrapper."""
        return [str(root / "scripts" / "build-slot.sh"), self.slot, *self.argv]


@dataclasses.dataclass
class StepResult:
    """What running a step produced."""

    exit: int
    wall_s: float
    wait_s: float = 0.0


Runner = Callable[[Step, Path, Path], StepResult]


# With --parallel the seven slow checks are one `zig build` over their targets, behind one build slot.
SUITES = ("test-units-gate", "test-core-gate", "test-cli-gate", "test-lang", "test-docs", "test-doc-coverage", "fmt-check")


def steps_for(base: str, grouped: bool = False) -> list[Step]:
    """The nine gate steps in order, with the affected-tests base filled in.

    `grouped` (the --parallel plan) keeps the first two and replaces the other seven by one
    `suites` step: a single `zig build` over the same checks, whose own scheduler runs them
    at the same time. Seven separate steps hold up to three of the machine's build slots and
    queue behind other agents' jobs (a 0.3 s check once waited 196 s for a slot), where one
    step waits once."""
    if grouped:
        install, affected = steps_for(base)[:SEQUENTIAL_PREFIX]
        # The suites step reruns the compiler roots, tests/lang and the docs in full, so the affected
        # tests beside it keep only what it does not run.
        affected = Step(affected.name, affected.argv + ("--skip-gate-suites",))
        return [install, affected, Step("suites", ("zig", "build", *SUITES))]
    return [
        Step("zig-build", ("zig", "build")),
        Step("affected-tests", ("python3", "scripts/affected_tests.py", "--base", base)),
        Step("test-units", ("zig", "build", "test-units-gate")),
        Step("test-core", ("zig", "build", "test-core-gate")),
        Step("test-cli", ("zig", "build", "test-cli-gate")),
        Step("test-lang", ("zig", "build", "test-lang")),
        Step("test-docs", ("zig", "build", "test-docs")),
        Step("doc-coverage", ("zig-out/bin/selka", "doc-coverage", ".")),
        Step("fmt-check", ("zig", "build", "fmt-check")),
    ]


def is_allowed(path: str) -> bool:
    """Whether the patch gate covers a change to this repository-relative path."""
    if path in MACHINERY:
        return False
    return path in ALLOWED_FILES or path.startswith(ALLOWED_PREFIXES)


def disallowed(paths: Sequence[str]) -> list[str]:
    """The paths the patch gate does not cover, sorted."""
    return sorted(path for path in paths if not is_allowed(path))


def git(root: Path, *args: str, check: bool = True) -> str:
    """Run git in the repository and return its stdout."""
    done = subprocess.run(["git", *args], cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if check and done.returncode != 0:
        raise UsageError("git {} failed: {}".format(" ".join(args), done.stderr.strip()))
    return done.stdout


def resolve_commit(root: Path, ref: str) -> str:
    """The commit a ref names, or a UsageError."""
    done = subprocess.run(["git", "rev-parse", "--verify", "--quiet", ref + "^{commit}"], cwd=root,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if done.returncode != 0:
        raise UsageError("--base {!r} does not name a commit".format(ref))
    return done.stdout.strip()


def resolve_base(root: Path, base: Optional[str]) -> tuple[str, str]:
    """The base commit and how it was chosen."""
    if base:
        return resolve_commit(root, base), "given"
    done = subprocess.run(["git", "merge-base", "HEAD", "main"], cwd=root, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True)
    if done.returncode != 0 or not done.stdout.strip():
        raise UsageError("no merge-base of HEAD and main; pass --base REF")
    return done.stdout.strip(), "merge-base of HEAD and main"


def split_z(text: str) -> list[str]:
    """The entries of NUL-separated git output."""
    return [entry for entry in text.split("\0") if entry]


def uncommitted_paths(root: Path) -> set[str]:
    """Staged, unstaged and untracked-but-not-ignored paths (renames count both names)."""
    found = set(split_z(git(root, "diff", "--name-only", "--no-renames", "-z", "HEAD")))
    found.update(split_z(git(root, "ls-files", "--others", "--exclude-standard", "-z")))
    return found


def changed_paths(root: Path, base: str) -> list[str]:
    """Every path the run judges: the committed diff base..HEAD plus the uncommitted changes."""
    found = set(split_z(git(root, "diff", "--name-only", "--no-renames", "-z", base, "HEAD")))
    found.update(uncommitted_paths(root))
    return sorted(found)


def fr_ids(root: Path, base: str) -> list[str]:
    """Distinct FR-NNN ids that start commit subjects in base..HEAD, oldest first."""
    subjects = git(root, "log", "--reverse", "--format=%s", base + "..HEAD").splitlines()
    ids: list[str] = []
    for subject in subjects:
        match = FR_SUBJECT.match(subject)
        if match and match.group(0) not in ids:
            ids.append(match.group(0))
    return ids


def load_average() -> Optional[list[float]]:
    """The 1, 5 and 15 minute load averages from /proc/loadavg, or None."""
    try:
        return [float(field) for field in Path("/proc/loadavg").read_text().split()[:3]]
    except (OSError, ValueError):
        return None


def utc_now() -> datetime.datetime:
    """The current time in UTC."""
    return datetime.datetime.now(datetime.timezone.utc)


def environment_warnings(root: Path, env: Mapping[str, str]) -> list[str]:
    """Reasons the shell may not be set up as CLAUDE.md requires (not fatal)."""
    notes = []
    if not env.get("SELKA_SLOT_DIR") or not env.get("ZIG_LOCAL_CACHE_DIR") or not env.get("TMPDIR", "").startswith(str(root)):
        notes.append("dev-env.sh does not look sourced (shared admission directory, per-worktree "
                     "ZIG_LOCAL_CACHE_DIR and on-disk TMPDIR): run `source ~/.config/selka/dev-env.sh` first")
    local = env.get("ZIG_LOCAL_CACHE_DIR")
    if local and not Path(local).resolve().is_relative_to(root.resolve()):
        notes.append("ZIG_LOCAL_CACHE_DIR={} is outside this worktree; never share it between worktrees".format(local))
    return notes


def parse_wait(log_path: Path) -> float:
    """The admission wait the build-slot wrapper reported at the top of a step's log."""
    try:
        with log_path.open("rb") as log:
            head = log.read(16384).decode("utf-8", "replace")
    except OSError:
        return 0.0
    match = ADMISSION_LINE.search(head)
    return float(match.group(1)) if match else 0.0


LIVE: set = set()  # children of running steps, so an interrupt can stop every one
LIVE_LOCK = threading.Lock()


def terminate_all() -> None:
    """Stop every step that is still running."""
    with LIVE_LOCK:
        children = list(LIVE)
    for child in children:
        terminate(child)


def terminate(child: "subprocess.Popen[bytes]") -> None:
    """Stop a step's whole process group, politely and then for good."""
    for signum, grace in ((signal.SIGTERM, 20), (signal.SIGKILL, 5)):
        try:
            os.killpg(child.pid, signum)
        except ProcessLookupError:
            return
        try:
            child.wait(timeout=grace)
            return
        except subprocess.TimeoutExpired:
            continue


def run_step(step: Step, log_path: Path, root: Path) -> StepResult:
    """Run one step behind the admission wrapper, logging combined output."""
    started = time.monotonic()
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("wb") as log:
        log.write(("$ " + shlex.join(step.argv) + "\n").encode())
        log.flush()
        child = subprocess.Popen(step.command(root), cwd=root, stdin=subprocess.DEVNULL, stdout=log,
                                 stderr=subprocess.STDOUT, start_new_session=True)
        with LIVE_LOCK:
            LIVE.add(child)
        try:
            code = child.wait()
        except BaseException:
            terminate(child)
            raise
        finally:
            with LIVE_LOCK:
                LIVE.discard(child)
    return StepResult(code, time.monotonic() - started, parse_wait(log_path))


def tail(log_path: Path, lines: int = TAIL_LINES) -> list[str]:
    """The last lines of a step's log, or nothing when there is no log."""
    try:
        return log_path.read_text(errors="replace").splitlines()[-lines:]
    except OSError:
        return []


def append_record(root: Path, record: dict) -> None:
    """Append one JSON line to the gate record."""
    path = root / RECORD_REL
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(record) + "\n")


def finish_step(index: int, steps: Sequence[Step], step: Step, log_path: Path, result: StepResult, record: dict) -> bool:
    """Record and print one finished step; returns whether it failed."""
    entry = {"name": step.name, "argv": list(step.argv), "wall_s": round(result.wall_s, 1), "exit": result.exit}
    if result.wait_s:
        entry["wait_s"] = round(result.wait_s, 1)
    record["steps"].append(entry)
    wait = " (admission wait {:.1f}s)".format(result.wait_s) if result.wait_s >= 0.05 else ""
    print("[{:2d}/{}] {:<4} {:<15} {:8.1f}s  exit {}{}".format(
        index, len(steps), "ok" if result.exit == 0 else "FAIL", step.name, result.wall_s, result.exit, wait), flush=True)
    if result.exit == 0:
        return False
    record["verdict"] = "red"
    print("--- {} failed; last {} lines of {} ---".format(step.name, TAIL_LINES, log_path))
    for line in tail(log_path):
        print(line)
    return True


def log_for(log_dir: Path, index: int, step: Step) -> Path:
    """The log file of the step at this 1-based position."""
    return log_dir / "{:02d}-{}.log".format(index, step.name)


def run_sequence(chosen: Sequence[Step], first: int, steps: Sequence[Step], runner: Runner, root: Path,
                 log_dir: Path, record: dict) -> bool:
    """Run steps one at a time, stopping after the first failure; returns whether one failed."""
    for index, step in enumerate(chosen, first):
        log_path = log_for(log_dir, index, step)
        if finish_step(index, steps, step, log_path, runner(step, log_path, root), record):
            return True
    return False


def run_concurrently(chosen: Sequence[Step], first: int, steps: Sequence[Step], runner: Runner, root: Path,
                     log_dir: Path, record: dict, jobs: int = DEFAULT_JOBS) -> bool:
    """Run up to `jobs` steps at the same time and report each as it finishes; returns whether any failed."""
    failed = False
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, min(jobs, len(chosen)))) as pool:
        try:
            futures = {}
            for index, step in enumerate(chosen, first):
                log_path = log_for(log_dir, index, step)
                futures[pool.submit(runner, step, log_path, root)] = (index, step, log_path)
            for future in concurrent.futures.as_completed(futures):
                index, step, log_path = futures[future]
                failed |= finish_step(index, steps, step, log_path, future.result(), record)
        except BaseException:
            terminate_all()  # the pool joins its workers on the way out, so stop their children first
            raise
    return failed


def parser() -> argparse.ArgumentParser:
    """The command line."""
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--base", help="commit to diff against (default: merge-base of HEAD and main)")
    p.add_argument("--dry-run", action="store_true", help="print the path verdict and the steps; run nothing, record nothing")
    p.add_argument("--parallel", action="store_true",
                   help="after the first {} steps, run the affected tests beside one zig build over the slow checks and report every failure".format(PARALLEL_PREFIX))
    p.add_argument("--jobs", type=int, default=DEFAULT_JOBS,
                   help="accepted for old callers; with --parallel the remaining checks are one step and run together (default {})".format(DEFAULT_JOBS))
    p.add_argument("--log-dir", type=Path, help="directory for the step logs (default: {}/<UTC timestamp>)".format(DEFAULT_LOG_ROOT))
    return p


def run(argv: Sequence[str], root: Path = ROOT, runner: Optional[Runner] = None,
        now: Callable[[], datetime.datetime] = utc_now) -> int:
    """Run the patch gate; returns the process exit status. `runner` replaces the real step runner in tests."""
    args = parser().parse_args(argv)
    runner = runner or run_step
    try:
        base, how = resolve_base(root, args.base)
        paths = changed_paths(root, base)
        head = git(root, "rev-parse", "HEAD").strip()
        frs = fr_ids(root, base)
    except UsageError as error:
        print("patch-gate: " + str(error), file=sys.stderr)
        return EXIT_USAGE
    bad = disallowed(paths)
    started = now()
    steps = steps_for(base, grouped=args.parallel)
    print("patch gate (not the complete verification)")
    print("base: {} ({}); head: {}; {} changed path(s); fix ids: {}".format(
        base[:12], how, head[:12], len(paths), ", ".join(frs) or "none"))
    if bad:
        print("{} changed path(s) are outside the patch gate's scope:".format(len(bad)))
        for path in bad:
            print("  " + path)
        print(COMPLETE_LINE)
    else:
        print("path rule: ok, every changed path is in scope")
    if args.dry_run:
        print("steps ({}), each through scripts/build-slot.sh build{}:".format(
            len(steps), "; --parallel: steps {} and {} run at the same time, the last being one zig build over the seven slow checks".format(
                PARALLEL_PREFIX + 1, PARALLEL_PREFIX + 2) if args.parallel else ""))
        for index, step in enumerate(steps, 1):
            print("  {:2d}. {:<15} {}".format(index, step.name, shlex.join(step.argv)))
        return EXIT_COMPLETE if bad else EXIT_GREEN

    record = {
        "version": VERSION,
        "commit": head,
        "dirty": bool(uncommitted_paths(root) - {RECORD_REL}),
        "base": base,
        "started_utc": started.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "steps": [],
        "verdict": "complete-required" if bad else "green",
        "fr_ids": frs,
        "disallowed": bad,
        "load_avg_start": load_average(),
    }
    if bad:
        record["load_avg_end"] = load_average()
        append_record(root, record)
        return EXIT_COMPLETE

    log_dir = (args.log_dir or DEFAULT_LOG_ROOT.expanduser() / started.strftime("%Y%m%dT%H%M%SZ")).expanduser().resolve()
    record["log_dir"] = str(log_dir)
    print("logs: " + str(log_dir))
    record["parallel"] = bool(args.parallel)
    if args.parallel:
        record["jobs"] = args.jobs
    began = time.monotonic()
    interrupted = False
    try:
        head_steps = steps[:PARALLEL_PREFIX] if args.parallel else steps
        failed = run_sequence(head_steps, 1, steps, runner, root, log_dir, record)
        if not failed and args.parallel:
            run_concurrently(steps[PARALLEL_PREFIX:], PARALLEL_PREFIX + 1, steps, runner, root, log_dir, record, args.jobs)
    except (KeyboardInterrupt, Interrupted):
        interrupted = True
        record["verdict"] = "red"
        record["interrupted"] = True
        terminate_all()
        print("patch-gate: interrupted", file=sys.stderr)
    position = {step.name: place for place, step in enumerate(steps)}
    record["steps"].sort(key=lambda entry: position[entry["name"]])  # gate order, whatever order they finished in
    total = time.monotonic() - began
    record["total_s"] = round(total, 1)
    record["load_avg_end"] = load_average()
    append_record(root, record)
    print("verdict: {} ({} of {} steps run, {:.1f}s); record appended to {}".format(
        record["verdict"], len(record["steps"]), len(steps), total, RECORD_REL))
    if interrupted:
        return EXIT_RED
    return EXIT_GREEN if record["verdict"] == "green" else EXIT_RED


def main(argv: Optional[Sequence[str]] = None) -> int:
    """Entry point: warn about the environment, turn SIGTERM into a clean stop, run the gate."""
    def on_term(signum: int, frame: object) -> None:
        raise Interrupted()

    signal.signal(signal.SIGTERM, on_term)
    sys.stdout.reconfigure(line_buffering=True)  # a log file or pipe sees each line as it happens
    for note in environment_warnings(ROOT, os.environ):
        print("patch-gate: warning: " + note, file=sys.stderr)
    return run(sys.argv[1:] if argv is None else argv)


if __name__ == "__main__":
    sys.exit(main())

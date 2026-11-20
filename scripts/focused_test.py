#!/usr/bin/env python3
"""Supported focused-test wrapper for the Zig suites.

Run from anywhere inside the repository:

    python3 scripts/focused_test.py units arena
    python3 scripts/focused_test.py cli "CLI managed constants"
    python3 scripts/focused_test.py full
    python3 scripts/focused_test.py --wait 12345

``units``, ``tooling``, ``cli`` and ``golden`` require a non-empty substring and run only
the tests whose names match it. A Guardian runtime-filter capability reuses the
complete binary; older dependencies retain compile-time filtering. ``full`` is the explicit full-suite request and refuses a
filter, which keeps "I meant one area" and "I meant everything" distinguishable.

The wrapper waits in the foreground and prints what an agent needs (`scripts/failure_report.py` reads the output):

* a pass is one line (what ran, how many tests, seconds) and the closing line;
* a failure is the failing tests' names, each with its `expected` and `found` lines or its first diagnostic and the
  `file:line` of the test, at most 30 lines in all; when the log shows no known failure form the last 20 lines and
  a note that nothing was recognised;
* the last line is always `exit status N; log PATH` (the complete output is saved there, whatever was printed);
* the exit status is the wrapped command's: the text only chooses what to print (it is 1 for a run that exited 0
  and still shows a failure);
* a run that is not done after ``--limit`` seconds (default 270, under the lane card's 280) keeps running, detached,
  and the wrapper says so: `still running ... (pid N)`, the one command that waits for it
  (`python3 scripts/focused_test.py --wait PID`, which prints the same result and may be repeated), and exits 124.
  Nobody polls with `sleep`, `pgrep` or `tail`. `kill -TERM -- -PID` ends it (its own process group).

When this worktree's watcher runs (``scripts/dev_loop.py start``), ``units`` (the compiler root) and ``cli`` run
the watcher's current binaries instead: ``dev_loop.py test`` waits for the build that holds the newest edit, then
runs the binary with Guardian's runtime filter, and compiles nothing. ``--no-watch`` builds as before.

Otherwise it only ever invokes the supported ``zig build`` targets. Do not copy the
``--listen=-`` command line the build runner prints for an internal test step.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import failure_report  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
LOG_DIR = ROOT / ".selka-cache" / "focused-tests"
# Targets that honour `-Dtest-filter`. `full` is the whole gate, which does not.
FOCUSED = {"text-scalar": "test-text-scalar-units", "units": "test-units", "cli": "test-cli", "golden": "test-golden", "tooling": "test-tooling-units"}
FULL = "full"
DEFAULT_LIMIT = 270.0
STILL_RUNNING = 124
LOST = -1


class FilterError(ValueError):
    """The requested test selection was empty or contradictory."""


def validate(root: str, filt: str | None) -> str | None:
    """Return the filter to pass, or raise :class:`FilterError` on a bad request."""
    if root == FULL:
        if filt is not None and filt.strip():
            raise FilterError("full runs the whole suite; drop the test filter")
        return None
    if root not in FOCUSED:
        raise FilterError("unknown target {!r}; choose {}".format(root, ", ".join(sorted([*FOCUSED, FULL]))))
    if filt is None or not filt.strip():
        raise FilterError("{} needs a non-empty test filter; use `full` for the whole suite".format(root))
    if "\x00" in filt:
        raise FilterError("test filter must not contain a NUL byte")
    return filt


def zig_program() -> str:
    """The Zig driver to run: the checkout's ``zigw`` wrapper when it is present.

    ``zigw`` pins ``ZIG_GLOBAL_CACHE_DIR`` inside the checkout, which is the only
    writable path under the agent sandbox. A bare ``zig`` dies there with
    ``failed to check cache: manifest_create ReadOnlyFileSystem``, because its
    default global cache lives under ``$HOME``.
    """
    wrapper = ROOT / "zigw"
    if wrapper.is_file() and os.access(wrapper, os.X_OK):
        return str(wrapper)
    return "zig"


def command(root: str, filt: str | None) -> list[str]:
    """The supported ``zig build`` command line for one request."""
    target = "test" if root == FULL else FOCUSED[root]
    # Explicit legacy namespaces route to their independent executable. Broad
    # filters remain scoped to the requested root; no-match remains a failure.
    moved = ("input_probe_test.test.", "fix_plan_test.test.", "timings_test.test.",
             "invalidation_test.test.", "doc_coverage_test.test.", "doc_coverage.test.")
    if root == "units" and filt is not None and filt.startswith(moved):
        target = FOCUSED["tooling"]
        filt = filt.replace("doc_coverage.test.", "doc_coverage_test.test.", 1)
    argv = [zig_program(), "build", target, "--summary", "all"]
    if filt is not None:
        argv.append("-Dtest-filter=" + filt)
    return argv


def log_path(root: str, filt: str | None) -> Path:
    """A stable, ignored path for the complete output of this run."""
    stamp = time.strftime("%Y%m%d-%H%M%S")
    slug = (filt or "full").replace("/", "_").replace(" ", "_")[:48]
    return LOG_DIR / "{}-{}-{}.log".format(root, slug, stamp)


def what_ran(root: str, filt: str | None) -> str:
    """The request in a few words: `units 'arena'`, or `full`."""
    return FULL if root == FULL else "{} {!r}".format(root, filt)


def launch(argv: list[str], log: Path, what: str) -> dict:
    """Start ARGV detached, its output in LOG; the state that `--wait` and the report read.

    The command runs under a shell that writes its exit status to `LOG.rc` when it ends, in a session of its own so
    that the run survives the wrapper, a `timeout` around it and a tool call that ends. The state is `LOG.json`.
    """
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    rc = Path(str(log) + ".rc")
    rc.unlink(missing_ok=True)
    script = '"$@"; code=$?; echo $code > "$0.tmp" && mv "$0.tmp" "$0"; exit $code'
    with open(log, "wb") as stream:
        proc = subprocess.Popen(["sh", "-c", script, str(rc), *argv], cwd=str(ROOT), stdin=subprocess.DEVNULL,
                                stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
    state = {"pid": proc.pid, "what": what, "log": str(log), "rc": str(rc), "started": time.time()}
    Path(str(log) + ".json").write_text(json.dumps(state), encoding="utf-8")
    state["proc"] = proc
    return state


def alive(state: dict) -> bool:
    """Whether the run's shell is still there (the Popen when this process started it, else the pid)."""
    proc = state.get("proc")
    if proc is not None:
        return proc.poll() is None
    try:
        os.kill(state["pid"], 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def wait_for(state: dict, limit: float) -> int | None:
    """The run's exit status once it ends; None when LIMIT seconds pass first; LOST when it ended without writing one."""
    rc = Path(state["rc"])
    deadline = time.monotonic() + limit
    while True:
        if rc.exists():
            try:
                return int(rc.read_text().strip())
            except ValueError:
                return LOST
        if not alive(state):
            return int(rc.read_text().strip()) if rc.exists() else LOST
        if time.monotonic() >= deadline:
            return None
        time.sleep(0.2)


def finish(state: dict, limit: float, tail: int, out=None) -> int:
    """Wait up to LIMIT seconds, then print the report of the finished run or the way to wait again; the exit status."""
    out = out or print
    log = Path(state["log"])
    code = wait_for(state, limit)
    text = log.read_text(encoding="utf-8", errors="replace") if log.exists() else ""
    if code is None:
        out("still running after {:.0f}s (pid {}): {}".format(time.time() - state["started"], state["pid"], state["what"]))
        queued = failure_report.queued(text.splitlines())
        if queued:
            out(queued)
        out("wait: python3 scripts/focused_test.py --wait {}".format(state["pid"]))
        out(failure_report.closing(STILL_RUNNING, log))
        return STILL_RUNNING
    rc = Path(state["rc"])
    seconds = (rc.stat().st_mtime if rc.exists() else time.time()) - state["started"]
    if code == LOST:
        out("the run ended without an exit status (its shell was killed): treat it as failed and run it again")
        code = 1
    for line in failure_report.render(text, code, state["what"], seconds, tail=tail):
        out(line)
    status = failure_report.exit_status(code, text)
    out(failure_report.closing(status, log))
    return status


def find_run(pid: int) -> dict | None:
    """The newest recorded run whose shell had process id PID, from the states under LOG_DIR."""
    states = sorted(LOG_DIR.glob("*.json"), key=lambda path: path.stat().st_mtime, reverse=True)
    for path in states:
        try:
            state = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(state, dict) and state.get("pid") == pid and "log" in state and "rc" in state:
            return state
    return None


# The focused targets a watcher's binaries hold: the unit root (not the tooling root) and the CLI root.
WATCH_ROOTS = {"units": "units", "cli": "cli"}


def watch_run(root: str, filt: str | None, worktree: Path = ROOT, out=print) -> int | None:
    """Run ROOT's tests on a live watcher's binaries; None when there is no watcher or it does not build ROOT."""
    if root not in WATCH_ROOTS or not filt or (root == "units" and "test-tooling-units" in command(root, filt)):
        return None
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import dev_loop
    if not dev_loop.daemon_alive(worktree) or dev_loop.daemon_mode(worktree) == "no-freeze":
        return None
    out("focused test: this worktree's watcher runs; using its watch binaries (dev_loop.py test; --no-watch builds)")
    return dev_loop.run_tests(worktree, WATCH_ROOTS[root], filt, out=out)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("target", nargs="?", help="units, tooling, text-scalar, cli, golden, or full")
    parser.add_argument("filter", nargs="?", help="non-empty substring for a focused target")
    parser.add_argument("--tail", type=int, default=failure_report.TAIL_LINES,
                        help="log lines to show when a failed log holds no known failure form (default 20)")
    parser.add_argument("--no-watch", action="store_true", help="build normally even when this worktree's watcher runs")
    parser.add_argument("--limit", type=float, default=DEFAULT_LIMIT,
                        help="seconds to wait before leaving the run going and printing how to wait again (default 270)")
    parser.add_argument("--wait", type=int, metavar="PID",
                        help="wait for the run that printed `still running ... (pid PID)` and print its result")
    args = parser.parse_args(argv)

    if args.wait is not None:
        state = find_run(args.wait)
        if state is None:
            print("focused test: no run with pid {} is recorded under {}".format(args.wait, LOG_DIR), file=sys.stderr)
            return 2
        return finish(state, args.limit, args.tail)
    if args.target is None:
        parser.error("name a target (units, tooling, text-scalar, cli, golden, full) or use --wait PID")
    try:
        filt = validate(args.target, args.filter)
    except FilterError as error:
        print("focused test: {}".format(error), file=sys.stderr)
        return 2

    if not args.no_watch:
        watched = watch_run(args.target, filt)
        if watched is not None:
            return watched

    argv = command(args.target, filt)
    if args.target == "units":
        message = ("routing explicit helper namespace to independent tooling root"
                   if "test-tooling-units" in argv else
                   "units filters select the compiler root; independent helpers use tooling or text-scalar")
        print("focused tests: " + message, file=sys.stderr)
    state = launch(argv, log_path(args.target, filt), what_ran(args.target, filt))
    return finish(state, args.limit, args.tail)


if __name__ == "__main__":
    sys.exit(main())

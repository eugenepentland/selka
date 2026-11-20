#!/usr/bin/env python3
"""The gate's cheap checks, run before any test action starts (lane DL-4, item 4a).

    python3 scripts/gate_cheap_checks.py [--compiler zig-out/bin/selka] [--zig ZIG]

Each check here runs the command one action of the complete gate runs, on the same tree:

    check          gate action                              needs
    zig-format     `zig fmt --check` over the paths build.zig formats   Zig
    my_format      `scripts/check_my_format.py` (one `selka fmt --check` per live file)   the compiler
    doc-coverage   `selka doc-coverage .`                  the compiler
    coverage       `tests/test_inputs_coverage.py` and the two self-tests of `test-inputs-coverage`   Python
    registry       the inventory's unregistered actions (`test-verification-registry` fails on any)   the inventory

A check's finding is final: the gate action runs the same command on the same inputs and fails the same way, so
`verify_cache.py` ends the gate there, before any test action, and prints the finding with its `file:line`. A check
that passes decides nothing: the gate still runs and records its own actions. A check whose tool is missing (no
compiler yet) is skipped, never failed. `scripts/edit_check.py` runs the same list. Guardian's check left this list
when Guardian was turned off (GH-2, 18 November 2026).

This module records no evidence and runs no build. It is not one of the coordinator's keyed modules.
"""
from __future__ import annotations

import argparse
import concurrent.futures
from dataclasses import dataclass, field
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
# The paths of `b.addFmt` in build.zig, in its order (`gate_cheap_checks_test.py` compares them with build.zig).
ZIG_FORMAT_PATHS = ("build.zig", "build_env.zig", "build_identity.zig", "build_test_inputs.zig", "build_verification.zig",
                    "src", "tests", "test", "selfhost")
# The three commands of build.zig's `test-inputs-coverage` step, each with the gate action it is registered as.
COVERAGE_COMMANDS = (("coverage_self", ("tests/test_inputs_coverage.py", "--self-test")),
                     ("manifest_self", ("tests/input_manifest.py", "--self-test")),
                     ("coverage", ("tests/test_inputs_coverage.py",)))
# The check names in report order; each is also the id of the gate action whose command it runs.
CHECKS = ("registry", "zig-format", "coverage", "my_format", "doc-coverage")
COMPILER_CHECKS = ("my_format", "doc-coverage")
# The gate actions each check stands for: a check runs only when the inventory registers one of them.
ACTIONS = {"registry": (), "zig-format": ("zig-format",), "coverage": ("coverage", "coverage_self", "manifest_self"),
           "my_format": ("my_format",), "doc-coverage": ("doc-coverage",)}
PHASE_SECONDS = 120  # the whole cheap phase's deadline: past it, unfinished checks are abandoned and decide nothing
COMMAND_SECONDS = 600  # one command's ceiling: far above any measured run, so it bounds a hang only
MAX_LINES = 6  # diagnostic lines kept per finding
FILE_LINE = re.compile(r'((?:[A-Za-z0-9_.+/-]+/)?[A-Za-z0-9_.+-]+\.(?:zig|py|selka|md|json|zon|toml)):([0-9]+)')


@dataclass
class Finding:
    """One failed cheap check: the gate action it stands for, where, and what its command printed."""
    check: str
    message: str
    location: str | None = None
    lines: list[str] = field(default_factory=list)


@dataclass
class Context:
    """What the checks run with: the tree, the pinned Zig, the compiler (None until one is known current), the
    environment and the coordinator's inventory (None outside the coordinator)."""
    root: Path
    zig: str
    compiler: Path | None = None
    env: dict | None = None
    plan: dict | None = None
    # The commands running now, each in a process group of its own, so `Runner.stop` can end them (and what they
    # started); `stopped` refuses new ones.
    processes: set = field(default_factory=set)
    stopped: bool = False


def short(path: str, root: Path) -> str:
    """A path as the repository names it."""
    text = str(path)
    prefix = str(root).rstrip("/") + "/"
    return text[len(prefix):] if text.startswith(prefix) else text


def first_location(lines, root: Path) -> str | None:
    for line in lines:
        match = FILE_LINE.search(line)
        if match:
            return "%s:%s" % (short(match.group(1), root), match.group(2))
    return None


def end_group(process) -> None:
    """End one command's process group: TERM, then KILL."""
    for signum in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(process.pid, signum)
        except (ProcessLookupError, PermissionError):
            return
        try:
            process.wait(timeout=2)
            return
        except subprocess.TimeoutExpired:
            continue


def run(context: Context, argv, input=None) -> subprocess.CompletedProcess:
    """One command of a check, in its own process group, registered so that `Runner.stop` can end it."""
    if context.stopped:
        raise OSError("the cheap checks were stopped")
    argv = [str(word) for word in argv]
    process = subprocess.Popen(argv, cwd=context.root, env=context.env, stdin=subprocess.PIPE if input is not None else
                               subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                               errors="replace", start_new_session=True)
    context.processes.add(process)
    try:
        stdout, stderr = process.communicate(input, timeout=COMMAND_SECONDS)
    except subprocess.TimeoutExpired:
        end_group(process)
        raise
    finally:
        context.processes.discard(process)
    if context.stopped:
        raise OSError("the cheap checks were stopped")
    return subprocess.CompletedProcess(argv, process.returncode, stdout, stderr)


def output_lines(result) -> list[str]:
    return [line.rstrip() for line in (result.stdout + result.stderr).splitlines() if line.strip()]


def first_difference(context: Context, path: Path) -> int | None:
    """The first line `zig fmt` would change in one file, from its formatted text on standard output."""
    try:
        source = path.read_text(errors="replace")
        formatted = run(context, [context.zig, "fmt", "--stdin"], input=source)
    except (OSError, subprocess.SubprocessError):
        return None
    if formatted.returncode != 0:
        return None
    old, new = source.splitlines(), formatted.stdout.splitlines()
    for number, (left, right) in enumerate(zip(old, new), 1):
        if left != right:
            return number
    return min(len(old), len(new)) + 1 if len(old) != len(new) else None


def zig_format(context: Context) -> list[Finding]:
    """`zig fmt --check` over build.zig's format paths; each file it names, at the first line it would change."""
    result = run(context, [context.zig, "fmt", "--check", *[context.root / path for path in ZIG_FORMAT_PATHS]])
    if result.returncode == 0:
        return []
    findings = []
    for line in output_lines(result):
        if FILE_LINE.search(line):  # a parse error: zig fmt prints file:line:column itself
            findings.append(Finding("zig-format", short(line, context.root), first_location([line], context.root)))
            continue
        path = Path(line) if os.path.isabs(line) else context.root / line
        if not path.is_file():
            continue
        number = first_difference(context, path)
        location = short(str(path), context.root) + ("" if number is None else ":%d" % number)
        findings.append(Finding("zig-format", "zig fmt would change this line" if number else "zig fmt would reformat this file",
                                location))
    return findings or [Finding("zig-format", "zig fmt --check exited %d" % result.returncode, None,
                                output_lines(result)[:MAX_LINES])]


def my_format(context: Context) -> list[Finding]:
    """`scripts/check_my_format.py`: the same file selection, one `selka fmt FILE --check` per file, run in parallel."""
    sys.path.insert(0, str(context.root / "scripts"))
    try:
        import check_my_format
    finally:
        sys.path.pop(0)
    try:
        sources, _ = check_my_format.select_sources(context.root.resolve())
    except (ValueError, OSError) as error:
        return [Finding("my_format", str(error), check_my_format.MANIFEST)]
    def one(source):
        if context.stopped:
            return source, None  # stopped: the gate is over or restarting, and decides nothing from this
        return source, check_my_format.check_source(context.compiler, source, context.root, env=context.env)

    findings = []
    workers = max(1, min(8, len(os.sched_getaffinity(0))))
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        for source, report in pool.map(one, sources):
            if report is None:
                continue
            lines = [line.rstrip() for line in report.splitlines() if line.strip()]
            findings.append(Finding("my_format", short(lines[0], context.root),
                                    first_location(lines, context.root) or source, lines[1:MAX_LINES]))
    return findings


def doc_coverage(context: Context) -> list[Finding]:
    """`selka doc-coverage .`: its failure lines, the first that names a file first."""
    result = run(context, [context.compiler, "doc-coverage", "."])
    if result.returncode == 0:
        return []
    lines = output_lines(result)
    # A failure is a `  ! <slug>: ...` line; the counts and per-page tallies around it are not.
    reported = [line.strip()[1:].strip() for line in lines if line.strip().startswith("!")]
    if not reported:
        reported = [line for line in lines if "error" in line.lower()] or lines[-1:] or [
            "selka doc-coverage exited %d" % result.returncode]
    findings = []
    for line in reported[:MAX_LINES]:
        quoted = re.search(r"'((?:docs|src)/[^']+)'", line)
        findings.append(Finding("doc-coverage", line, first_location([line], context.root)
                                or (quoted.group(1) if quoted else None)))
    return findings


def inputs_coverage(context: Context) -> list[Finding]:
    """The three commands of `test-inputs-coverage`, in build.zig's order; each failure names its action."""
    findings = []
    for action, arguments in COVERAGE_COMMANDS:
        if not (context.root / arguments[0]).is_file():
            continue
        # The action runs `python3` from PATH (build.zig's driver), not this interpreter.
        python = shutil.which("python3", path=(context.env or os.environ).get("PATH")) or "python3"
        result = run(context, [python, *arguments])
        if result.returncode == 0:
            continue
        lines = output_lines(result) or ["%s exited %d" % (" ".join(arguments), result.returncode)]
        located = [line for line in lines if FILE_LINE.search(line)]
        findings.append(Finding(action, (located or lines)[0], first_location(lines, context.root),
                                [line for line in lines if line != (located or lines)[0]][:MAX_LINES]))
    return findings


def registry(context: Context) -> list[Finding]:
    """The inventory's unregistered actions: `test-verification-registry`, a dependency of every gate root, fails
    while there is one."""
    unknown = ((context.plan or {}).get("coverage") or {}).get("unknown_actions") or []
    if not unknown:
        return []
    return [Finding("registry", "%d gate action(s) belong to no cohort; register each in build.zig or "
                    "build_verification.registerInfrastructure" % len(unknown), "build_verification.zig",
                    ["unregistered action: " + name for name in unknown[:MAX_LINES]])]


RUNNERS = {"registry": registry, "zig-format": zig_format, "coverage": inputs_coverage,
           "my_format": my_format, "doc-coverage": doc_coverage}


def applicable(plan: dict | None) -> list[str]:
    """The checks a request runs: those whose gate action the inventory registers (all of them without one)."""
    if plan is None:
        return list(CHECKS)
    registered = {group["id"] for group in plan.get("groups", [])}
    return [name for name in CHECKS if name == "registry" or set(ACTIONS[name]) & registered]


class Runner:
    """Runs a list of checks in background threads and says, when polled, whether any has a finding.

    Calling it is the `stop` that `verify_cache.run_admitted` polls: true from the first finding, so a preparation build
    still running is ended then. `killed` is set by the caller that ended a build because of it. `wait()` joins every
    check and returns the findings in CHECKS order; `seconds` holds each check's wall time from `start`.
    """

    def __init__(self, context: Context):
        self.context = context
        self.started_at = None
        self.threads: list[threading.Thread] = []
        self.results: dict[str, list[Finding]] = {}
        self.errors: dict[str, str] = {}
        self.seconds: dict[str, float] = {}
        self.first_finding_seconds = None
        self.first_finding_at = None  # time.monotonic() of the first finding
        self.lock = threading.Lock()
        self.killed = False
        self.abandoned: list[str] = []
        self.began: dict[str, float] = {}  # when each check started: its deadline counts from there
        self.on_finding = None  # called (from the check's thread) with each check's findings as they arrive

    def start(self, names) -> None:
        if self.started_at is None:
            self.started_at = time.monotonic()
        for name in names:
            if name in self.results or any(thread.name == name for thread in self.threads):
                continue
            thread = threading.Thread(target=self._run, args=(name,), name=name, daemon=True)
            self.threads.append(thread)
            self.began[name] = time.monotonic()
            thread.start()

    def _run(self, name: str) -> None:
        began = time.monotonic()
        try:
            found = RUNNERS[name](self.context)
        except (OSError, subprocess.SubprocessError, ValueError) as error:
            # A check that cannot run decides nothing; the gate action runs the command and reports it.
            found = []
            with self.lock:
                self.errors[name] = "%s: %s" % (type(error).__name__, error)
        with self.lock:
            self.results[name] = found
            self.seconds[name] = time.monotonic() - began
            if found and self.first_finding_seconds is None:
                self.first_finding_at = time.monotonic()
                self.first_finding_seconds = self.first_finding_at - self.started_at
        if found and self.on_finding is not None:
            self.on_finding(name, found)

    def __call__(self) -> bool:
        with self.lock:
            return any(self.results.values())

    def stop(self) -> None:
        """End every running check's commands and start no more: the request is over or restarting, so nothing they
        would find can count. Their threads then end on their own."""
        self.context.stopped = True
        for process in list(self.context.processes):
            end_group(process)

    def wait(self) -> list[Finding]:
        """Join the checks, each at most PHASE_SECONDS after it started. A check still running then is abandoned
        (named in `abandoned`, its thread left to end on its own command's ceiling) and decides nothing; findings of the
        checks that finished stand."""
        for thread in self.threads:
            thread.join(max(0.0, self.began[thread.name] + PHASE_SECONDS - time.monotonic()))
        with self.lock:
            self.abandoned = sorted(thread.name for thread in self.threads
                                    if thread.is_alive() and thread.name not in self.results)
        return self.findings()

    def findings(self) -> list[Finding]:
        with self.lock:
            return [finding for name in CHECKS for finding in self.results.get(name, [])]

    def report(self) -> dict:
        """The record `last-run.json` keeps of this run: each check's seconds, findings and errors."""
        with self.lock:
            return {"checks": {name: {"seconds": round(self.seconds[name], 3), "findings": len(self.results[name])}
                               for name in CHECKS if name in self.results},
                    "errors": dict(self.errors), "abandoned": list(self.abandoned),
                    "first_finding_seconds": self.first_finding_seconds,
                    "findings": [{"check": item.check, "location": item.location, "message": item.message,
                                  "lines": item.lines} for name in CHECKS for item in self.results.get(name, [])]}


def summary_lines(findings: list[Finding], limit: int) -> list[str]:
    """One `failure N/M: <action>` block per gate action, its findings each with their `file:line`, at most `limit`
    lines."""
    order = []
    for finding in findings:
        if finding.check not in order:
            order.append(finding.check)
    lines = []
    for number, check in enumerate(order, 1):
        mine = [finding for finding in findings if finding.check == check]
        lines.append("failure %d/%d: %s (a cheap check, before any test action)" % (number, len(order), check))
        for finding in mine[:4]:
            text = finding.message if not finding.location or finding.message.startswith(finding.location) \
                else "%s: %s" % (finding.location, finding.message)
            lines.append("  " + text[:400])
            lines += ["    " + line[:400] for line in finding.lines[:2]]
        if len(mine) > 4:
            lines.append("  ... and %d more findings of %s" % (len(mine) - 4, check))
    if len(lines) > limit:
        lines = lines[:limit - 1] + ["  ... more findings follow; run python3 scripts/gate_cheap_checks.py"]
    return lines


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--zig", default=os.environ.get("ZIG") or "zig")
    parser.add_argument("--compiler", type=Path, help="the compiler my_format and doc-coverage run (default: skip them)")
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args(argv)
    context = Context(root=args.root.resolve(), zig=args.zig, compiler=args.compiler, env=dict(os.environ))
    runner = Runner(context)
    runner.start([name for name in CHECKS if name != "registry" and (args.compiler or name not in COMPILER_CHECKS)])
    findings = runner.wait()
    for name, error in sorted(runner.errors.items()):
        print("cheap checks: %s could not run (%s)" % (name, error))
    if findings:
        for line in summary_lines(findings, 40):
            print(line)
        return 1
    print("cheap checks: passed (%s)" % ", ".join("%s %.1f s" % (name, runner.seconds[name]) for name in CHECKS
                                                if name in runner.seconds))
    return 0


if __name__ == "__main__":
    sys.exit(main())

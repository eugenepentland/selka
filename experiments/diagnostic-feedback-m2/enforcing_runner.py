#!/usr/bin/env python3
"""A participant runner that enforces a task-level token envelope *live*.

`budget.py` defines the contract; `m2_smoke.py` and `budget_adapter.py` demonstrate
it with a scripted model; `envelope_replay.py` models enforcement over trajectories
that were measured without any budget. This module is the missing half: it launches
a real headless participant, watches that session's harness log *while the session
runs*, and charges every model call it observes against one task-level `Envelope`.

A call whose actual generation exceeds the allowance it was given is charged what it
really generated (the tokens are spent; refusing the charge cannot un-spend them),
and that refusal ends the candidate immediately: the process group is terminated
(SIGTERM, then SIGKILL after a short grace) and the candidate is recorded as
ended-by-overshoot, never retried and never extended. The budget is also stated in
the prompt, so the participant is told the cap it is held to.

**How a stop is classified (runner version 2).** The binary `killed_by_harness`
required the participant to *die from a signal*, which no `dsh` participant can do:
`dsh --profile headless` installs `process.on("SIGTERM", () => interrupt(0))`
(`@deepseek-ai/dsh/lib/profile-boot-*.js`) and shuts down gracefully with exit
status 0. A real, effective kill was therefore indistinguishable from a session
that happened to end, and the strongest low-cap probe available classified as a
mechanism failure while the participant had in fact been stopped mid-step. The
record now carries a tri-state `stop` instead:

    signal                  the process died from the signal the harness sent;
    graceful-after-request  a stop was requested (SIGTERM), the process was gone
                            inside the grace window, and no call was charged after
                            the refusal — a SUCCESS, and the expected `dsh` shape;
    none                    no stop was requested, the process outlived the grace
                            window, or calls were still charged after the refusal.

`stop` is derived by `classify_stop` from the recorded exit, the stop request, the
reaped-after delta and the charge list, so it re-derives offline. `mechanism_failures`
fires on `stop == none` after an overshoot, on any call charged after the refusal
that does not carry the `after_overshoot` flag, on an overshoot above three times the
cap, and on a candidate that overshot yet is marked complete; a
`graceful-after-request` stop is not a failure. Records written by runner version 1
(`sha256 52018fe9…`, including the 8-session pilot and the dev-checked probe) keep
their own fields and are re-classified from them, with the shutdown latency bounded
from `finished_utc` rather than measured.

Policies (both charge ONE envelope per task, never one per candidate):

    repair       one session per task; every call it makes is charged to the task
                 envelope; an overshoot ends the task's candidate.
    independent  fresh sessions, one after another, each charging the SAME
                 envelope instance; another candidate starts only while the
                 envelope still has budget. Live, the harness cannot look ahead at
                 a call's size the way `envelope_replay.py` could over a measured
                 trajectory, so a candidate is started whenever `remaining() > 0`
                 and its first call may therefore overshoot. After the pool stops,
                 selection uses the PUBLIC check only; the hidden manifest is run
                 once, on the selected candidate, and never informs selection.

Everything the measurement needs is coordinator-side: the sealed snapshot, the
public and hidden grading of that snapshot with the frozen compiler, the per-call
charges and the raw session logs. A session whose log cannot be matched is recorded
as MISSING with no invented spend.

    python3 experiments/diagnostic-feedback-m2/enforcing_runner.py --selftest
    python3 experiments/diagnostic-feedback-m2/enforcing_runner.py --dry-run
    python3 experiments/diagnostic-feedback-m2/enforcing_runner.py --case dev-bool --policy repair --cap 5000
    python3 experiments/diagnostic-feedback-m2/enforcing_runner.py --case bool-a --policy repair --cap 5000 \
        --cohort-id m2 --evidence-root cohorts/m2 --work-root work/m2
    python3 experiments/diagnostic-feedback-m2/enforcing_runner.py --pilot --cap 5000 --session-budget 8
    python3 experiments/diagnostic-feedback-m2/enforcing_runner.py --audit cohorts/pilot-5000/dev-bool/repair/record.json
    python3 experiments/diagnostic-feedback-m2/enforcing_runner.py --reclassify cohorts/overshoot-1000/dev-checked/repair/record.json

`--cohort-id` names the cohort a record and the participant's `MYLANG_COHORT` carry; it
defaults to `pilot-5000` so every existing invocation and record is unchanged.

All scratch lives under `experiments/diagnostic-feedback-m2/.tmp/` (never `/tmp`,
which is a small tmpfs that has filled up before). Work directories are pruned and
sealed after every task, and one participant runs at a time, guarded by an on-disk
lock and a process scan.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))

import cohort  # noqa: E402
import conditions  # noqa: E402
import events  # noqa: E402
import m2_usage  # noqa: E402
from budget import Envelope, Usage  # noqa: E402

TMP = HERE / ".tmp"
WORK_ROOT = HERE / "work" / "pilot-5000"
EVIDENCE_ROOT = HERE / "cohorts" / "pilot-5000"
CASES = HERE / "cases"
LOCK = TMP / "active-participant.lock"

ARM = "text"
POLICIES = ("repair", "independent")
DEFAULT_CAP = 5000
DEFAULT_SESSION_BUDGET = 8
DEFAULT_MAX_CANDIDATES = 5
DEFAULT_POLL_SECONDS = 2.0
DEFAULT_GRACE_SECONDS = 5.0
DEFAULT_SESSION_DEADLINE = 900.0
INVOCATION_LIMIT = 20
SETTLE_SECONDS = 3.0
# One call that overshoots is expected: the kill happens after that call's usage
# line is written. A mechanism failure is spend that keeps arriving after the kill,
# a single call over three times the whole cap, or an overshoot with no termination.
MECHANISM_OVERSHOOT_FACTOR = 3
MECHANISM_LATE_CALLS = 1          # runner v1 tolerance, kept only to re-audit v1 records
RUNNER_VERSION = 2
LEGACY_RUNNER_SHA256 = "52018fe9c5197cecf67332bdf159bc560d55a15af4659236772886665aa4c955"
STOP_SIGNAL = "signal"
STOP_GRACEFUL = "graceful-after-request"
STOP_NONE = "none"
STOP_STATES = (STOP_SIGNAL, STOP_GRACEFUL, STOP_NONE)

PILOT_ORDER = (
    ("dev-bool", "repair"),
    ("dev-bool", "independent"),
    ("dev-checked", "repair"),
    ("dev-checked", "independent"),
    ("dev-generic", "repair"),
    ("dev-generic", "independent"),
    ("dev-variant", "repair"),
    ("dev-variant", "independent"),
)

PROMPT = """# Fix the program

{request}

You are working in `project/`. `bin/mylang` is the installed compiler:
`bin/mylang check project/main.my`, `bin/mylang run project/main.my -- <arguments>`.

The same behavior is required for every input, not only the examples in `public/`.
Read `public/expected.json` for the examples this task will be checked against, and run them however you like.

Constraints:

- Work only inside this directory; do not read or write anything outside it and do not spawn subagents.
- At most {limit} compiler invocations are available for this attempt.
- You have {cap} generated (output) tokens for this task, reasoning included; the harness reads this session's log while it runs and terminates the attempt as soon as that budget is exceeded.
- Change only what the request requires.

When you are done, reply with a short final message: what you changed and the exact command you ran with its result.
"""


# --------------------------------------------------------------------------
# small helpers


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_text(text: str) -> str:
    return sha256_bytes(text.encode())


def sha256_path(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def load_module(name: str, path: Path):
    """Load a sibling module under its own name; several modules here are `run.py`."""
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


# `run.py` is the M1 runner, unchanged: it owns the working-copy layout, the
# prompt template, staging and the grading step. Importing it also imports
# `experiments/cascade/run.py` as `runlib` (the frozen compiler path and the
# headless launcher template), which is why the import order here matters.
m2_run = load_module("m2_run", HERE / "run.py")
runlib = m2_run.runlib
# run.py inserted the cascade directory at the front of sys.path; drop it again so
# a later import here cannot silently resolve to a cascade module of the same name.
sys.path[:] = [entry for entry in sys.path if entry != str(REPO / "experiments" / "cascade")]


def validate_cap(cap: int) -> int:
    """A non-positive cap is a usage error, not an empty budget."""
    if not isinstance(cap, int) or cap <= 0:
        raise SystemExit(f"enforcing_runner: --cap must be a positive integer, got {cap!r}")
    return cap


def prompt_text(case: str, cap: int) -> str:
    """The M1 treatment prompt plus the budget statement, verbatim and frozen."""
    request = (m2_run.case_directory(case) / "request.md").read_text().split("\n", 1)[-1].strip()
    return PROMPT.format(request=request, limit=INVOCATION_LIMIT, cap=cap)


# --------------------------------------------------------------------------
# the live watcher


def call_key(meta: dict) -> str:
    """Identity of one model call: its session log and its position in that log."""
    return f"{meta['session']}#{meta['index']}"


class SessionWatcher:
    """Charge the calls of one growing session log, exactly once each.

    Every poll re-decompresses the whole log through `m2_usage.read_calls` (the
    verified reader: same `cwd` match, same start-time slack, torn final frames
    skipped and counted) and charges the calls whose `(session, index)` key has not
    been seen. Each new call receives `allowance = envelope.remaining()` at the
    moment it is charged, which is the live form of the replay's allowance.

    A refusal ends the candidate, but a call already written to the log after it is
    real spend too, so it is charged as well and flagged `after_overshoot`; the
    envelope's `spent` therefore always equals what was actually generated, and no
    charge is ever dropped.
    """

    def __init__(self, envelope: Envelope, work_dir: Path, started_utc: str, label: str,
                 root: Path = m2_usage.SESSION_ROOT, reader=None):
        self.envelope = envelope
        self.work_dir = Path(work_dir)
        self.started_utc = started_utc
        self.label = label
        self.root = Path(root)
        self.reader = reader or (lambda work_dir, since, root: m2_usage.read_calls(work_dir, since, root=root))
        self.seen: set[str] = set()
        self.charges: list[dict] = []
        self.reads = 0
        self.repeat_observations = 0
        self.last_read: dict = {"matched": False, "sessions": [], "calls": [], "call_meta": [],
                                "malformed_lines": 0, "generated": 0}
        self.settle_reads = 0

    def poll(self) -> tuple[list[dict], bool]:
        """One read; returns the newly charged entries and whether one refused."""
        read = self.reader(self.work_dir, self.started_utc, self.root)
        self.reads += 1
        self.last_read = read
        new: list[dict] = []
        refused = False
        for call, meta in zip(read.get("calls", []), read.get("call_meta", [])):
            key = call_key(meta)
            if key in self.seen:
                self.repeat_observations += 1
                continue
            self.seen.add(key)
            allowance = self.envelope.remaining()
            entry = self.envelope.charge(call, label=self.label, allowance=allowance)
            entry = {**entry, "key": key, "call": dict(meta), "observed_utc": now_iso(),
                     "after_overshoot": refused}
            self.charges.append(entry)
            new.append(entry)
            if entry["refused"]:
                refused = True
        return new, refused

    def settle(self, seconds: float = SETTLE_SECONDS, interval: float = 0.25) -> list[dict]:
        """Keep reading after the process stopped, until the log stops growing."""
        deadline = time.monotonic() + seconds
        late: list[dict] = []
        while time.monotonic() < deadline:
            new, _ = self.poll()
            self.settle_reads += 1
            if not new:
                break
            late.extend(new)
        return late

    def missing_note(self) -> str | None:
        """A session whose log never matched is MISSING, never zero spend."""
        if self.last_read.get("matched"):
            return None
        return (f"no session log matched work dir {self.work_dir} since {self.started_utc}; "
                "spend is MISSING, not zero")


# --------------------------------------------------------------------------
# process control


class ParticipantLock:
    """One participant at a time: an in-process claim plus an on-disk PID lock."""

    HELD: set = set()

    def __init__(self, path: Path = LOCK):
        self.path = Path(path)
        self.held = False

    def acquire(self) -> None:
        if self.held or self.path in ParticipantLock.HELD:
            raise SystemExit("enforcing_runner: refusing to start a second participant (lock already held)")
        self.path.parent.mkdir(parents=True, exist_ok=True)
        if self.path.is_file():
            try:
                other = int(self.path.read_text().strip() or "0")
            except ValueError:
                other = 0
            if other and other != os.getpid() and Path(f"/proc/{other}").exists():
                raise SystemExit(f"enforcing_runner: participant pid {other} is still running; "
                                 "refusing to start another")
        self.path.write_text(str(os.getpid()) + "\n")
        ParticipantLock.HELD.add(self.path)
        self.held = True

    def release(self) -> None:
        if self.held:
            try:
                self.path.unlink()
            except OSError:
                pass
            ParticipantLock.HELD.discard(self.path)
            self.held = False


def other_participant_running(work_marker: str = "pilot-5000") -> list[str]:
    """Other live participants for this experiment, found by their working directory.

    The marker is in the participant's cwd, not in its argv (the argv carries the
    prompt), so the process's `/proc/<pid>/cwd` is what is inspected.
    """
    hits = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit() or int(entry.name) == os.getpid():
            continue
        try:
            cmdline = (entry / "cmdline").read_bytes().decode(errors="replace").replace("\x00", " ")
            cwd = os.readlink(entry / "cwd")
        except OSError:
            continue
        if "dsh" in cmdline and work_marker in cwd:
            hits.append(f"{entry.name}: cwd={cwd} :: {cmdline[:120]}")
    return hits


def terminate(process: subprocess.Popen, grace: float) -> str:
    """SIGTERM the participant's process group, SIGKILL it after `grace`."""
    sent = ""
    try:
        os.killpg(os.getpgid(process.pid), signal.SIGTERM)
        sent = "SIGTERM"
    except (ProcessLookupError, PermissionError, OSError):
        try:
            process.terminate()
            sent = "SIGTERM"
        except OSError:
            pass
    deadline = time.monotonic() + grace
    while time.monotonic() < deadline:
        if process.poll() is not None:
            return sent
        time.sleep(0.1)
    try:
        os.killpg(os.getpgid(process.pid), signal.SIGKILL)
        sent = "SIGKILL"
    except (ProcessLookupError, PermissionError, OSError):
        try:
            process.kill()
            sent = "SIGKILL"
        except OSError:
            pass
    return sent


def signal_name(exit_code: int | None) -> str:
    if exit_code is None or exit_code >= 0:
        return ""
    try:
        return signal.Signals(-exit_code).name
    except ValueError:
        return f"signal {-exit_code}"


# --------------------------------------------------------------------------
# how the participant stopped (tri-state, runner v2)


def parse_iso(value) -> float | None:
    """Seconds since the epoch for an ISO timestamp, or None when unusable."""
    try:
        moment = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return moment.timestamp()


def stop_latency(candidate: dict) -> tuple[float | None, str]:
    """Seconds from the stop request to the process being reaped, and its source.

    A v2 record measures it. A v1 record (runner `52018fe9…`) did not, so it is
    bounded instead: `finished_utc` is written after the reap and the refusal charge
    was observed at or before the stop request, so `finished_utc - refusal observed`
    is an upper bound on the shutdown latency. A bound that fits inside the grace
    window proves the latency did too; a bound that does not fit proves nothing.
    """
    measured = candidate.get("reaped_after_request_seconds")
    if isinstance(measured, (int, float)):
        return float(measured), "measured"
    refusal = next((charge for charge in candidate.get("charges") or [] if charge.get("refused")), None)
    if refusal is None or not candidate.get("kill_signal_sent"):
        return None, "no stop was requested"
    finished = parse_iso(candidate.get("finished_utc"))
    observed = parse_iso(refusal.get("observed_utc"))
    if finished is None or observed is None:
        return None, "not recorded"
    return max(0.0, finished - observed), "upper bound: finished_utc - refusal observed_utc"


def classify_stop(candidate: dict) -> dict:
    """The tri-state stop verdict, re-derivable from a record alone.

    `signal` needs the process to have died from the signal; `graceful-after-request`
    needs a request, a reap inside the grace window and no call charged after the
    refusal; everything else is `none`. A participant that traps SIGTERM and exits 0
    — `dsh --profile headless` does exactly that — is a successful
    `graceful-after-request`, not a failure to stop.
    """
    requested = bool(candidate.get("stop_requested", bool(candidate.get("kill_signal_sent"))))
    signal_exit = candidate.get("exit_signal") in ("SIGTERM", "SIGKILL")
    grace = candidate.get("grace_seconds", DEFAULT_GRACE_SECONDS)
    late = int(candidate.get("late_calls_after_stop") or 0)
    latency, source = stop_latency(candidate)
    verdict = {"requested": requested, "exit": candidate.get("exit"),
               "exit_signal": candidate.get("exit_signal") or "",
               "kill_signal_sent": candidate.get("kill_signal_sent") or "",
               "reaped_after_request_seconds": None if latency is None else round(latency, 3),
               "latency_source": source, "late_calls_after_stop": late}
    if requested and signal_exit:
        verdict.update({"stop": STOP_SIGNAL, "why": "the process died from the signal the harness sent"})
    elif not requested:
        verdict.update({"stop": STOP_NONE, "why": "no stop was requested before the process ended"})
    elif latency is None:
        verdict.update({"stop": STOP_NONE, "why": "the shutdown latency was not recorded"})
    elif latency > grace:
        verdict.update({"stop": STOP_NONE,
                        "why": f"the process outlived the {grace}s grace window (latency {latency:.3f}s)"})
    elif late:
        verdict.update({"stop": STOP_NONE,
                        "why": f"{late} call(s) were charged after the refusal, so generation continued"})
    else:
        verdict.update({"stop": STOP_GRACEFUL,
                        "why": (f"SIGTERM was sent and the process was gone within {latency:.3f}s "
                                f"({source}) with no call charged after the refusal")})
    return verdict


def unflagged_after_refusal(candidate: dict) -> int:
    """Calls charged after the refusal that do not carry the `after_overshoot` flag.

    `after_overshoot` is set from refusals seen *within one poll*, so a call charged
    in a later poll (the settle read after the process stopped) can be real spend
    that arrived after the refusal without being flagged. That is a mechanism
    failure: spend that continued after the stop is not allowed to look ordinary.
    """
    count = 0
    refused_seen = False
    for charge in candidate.get("charges") or []:
        if refused_seen and not charge.get("after_overshoot"):
            count += 1
        if charge.get("refused"):
            refused_seen = True
    return count


# --------------------------------------------------------------------------
# grading


def public_only(case: str, snapshot: Path) -> dict:
    """The public half of `run.py`'s grade(), so selection never runs hidden checks."""
    checks = m2_run.public_checks(case)
    failures = []
    for check in checks:
        completed = subprocess.run(
            [str(runlib.COMPILER), "run", str(snapshot / "main.my"), "--", *check.get("args", [])],
            capture_output=True, text=True, cwd=snapshot,
        )
        if completed.returncode != 0 or completed.stdout != check["stdout"]:
            failures.append({"args": check.get("args", []), "exit": completed.returncode,
                             "expected": check["stdout"], "actual": completed.stdout})
    return {"public_acceptance": not failures and bool(checks), "public_failures": failures}


def with_cache_env(directory: Path, action, *args, **kwargs):
    """Run `action` with the Zig caches pinned inside `directory` (never the repo)."""
    keys = ("ZIG_GLOBAL_CACHE_DIR", "ZIG_LOCAL_CACHE_DIR", "PYTHONDONTWRITEBYTECODE")
    saved = {key: os.environ.get(key) for key in keys}
    os.environ["ZIG_GLOBAL_CACHE_DIR"] = str(directory / ".cache" / "zig-global")
    os.environ["ZIG_LOCAL_CACHE_DIR"] = str(directory / ".cache" / "zig-local")
    os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
    try:
        return action(*args, **kwargs)
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def copy_for_grading(sealed: Path, grading_root: Path) -> Path:
    """Grade a copy, so the sealed evidence stays byte-identical to what was hashed."""
    if grading_root.exists():
        shutil.rmtree(grading_root)
    grading_root.mkdir(parents=True)
    graded = grading_root / "sealed"
    shutil.copytree(sealed, graded)
    return graded


class RealGrader:
    """Public grading per candidate; the module's full grading path for the selection."""

    def __init__(self):
        self.public_calls = 0
        self.hidden_calls: list[str] = []
        self.phase = "selecting"

    def public(self, case: str, grading_root: Path, sealed: Path, label: str) -> dict:
        graded = copy_for_grading(sealed, grading_root)
        self.public_calls += 1
        return with_cache_env(grading_root, public_only, case, graded)

    def hidden(self, case: str, grading_root: Path, sealed: Path, label: str) -> dict:
        """`run.py`'s own grading step, on a copy, after selection is already fixed."""
        graded = copy_for_grading(sealed, grading_root)
        self.hidden_calls.append(label)
        return with_cache_env(grading_root, m2_run.grade, grading_root, case, graded)

    def hidden_manifest(self, case: str) -> bool:
        return (m2_run.case_directory(case) / "hidden" / "verify.json").is_file()


class ScriptedGrader:
    """A stand-in grader for the dry run: reads `project/.answer`, counts hidden runs."""

    def __init__(self):
        self.public_calls = 0
        self.calls: list[dict] = []
        self.phase = "selecting"

    @staticmethod
    def _answer(sealed: Path) -> str:
        marker = sealed / ".answer"
        return marker.read_text().strip() if marker.is_file() else ""

    def public(self, case: str, grading_root: Path, sealed: Path, label: str) -> dict:
        self.public_calls += 1
        text = self._answer(sealed)
        self.calls.append({"phase": self.phase, "kind": "public", "label": label, "answer": text})
        passes = "public-pass" in text
        return {"public_acceptance": passes,
                "public_failures": [] if passes else [{"args": [], "exit": 1, "expected": "public-pass",
                                                       "actual": text}]}

    def hidden(self, case: str, grading_root: Path, sealed: Path, label: str) -> dict:
        text = self._answer(sealed)
        self.calls.append({"phase": self.phase, "kind": "hidden", "label": label, "answer": text})
        return {"public_acceptance": "public-pass" in text, "public_failures": [],
                "hidden_acceptance": "hidden-pass" in text, "grader_ok": True, "hidden_steps": []}

    def hidden_manifest(self, case: str) -> bool:
        return True


# --------------------------------------------------------------------------
# one participant session, watched


def build_work_dir(case: str, policy: str, index: int, work_root: Path, prompt: str) -> tuple[Path, str]:
    """The working copy `run.py` builds, with the budget-bearing prompt in it."""
    source = m2_run.case_directory(case)
    directory = (work_root / case / policy / str(index)).resolve()
    if directory.exists():
        shutil.rmtree(directory)
    shutil.copytree(source / "project", directory / "project")
    if (source / "public").is_dir():
        shutil.copytree(source / "public", directory / "public")
    conditions.install(directory / "bin", ARM)
    (directory / "request.md").write_text((source / "request.md").read_text())
    (directory / "PROMPT.md").write_text(prompt)
    initial, _ = events.inventory(directory / "project")
    return directory, initial


def session_environment(work_dir: Path, event_log: Path, cohort_id: str, attempt_id: str,
                        initial: str) -> dict:
    """The per-run environment: Zig caches pinned inside the working copy, as M1."""
    environment = dict(os.environ)
    environment["ZIG_GLOBAL_CACHE_DIR"] = str(work_dir / ".cache" / "zig-global")
    environment["ZIG_LOCAL_CACHE_DIR"] = str(work_dir / ".cache" / "zig-local")
    environment["MYLANG_EVENT_LOG"] = str(event_log)
    environment["MYLANG_PROJECT"] = str(work_dir / "project")
    environment["MYLANG_LIMIT"] = str(INVOCATION_LIMIT)
    environment["MYLANG_COHORT"] = cohort_id
    environment["MYLANG_ATTEMPT"] = attempt_id
    environment["MYLANG_INITIAL_HASH"] = initial
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    return environment


def run_participant(case: str, policy: str, index: int, options: "Options", envelope: Envelope,
                    prompt: str) -> dict:
    """Launch one participant and watch it until it stops or overshoots."""
    cohort_id = options.cohort_id
    directory, initial = build_work_dir(case, policy, index, options.work_root, prompt)
    destination = options.evidence_root / case / policy
    destination.mkdir(parents=True, exist_ok=True)
    label = f"{policy}-{index}"
    command = options.build_command(directory, index, prompt, case, policy)
    event_log = directory / ".events" / "events.jsonl"
    environment = session_environment(directory, event_log, cohort_id, f"{policy}/{case}/{index}", initial)
    started = now_iso()
    started_monotonic = time.monotonic()
    stdout_path = destination / f"{label}.stdout.txt"
    stderr_path = destination / f"{label}.stderr.txt"
    watcher = SessionWatcher(envelope, directory, started, label, root=options.session_root)
    record: dict = {
        "label": label,
        "index": index,
        "policy": policy,
        "work_dir": str(directory),
        "initial_source_sha256": initial,
        "started_utc": started,
        "command": [("<PROMPT>" if part == prompt else part) for part in command],
        "env": {key: environment[key] for key in ("ZIG_GLOBAL_CACHE_DIR", "ZIG_LOCAL_CACHE_DIR",
                                                  "MYLANG_LIMIT", "MYLANG_ATTEMPT")},
        "poll_seconds": options.poll_seconds,
    }
    timed_out = False
    kill_signal = ""
    refused = False
    stop_requested_utc = ""
    request_monotonic: float | None = None
    with stdout_path.open("wb") as out, stderr_path.open("wb") as err:
        process = subprocess.Popen(command, cwd=directory, stdout=out, stderr=err,
                                   stdin=subprocess.DEVNULL, env=environment, start_new_session=True)
        deadline = started_monotonic + options.session_deadline
        while True:
            code = process.poll()
            _, refused_now = watcher.poll()
            refused = refused or refused_now
            if code is not None:
                break
            if refused:
                request_monotonic = time.monotonic()
                stop_requested_utc = now_iso()
                kill_signal = terminate(process, options.grace_seconds)
                break
            if time.monotonic() >= deadline:
                timed_out = True
                request_monotonic = time.monotonic()
                stop_requested_utc = now_iso()
                kill_signal = terminate(process, options.grace_seconds)
                break
            time.sleep(options.poll_seconds)
        if process.poll() is None:
            request_monotonic = request_monotonic or time.monotonic()
            stop_requested_utc = stop_requested_utc or now_iso()
            kill_signal = kill_signal or terminate(process, options.grace_seconds)
        exit_code = process.wait()
        reaped_monotonic = time.monotonic()
    charged_before_settle = len(watcher.charges)
    late = watcher.settle()
    finished = now_iso()
    exit_signal = signal_name(exit_code)
    ended_by_overshoot = any(charge["refused"] for charge in watcher.charges)
    charged = sum(charge["charged"] for charge in watcher.charges)
    overshoot = sum(charge["overshoot"] for charge in watcher.charges)
    read = watcher.last_read
    record.update({
        "finished_utc": finished,
        "wall_seconds": round(time.monotonic() - started_monotonic, 3),
        "exit": exit_code,
        "exit_signal": exit_signal,
        "timed_out": timed_out,
        "stop_requested": request_monotonic is not None,
        "stop_requested_utc": stop_requested_utc,
        "reaped_after_request_seconds": (None if request_monotonic is None
                                         else round(reaped_monotonic - request_monotonic, 3)),
        "grace_seconds": options.grace_seconds,
        "kill_signal_sent": kill_signal,
        "ended_by_overshoot": ended_by_overshoot,
        "overshoot": overshoot,
        "complete": not ended_by_overshoot and not timed_out,
        "calls_charged": len(watcher.charges),
        "charged": charged,
        "input_volume": sum(charge["usage"]["input_volume"] for charge in watcher.charges),
        "charges": watcher.charges,
        "calls_charged_before_settle": charged_before_settle,
        "late_calls_after_stop": len(late),
        "late_call_keys": [entry["key"] for entry in late],
        "watcher_reads": watcher.reads,
        "settle_reads": watcher.settle_reads,
        "repeat_observations": watcher.repeat_observations,
        "log_matched": bool(read.get("matched")),
        "sessions": read.get("sessions", []),
        "session_paths": [session["path"] for session in read.get("sessions", [])],
        "raw_session_logs": [session["path"] for session in read.get("sessions", [])],
        "malformed_lines": read.get("malformed_lines", 0),
        "session_generated": read.get("generated", 0),
        "missing": watcher.missing_note(),
        "session_stdout": stdout_path.name,
        "session_stderr": stderr_path.name,
        "events_log": str(event_log),
        "public_acceptance": None,
        "hidden_acceptance": None,
        "sealed_source_sha256": None,
    })
    # The stop verdict is part of the record, derived from what was just measured,
    # so a reader never has to re-infer it (and `--audit` can re-derive it anyway).
    verdict = classify_stop(record)
    record["stop"] = verdict["stop"]
    record["stop_why"] = verdict["why"]
    record["stop_latency_source"] = verdict["latency_source"]
    record["mechanism_failures"] = mechanism_failures(record, envelope.cap)
    return record


def mechanism_failures(candidate: dict, cap: int) -> list[str]:
    """Enforcement that demonstrably did not hold: the pilot stops on any of these.

    A `graceful-after-request` stop is a success: `dsh` traps SIGTERM and exits 0, so
    requiring a signal exit would report an effective kill as a failure.
    """
    problems = []
    stop = classify_stop(candidate)["stop"]
    if candidate.get("ended_by_overshoot") and stop == STOP_NONE:
        problems.append("an overshooting call was charged but the participant was not stopped by the harness")
    unflagged = unflagged_after_refusal(candidate)
    if unflagged:
        problems.append(f"{unflagged} call(s) were charged after the refusal without the after_overshoot flag")
    if candidate.get("overshoot", 0) > MECHANISM_OVERSHOOT_FACTOR * cap:
        problems.append(f"overshoot {candidate['overshoot']} exceeds {MECHANISM_OVERSHOOT_FACTOR}x the cap")
    if candidate.get("ended_by_overshoot") and candidate.get("complete"):
        problems.append("a candidate that overshot is marked complete")
    return problems


def legacy_mechanism_failures(candidate: dict, cap: int) -> list[str]:
    """The rule runner v1 (`52018fe9…`) applied, so its records stay auditable."""
    problems = []
    if candidate.get("ended_by_overshoot") and not candidate.get("killed_by_harness"):
        problems.append("an overshooting call was charged but the participant was not terminated by the harness")
    if candidate.get("late_calls_after_stop", 0) > MECHANISM_LATE_CALLS:
        problems.append(f"{candidate['late_calls_after_stop']} calls were written after termination")
    if candidate.get("overshoot", 0) > MECHANISM_OVERSHOOT_FACTOR * cap:
        problems.append(f"overshoot {candidate['overshoot']} exceeds {MECHANISM_OVERSHOOT_FACTOR}x the cap")
    if candidate.get("ended_by_overshoot") and candidate.get("complete"):
        problems.append("a candidate that overshot is marked complete")
    return problems


def recorded_rule(record: dict):
    """The mechanism-failure rule of the runner that produced a record."""
    return legacy_mechanism_failures if record.get("runner_sha256") == LEGACY_RUNNER_SHA256 else mechanism_failures


# --------------------------------------------------------------------------
# one task under one policy


@dataclass
class Options:
    """Everything one invocation of the runner needs, production or dry run."""
    cap: int
    work_root: Path = WORK_ROOT
    evidence_root: Path = EVIDENCE_ROOT
    session_root: Path = m2_usage.SESSION_ROOT
    cohort_id: str = "pilot-5000"
    poll_seconds: float = DEFAULT_POLL_SECONDS
    grace_seconds: float = DEFAULT_GRACE_SECONDS
    session_deadline: float = DEFAULT_SESSION_DEADLINE
    max_candidates: int = DEFAULT_MAX_CANDIDATES
    sessions_allowed: int = 0          # 0 means "as many as max_candidates"
    keep_work: bool = False
    dry_run: bool = False
    build_command: object = None
    grader: object = None
    lock: ParticipantLock = field(default_factory=ParticipantLock)

    def __post_init__(self):
        if self.build_command is None:
            def build(work_dir: Path, index: int, prompt: str, case: str, policy: str) -> list[str]:
                return [part.replace("{prompt}", prompt).replace("{turn_cap}", "30")
                        for part in runlib.launcher("dsh")]
            self.build_command = build
        if self.grader is None:
            self.grader = RealGrader()


def next_candidate_allowed(envelope: Envelope, started: int, max_candidates: int,
                           sessions_allowed: int) -> tuple[bool, str]:
    """The live start rule: only the envelope and the pool bound decide."""
    if started >= sessions_allowed:
        return False, "session-budget"
    if started >= max_candidates:
        return False, "candidate-pool-exhausted"
    if envelope.remaining() <= 0:
        return False, "envelope-exhausted"
    return True, ""


def select_candidate(candidates: list[dict]) -> tuple[dict | None, str, str]:
    """A complete candidate that passed the public check, else the last complete one."""
    complete = [candidate for candidate in candidates if candidate.get("complete")]
    passing = next((candidate for candidate in complete if candidate.get("public_acceptance")), None)
    if passing is not None:
        return passing, "public", f"{passing['label']} is complete and passes the public examples"
    if complete:
        return complete[-1], "last-complete", f"{complete[-1]['label']} is the last complete candidate"
    return None, "", "no complete candidate"


def grade_and_seal(case: str, policy: str, candidate: dict, options: Options) -> None:
    """Seal the candidate's source, grade it publicly, and copy the raw logs."""
    destination = options.evidence_root / case / policy
    label = candidate["label"]
    work_dir = Path(candidate["work_dir"])
    sealed = destination / "sealed" / label
    sealed.parent.mkdir(parents=True, exist_ok=True)
    if sealed.exists():
        shutil.rmtree(sealed)
    if (work_dir / "project").is_dir():
        candidate["sealed_source_sha256"] = cohort.seal(work_dir / "project", sealed)
    else:
        candidate["sealed_source_sha256"] = None
        candidate["missing"] = (candidate.get("missing") or "") + " sealed snapshot missing: no project dir"
    grading_root = TMP / "grading" / case / policy / label
    verdict = options.grader.public(case, grading_root, sealed, label)
    candidate["public_acceptance"] = bool(verdict.get("public_acceptance"))
    candidate["public_failures"] = verdict.get("public_failures", [])
    candidate["grading_root"] = str(grading_root)
    log_dir = destination / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    copied = []
    for session in candidate.get("sessions", []):
        source = Path(session["path"])
        if source.is_file():
            target = log_dir / f"{label}-{source.parent.name}"
            if source.name.endswith(".zstd"):
                target = target.with_name(target.name + ".zstd")
            shutil.copy2(source, target)
            copied.append(str(target))
        else:
            candidate["missing"] = (candidate.get("missing") or "") + f" session log vanished: {source}"
    candidate["raw_session_log_copies"] = copied
    events_log = Path(candidate.get("events_log", ""))
    if events_log.is_file():
        target = destination / f"{label}.events.jsonl"
        shutil.copy2(events_log, target)
        candidate["events_copy"] = str(target)


def publish(case: str, policy: str, envelope: Envelope, candidates: list[dict], options: Options,
            prompt: str, prompt_sha: str, started_utc: str, started_monotonic: float,
            stop_reason: str, grader) -> dict:
    """Choose the candidate publicly, grade the selection, write the task record."""
    destination = options.evidence_root / case / policy
    selected, mode, why = select_candidate(candidates)
    hidden_supplied = bool(grader.hidden_manifest(case))
    grader.phase = "grading"
    if selected is not None and hidden_supplied:
        verdict = grader.hidden(case, Path(selected["grading_root"]), destination / "sealed" / selected["label"],
                                selected["label"])
        selected["hidden_acceptance"] = verdict.get("hidden_acceptance")
        selected["hidden_steps"] = verdict.get("hidden_steps", [])
        selected["grader_ok"] = verdict.get("grader_ok", True)
        selected["hidden_source"] = "run.py grading path on a copy of the sealed snapshot"
    elif selected is not None:
        selected["hidden_source"] = "no hidden manifest for this case"
    record = {
        "version": 2,
        "runner": "enforcing_runner.py",
        "runner_version": RUNNER_VERSION,
        "runner_sha256": sha256_path(Path(__file__)),
        "stop_schema": "tri-state-v1 (signal | graceful-after-request | none)",
        "case": case,
        "policy": policy,
        "cap": envelope.cap,
        "cohort_id": options.cohort_id,
        "arm": ARM,
        "prompt_sha256": prompt_sha,
        "prompt_path": "prompt.md",
        "identity": {
            "case": case,
            "policy": policy,
            "cap": envelope.cap,
            "prompt_sha256": prompt_sha,
            "arm": ARM,
            "model": "deepseek-v4-flash",
            "reasoning_effort": "max",
            "invocation_limit": INVOCATION_LIMIT,
            "session_deadline_s": options.session_deadline,
            "cache_policy": "ZIG_GLOBAL_CACHE_DIR and ZIG_LOCAL_CACHE_DIR per candidate inside the working copy",
            "cap_unit": "generated (output) tokens, reasoning included once",
            "enforcement": ("live: the session log is polled every %.2fs and an overshoot terminates "
                            "the process group" % options.poll_seconds),
            "stop_classification": ("tri-state: signal (died from the signal), graceful-after-request "
                                    "(SIGTERM sent, gone inside the grace window, no call charged after "
                                    "the refusal), none (not stopped). `dsh --profile headless` traps "
                                    "SIGTERM and exits 0, so an effective stop is normally graceful."),
            "selection_rule": "public check only; the hidden manifest runs once, after selection",
        },
        "totals": envelope.totals(),
        "calls_charged": len(envelope.charges),
        # Every charge the envelope recorded, with the watcher's own provenance on
        # top of the budget contract's fields (label/requested/charged/allowance/
        # overshoot/refused/usage).
        "charges": [charge for candidate in candidates for charge in candidate.get("charges", [])],
        "candidates": candidates,
        "selected": None if selected is None else {
            "label": selected["label"],
            "mode": mode,
            "why": why,
            "public_acceptance": selected["public_acceptance"],
            "hidden_acceptance": selected.get("hidden_acceptance"),
            "complete": selected["complete"],
            "sealed_source_sha256": selected.get("sealed_source_sha256"),
        },
        "selection_mode": mode,
        "selection_reason": why,
        "public_acceptance": bool(selected and selected.get("public_acceptance")),
        "hidden_acceptance": None if selected is None else selected.get("hidden_acceptance"),
        "hidden_manifest_supplied": hidden_supplied,
        "candidates_started": len(candidates),
        "stop_reason": stop_reason,
        "session_budget": {"sessions_this_task": len(candidates), "max_candidates": options.max_candidates,
                           "sessions_allowed": options.sessions_allowed or options.max_candidates},
        "started_utc": started_utc,
        "finished_utc": now_iso(),
        "wall_seconds": round(time.monotonic() - started_monotonic, 3),
        "session_paths": [path for candidate in candidates for path in candidate.get("session_paths", [])],
        "raw_session_logs": [path for candidate in candidates for path in candidate.get("raw_session_logs", [])],
        "missing": [{"candidate": candidate["label"], "note": candidate["missing"]}
                    for candidate in candidates if candidate.get("missing")],
        "mechanism_failures": [{"candidate": candidate["label"], "problems": candidate["mechanism_failures"]}
                               for candidate in candidates if candidate.get("mechanism_failures")],
    }
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "prompt.md").write_text(prompt)
    (destination / "identity.json").write_text(json.dumps({
        "case": case, "policy": policy, "cap": envelope.cap, "prompt_sha256": prompt_sha,
        "prompt": prompt, "frozen_utc": now_iso(),
    }, indent=2) + "\n")
    (destination / "record.json").write_text(json.dumps(record, indent=2) + "\n")
    return record


def run_task(case: str, policy: str, options: Options) -> dict:
    """One task under one policy on ONE task-level envelope."""
    if policy not in POLICIES:
        raise SystemExit(f"enforcing_runner: unknown policy {policy!r}; expected one of {', '.join(POLICIES)}")
    validate_cap(options.cap)
    destination = options.evidence_root / case / policy
    if (destination / "record.json").exists():
        raise SystemExit(f"enforcing_runner: {case}/{policy} already has a record; "
                         "a retry is a new cohort, never an overwrite")
    prompt = prompt_text(case, options.cap)
    prompt_sha = sha256_text(prompt)
    envelope = Envelope(options.cap)
    started_utc = now_iso()
    started_monotonic = time.monotonic()
    candidates: list[dict] = []
    sessions_allowed = options.sessions_allowed or options.max_candidates
    stop_reason = ""
    while True:
        allowed, reason = next_candidate_allowed(envelope, len(candidates), options.max_candidates, sessions_allowed)
        if not allowed:
            stop_reason = reason
            break
        options.lock.acquire()
        try:
            candidate = run_participant(case, policy, len(candidates) + 1, options, envelope, prompt)
        finally:
            options.lock.release()
        grade_and_seal(case, policy, candidate, options)
        candidates.append(candidate)
        if policy == "repair":
            stop_reason = "repair-single-session"
            break
        if candidate["ended_by_overshoot"]:
            stop_reason = "overshoot"
            break
    record = publish(case, policy, envelope, candidates, options, prompt, prompt_sha,
                     started_utc, started_monotonic, stop_reason, options.grader)
    for candidate in candidates:
        work_dir = Path(candidate["work_dir"])
        if work_dir.exists() and not options.keep_work:
            runlib.prune_caches(work_dir)
            shutil.rmtree(work_dir, ignore_errors=True)
            candidate["work_dir_pruned"] = True
        else:
            candidate["work_dir_pruned"] = False
    record["candidates"] = candidates
    (destination / "record.json").write_text(json.dumps(record, indent=2) + "\n")
    return record


# --------------------------------------------------------------------------
# selftest


def selftest() -> tuple[int, int, list[str]]:
    """Deterministic checks of the accounting, the guard rails and the kill path."""
    checks: list[tuple[str, bool, str]] = []
    scratch = TMP / "selftest"
    shutil.rmtree(scratch, ignore_errors=True)
    scratch.mkdir(parents=True)

    def check(name: str, condition: bool, detail: str = "") -> None:
        checks.append((name, bool(condition), detail))
        print(f"  {'ok  ' if condition else 'FAIL'} {name}{'' if condition else '  ' + detail}")

    # 1. a non-positive cap is refused
    refused_caps = []
    for bad in (0, -1, -5000):
        try:
            validate_cap(bad)
        except SystemExit:
            refused_caps.append(bad)
    check("a cap that is not positive is refused", refused_caps == [0, -1, -5000], str(refused_caps))

    # 2. the watcher charges each call exactly once, in order, at the live allowance
    envelope = Envelope(1000)
    usage_50 = Usage(input_tokens=10, cache_read_tokens=90, output_tokens=50, reasoning_tokens=20)
    usage_200 = Usage(input_tokens=10, cache_read_tokens=90, output_tokens=200, reasoning_tokens=100)

    def reader_for(calls):
        def read(work_dir, since, root):
            return {"matched": True, "sessions": [{"path": "/s/x"}], "malformed_lines": 0,
                    "calls": [call for call, _ in calls],
                    "call_meta": [meta for _, meta in calls]}
        return read

    meta = [{"session": "/s/x", "index": 0, "step": 1}, {"session": "/s/x", "index": 1, "step": 2}]
    watcher = SessionWatcher(envelope, scratch, "2026-01-01T00:00:00+00:00", "repair-1", scratch,
                             reader=reader_for(list(zip([usage_50, usage_200], meta))))
    new, refused_now = watcher.poll()
    reread, _ = watcher.poll()
    check("the watcher charges each observed call exactly once",
          len(new) == 2 and reread == [] and watcher.repeat_observations == 2
          and [entry["allowance"] for entry in new] == [1000, 950],
          f"new={len(new)} reread={len(reread)} repeats={watcher.repeat_observations}")
    check("charges are the real spend, in log order, and never a truncation",
          [entry["charged"] for entry in new] == [50, 200] and envelope.spent == 250
          and [entry["refused"] for entry in new] == [False, False])

    # 3. an overshoot is charged at actual spend and ends the candidate
    envelope = Envelope(200)
    calls = [(Usage(output_tokens=150), {"session": "/s/x", "index": 0}),
             (Usage(output_tokens=300), {"session": "/s/x", "index": 1})]
    watcher = SessionWatcher(envelope, scratch, "2026-01-01T00:00:00+00:00", "repair-1", scratch,
                             reader=reader_for(calls))
    new, refused_now = watcher.poll()
    check("an overshooting call stands as actual spend and refuses",
          refused_now and new[-1]["refused"] and new[-1]["overshoot"] == 250
          and envelope.spent == 450 and envelope.remaining() == -250,
          f"spent={envelope.spent} overshoot={new[-1]['overshoot']}")
    check("remaining <= 0 forbids another candidate",
          next_candidate_allowed(envelope, 1, 5, 5) == (False, "envelope-exhausted"))
    check("the candidate pool bound and the session budget both stop the loop",
          next_candidate_allowed(Envelope(10 ** 6), 2, 2, 5) == (False, "candidate-pool-exhausted")
          and next_candidate_allowed(Envelope(10 ** 6), 1, 5, 1) == (False, "session-budget"))

    # 4. both policies share ONE envelope per task, never one per candidate
    shared = Envelope(1000)
    shared.charge(usage_50, label="candidate-1", allowance=shared.remaining())
    shared.charge(usage_200, label="candidate-2", allowance=shared.remaining())
    check("every candidate of a task charges the same envelope instance",
          shared.spent == 250 and len(shared.charges) == 2
          and [charge["label"] for charge in shared.charges] == ["candidate-1", "candidate-2"]
          and [charge["allowance"] for charge in shared.charges] == [1000, 950])

    # 5. selection reads the public check only
    candidates = [
        {"label": "a", "complete": True, "public_acceptance": False, "hidden_acceptance": True},
        {"label": "b", "complete": True, "public_acceptance": True, "hidden_acceptance": False},
        {"label": "c", "complete": False, "public_acceptance": True, "hidden_acceptance": True},
    ]
    selected, mode, why = select_candidate(candidates)
    check("selection prefers a complete public-passing candidate and never reads hidden",
          selected["label"] == "b" and mode == "public" and "hidden" not in why)
    selected, mode, _ = select_candidate([{"label": "x", "complete": True, "public_acceptance": False,
                                           "hidden_acceptance": True}])
    check("a complete candidate that fails public is still the fallback, not a hidden-passing one",
          selected["label"] == "x" and mode == "last-complete")
    check("no complete candidate means no selection", select_candidate([])[0] is None)

    # 6. the prompt states the budget and is frozen by hash
    prompt = prompt_text("dev-bool", 5000)
    check("the prompt states the generated-token budget and the termination rule",
          "You have 5000 generated (output) tokens for this task, reasoning included" in prompt
          and "terminates the attempt as soon as that budget is exceeded" in prompt)
    check("the prompt keeps the M1 treatment text otherwise",
          "At most 20 compiler invocations are available for this attempt." in prompt
          and "do not spawn subagents" in prompt
          and "reply with a short final message" in prompt)
    check("the prompt identity is stable and cap-dependent",
          sha256_text(prompt) == sha256_text(prompt_text("dev-bool", 5000))
          and sha256_text(prompt) != sha256_text(prompt_text("dev-bool", 4000)))

    # 7. an unmatched session log is MISSING, never imputed
    empty = scratch / "never-ran"
    empty.mkdir()
    read = m2_usage.read_calls(empty, "2026-01-01T00:00:00+00:00", root=scratch / "no-sessions")
    missing = SessionWatcher(Envelope(100), empty, "2026-01-01T00:00:00+00:00", "repair-1", scratch / "no-sessions")
    missing.poll()
    check("a run whose log cannot be matched reads as MISSING with no invented spend",
          read["matched"] is False and read["calls"] == [] and missing.missing_note() is not None
          and missing.envelope.spent == 0 and missing.charges == [])

    # 8. one participant at a time
    lock = ParticipantLock(scratch / "lock")
    lock.acquire()
    blocked = False
    try:
        ParticipantLock(scratch / "lock").acquire()
    except SystemExit:
        blocked = True
    lock.release()
    reacquired = ParticipantLock(scratch / "lock")
    reacquired.acquire()
    check("a second participant is refused while one is running, and allowed after release",
          blocked and reacquired.held)
    reacquired.release()

    # 9. termination escalates to SIGKILL when SIGTERM is ignored
    ready = scratch / "stubborn-ready"
    stubborn = subprocess.Popen(
        [sys.executable, "-c",
         "import pathlib,signal,sys,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); "
         "pathlib.Path(sys.argv[1]).write_text('ready'); time.sleep(60)", str(ready)],
        start_new_session=True)
    for _ in range(100):
        if ready.is_file():
            break
        time.sleep(0.05)
    began = time.monotonic()
    sent = terminate(stubborn, grace=1.0)
    code = stubborn.wait()
    elapsed = time.monotonic() - began
    check("an overshoot terminates the process group, escalating to SIGKILL",
          ready.is_file() and sent == "SIGKILL" and code == -signal.SIGKILL and elapsed < 5.0,
          f"sent={sent} exit={code} seconds={elapsed:.2f}")

    # 10. the session budget arithmetic refuses to overrun
    overrun = False
    try:
        check_session_budget(used=7, will_use=2, budget=8)
    except SystemExit:
        overrun = True
    check("the global session budget refuses to overrun",
          overrun and check_session_budget(used=7, will_use=1, budget=8) == 8)

    # 11. the three stop states re-derive from the recorded evidence
    def charge(refused: bool, flagged: bool) -> dict:
        return {"refused": refused, "after_overshoot": flagged}
    signal_stop = {"ended_by_overshoot": True, "exit": -9, "exit_signal": "SIGKILL",
                   "kill_signal_sent": "SIGKILL", "stop_requested": True, "grace_seconds": 5.0,
                   "reaped_after_request_seconds": 5.0, "late_calls_after_stop": 0,
                   "overshoot": 400, "complete": False, "charges": [charge(False, False), charge(True, False)]}
    graceful_stop = {**signal_stop, "exit": 0, "exit_signal": "", "kill_signal_sent": "SIGTERM",
                     "reaped_after_request_seconds": 0.23}
    stopped_none = {**graceful_stop, "stop_requested": False, "kill_signal_sent": "",
                    "reaped_after_request_seconds": None}
    stale_grace = {**graceful_stop, "reaped_after_request_seconds": 30.0}
    late_grace = {**graceful_stop, "late_calls_after_stop": 1,
                  "charges": [charge(False, False), charge(True, False), charge(False, True)]}
    unflagged = {**graceful_stop, "charges": [charge(False, False), charge(True, False), charge(False, False)]}
    check("the stop is tri-state and re-derives from the exit, the request and the charges",
          classify_stop(signal_stop)["stop"] == STOP_SIGNAL
          and classify_stop(graceful_stop)["stop"] == STOP_GRACEFUL
          and classify_stop(stopped_none)["stop"] == STOP_NONE
          and classify_stop(stale_grace)["stop"] == STOP_NONE
          and classify_stop(late_grace)["stop"] == STOP_NONE,
          str([classify_stop(case)["stop"] for case in
               (signal_stop, graceful_stop, stopped_none, stale_grace, late_grace)]))
    check("a stop that did not stop generation is a mechanism failure",
          mechanism_failures(graceful_stop, 5000) == []
          and mechanism_failures(signal_stop, 5000) == []
          and mechanism_failures(stale_grace, 5000)
          and mechanism_failures(late_grace, 5000)
          and mechanism_failures(stopped_none, 5000)
          and mechanism_failures(unflagged, 5000)
          and mechanism_failures({**graceful_stop, "overshoot": 20000}, 5000)
          and mechanism_failures({**graceful_stop, "complete": True}, 5000))

    shutil.rmtree(scratch, ignore_errors=True)
    failures = [name for name, ok, _ in checks if not ok]
    print(f"\n{len(checks) - len(failures)}/{len(checks)} enforcement properties demonstrated")
    return len(checks) - len(failures), len(checks), failures


def check_session_budget(used: int, will_use: int, budget: int) -> int:
    """Refuse to spend more participant sessions than the approved total."""
    if used + will_use > budget:
        raise SystemExit(f"enforcing_runner: session budget {budget} would be exceeded "
                         f"({used} used + {will_use} requested)")
    return used + will_use


def sessions_used(evidence_root: Path = EVIDENCE_ROOT) -> int:
    """Participant sessions already recorded in this cohort's evidence."""
    total = 0
    if not evidence_root.is_dir():
        return 0
    for path in sorted(evidence_root.glob("*/*/record.json")):
        try:
            record = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        total += int(record.get("session_budget", {}).get("sessions_this_task",
                                                          len(record.get("candidates", []))))
    return total


# --------------------------------------------------------------------------
# dry run


FAKE_PARTICIPANT = '''#!/usr/bin/env python3
"""Dry-run stand-in: append session-log frames over time, then hold.

With `--graceful`, SIGTERM is trapped and answered with a clean exit 0 — the shape
`dsh --profile headless` has — so the graceful half of the stop classification is
exercised by the same process control the live path uses.
"""
import argparse, json, os, signal, subprocess, sys, time
from pathlib import Path


def frame(line: bytes) -> bytes:
    return subprocess.run(["zstd", "-q", "-c", "--"], input=line, capture_output=True).stdout


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--work-dir", required=True)
    parser.add_argument("--session-root", required=True)
    parser.add_argument("--session-id", default="dry")
    parser.add_argument("--calls", default="")
    parser.add_argument("--delay", type=float, default=0.15)
    parser.add_argument("--marker", default="")
    parser.add_argument("--hold", type=float, default=8.0)
    parser.add_argument("--graceful", action="store_true")
    parser.add_argument("--no-log", action="store_true")
    args = parser.parse_args()
    if args.graceful:
        signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    if args.no_log:
        time.sleep(args.hold)
        return 0
    work = Path(args.work_dir)
    slug = "--" + str(work).replace("/", "-") + "--"
    directory = Path(args.session_root) / slug / ("session-" + args.session_id)
    directory.mkdir(parents=True, exist_ok=True)
    log = directory / "session.v3.jsonl.zstd"
    header = {"type": "session", "version": 3, "id": "session-" + args.session_id,
              "createdAt": int(time.time() * 1000), "cwd": str(work), "delegationDepth": 0}
    with log.open("ab") as handle:
        handle.write(frame((json.dumps(header) + "\\n").encode()))
        handle.flush()
        os.fsync(handle.fileno())
    for index, size in enumerate([int(x) for x in args.calls.split(",") if x.strip()], start=1):
        record = {"type": "assistant/message", "time": int(time.time() * 1000),
                  "data": {"step": index, "usage": {"inputTokens": 100, "cacheReadTokens": 900,
                                                    "outputTokens": size, "reasoningTokens": size // 2,
                                                    "totalTokens": 100 + 900 + size}}}
        with log.open("ab") as handle:
            handle.write(frame((json.dumps(record) + "\\n").encode()))
            handle.flush()
            os.fsync(handle.fileno())
        time.sleep(args.delay)
    if args.marker:
        (work / "project").mkdir(parents=True, exist_ok=True)
        (work / "project" / ".answer").write_text(args.marker + "\\n")
    time.sleep(args.hold)
    return 0


if __name__ == "__main__":
    sys.exit(main())
'''


def dry_run() -> tuple[int, int, list[str]]:
    """Exercise the real watcher, kill path and policy loop with no model calls.

    A stand-in participant appends session-log frames in small increments (one
    zstd frame per call, the shape the harness writes) and then either exits or
    holds, so the code under test is the same code the live pilot runs; only the
    participant process and the grader are stand-ins.
    """
    checks: list[tuple[str, bool, str]] = []
    scratch = TMP / "dryrun"
    shutil.rmtree(scratch, ignore_errors=True)
    (scratch / "sessions").mkdir(parents=True)
    fake = scratch / "fake_participant.py"
    fake.write_text(FAKE_PARTICIPANT)
    fake.chmod(0o755)

    def check(name: str, condition: bool, detail: str = "") -> None:
        checks.append((name, bool(condition), detail))
        print(f"  {'ok  ' if condition else 'FAIL'} {name}{'' if condition else '  ' + detail}")

    def launcher(calls, markers=None, holds=None, default_marker: str = "public-pass",
                 no_log: bool = False, delay: float = 0.15, graceful: bool = False):
        """Per-candidate call sizes, markers and hold times, so a kill can be
        distinguished from a session that simply ended."""
        def build(work_dir: Path, index: int, prompt: str, case: str, policy: str) -> list[str]:
            marker = (markers or {}).get(index, default_marker)
            hold = (holds or {}).get(index, 0.4)
            sizes = calls[index] if isinstance(calls, dict) else calls
            command = [sys.executable, str(fake), "--work-dir", str(work_dir), "--session-root",
                       str(scratch / "sessions"), "--session-id", f"{policy}-{case}-{index}",
                       "--calls", sizes, "--marker", marker, "--hold", str(hold), "--delay", str(delay)]
            return command + (["--no-log"] if no_log else []) + (["--graceful"] if graceful else [])
        return build

    def options(name: str, cap: int, policy: str, build, grader, **overrides) -> Options:
        base = dict(cap=cap, work_root=scratch / "work" / name, evidence_root=scratch / "evidence" / name,
                    session_root=scratch / "sessions", cohort_id="dryrun", poll_seconds=0.1,
                    grace_seconds=0.5, session_deadline=20.0, max_candidates=3, dry_run=True,
                    build_command=build, grader=grader, lock=ParticipantLock(scratch / f"lock-{name}"))
        base.update(overrides)
        return Options(**base)

    # 1. repair that fits: three calls, one envelope, one session
    grader = ScriptedGrader()
    record = run_task("dev-bool", "repair",
                      options("repair-fits", 1000, "repair", launcher("100,200,300"), grader))
    candidate = record["candidates"][0]
    keys = [charge["key"] for charge in record["charges"]]
    check("dry-run: the watcher charges each call of a growing log exactly once",
          record["calls_charged"] == 3 and len(set(keys)) == 3 and candidate["watcher_reads"] > 1,
          f"charges={record['calls_charged']} unique={len(set(keys))} reads={candidate['watcher_reads']}")
    check("dry-run: charged == the per-call sums and the envelope's own total",
          candidate["charged"] == 600 and record["totals"]["spent"] == 600
          and sum(charge["charged"] for charge in record["charges"]) == 600
          and [charge["allowance"] for charge in record["charges"]] == [1000, 900, 700])
    check("dry-run: repair runs exactly one session and selects it on the public check",
          len(record["candidates"]) == 1 and record["selection_mode"] == "public"
          and record["public_acceptance"] is True and candidate["complete"] is True
          and candidate["timed_out"] is False and candidate["stop"] == STOP_NONE
          and candidate["stop_requested"] is False,
          f"complete={candidate['complete']} timed_out={candidate['timed_out']} stop={candidate['stop']}")
    check("dry-run: the snapshot was sealed and the work dir was pruned",
          bool(candidate["sealed_source_sha256"]) and candidate["work_dir_pruned"] is True)
    check("dry-run: the cohort id reaches the record",
          record["cohort_id"] == "dryrun" and candidate["env"]["MYLANG_ATTEMPT"] == "repair/dev-bool/1",
          f"cohort_id={record['cohort_id']!r}")

    # 2. repair that overshoots: the call is charged at actual spend, the process dies
    grader = ScriptedGrader()
    record = run_task("dev-bool", "repair",
                      options("repair-overshoot", 400, "repair",
                              launcher("100,200,250", holds={1: 20.0}), grader))
    candidate = record["candidates"][0]
    refused = [charge for charge in record["charges"] if charge["refused"]]
    check("dry-run: an overshoot is charged at actual spend, not truncated",
          record["totals"]["spent"] == 550 and len(refused) == 1 and refused[0]["overshoot"] == 150
          and refused[0]["charged"] == 250 and refused[0]["allowance"] == 100
          and [charge["allowance"] for charge in record["charges"]] == [400, 300, 100],
          f"spent={record['totals']['spent']} refused={len(refused)}")
    check("dry-run: the overshoot stopped the participant and ended the candidate",
          candidate["ended_by_overshoot"] is True and candidate["complete"] is False
          and candidate["stop"] == STOP_SIGNAL
          and candidate["exit_signal"] in ("SIGTERM", "SIGKILL")
          and candidate["kill_signal_sent"] in ("SIGTERM", "SIGKILL")
          and isinstance(candidate["reaped_after_request_seconds"], float),
          f"exit={candidate['exit']} sent={candidate['kill_signal_sent']} stop={candidate['stop']}")
    check("dry-run: an overshooting repair candidate is not selected and is not retried",
          len(record["candidates"]) == 1 and record["selected"] is None
          and record["stop_reason"] == "repair-single-session")
    check("dry-run: a clean overshoot kill is not a mechanism failure",
          record["mechanism_failures"] == [] and candidate["mechanism_failures"] == []
          and candidate["late_calls_after_stop"] == 0)

    # 2b. a participant that traps SIGTERM and exits 0 — the `dsh` shape — is a stop
    grader = ScriptedGrader()
    record = run_task("dev-checked", "repair",
                      options("repair-graceful", 400, "repair",
                              launcher("100,200,250", holds={1: 20.0}, graceful=True), grader))
    candidate = record["candidates"][0]
    check("dry-run: a SIGTERM-trapping participant is a graceful-after-request stop",
          candidate["ended_by_overshoot"] is True and candidate["exit"] == 0
          and candidate["exit_signal"] == "" and candidate["stop"] == STOP_GRACEFUL
          and candidate["stop_requested"] is True
          and candidate["reaped_after_request_seconds"] <= candidate["grace_seconds"]
          and candidate["late_calls_after_stop"] == 0,
          f"exit={candidate['exit']} stop={candidate['stop']} "
          f"reaped={candidate['reaped_after_request_seconds']}")
    check("dry-run: a graceful stop is a success, not a mechanism failure",
          candidate["mechanism_failures"] == [] and record["mechanism_failures"] == []
          and candidate["complete"] is False and record["selected"] is None)

    # 3. independent: fresh candidates share one envelope; exhaustion stops the pool
    grader = ScriptedGrader()
    record = run_task("dev-bool", "independent",
                      options("independent-shared", 500, "independent",
                              launcher({1: "100,100", 2: "600"}, holds={2: 20.0}), grader,
                              max_candidates=3))
    check("dry-run: independent stops when remaining <= 0 and never starts a third candidate",
          len(record["candidates"]) == 2 and record["stop_reason"] == "overshoot"
          and record["candidates"][1]["ended_by_overshoot"] is True
          and record["totals"]["spent"] == 800,
          f"candidates={len(record['candidates'])} stop={record['stop_reason']} spent={record['totals']['spent']}")
    check("dry-run: repair and independent share ONE envelope per task",
          record["totals"]["spent"] == sum(charge["charged"] for charge in record["charges"])
          and record["totals"]["charges"] == 3 and len({charge["label"] for charge in record["charges"]}) == 2
          and [charge["allowance"] for charge in record["charges"]] == [500, 400, 300],
          str([charge["allowance"] for charge in record["charges"]]))
    check("dry-run: the second candidate was stopped by the harness for its overshoot",
          record["candidates"][1]["stop"] == STOP_SIGNAL
          and record["candidates"][1]["late_calls_after_stop"] == 0
          and record["candidates"][0]["complete"] is True)

    # 4. a candidate that uses the whole envelope exhausts it: no second session
    grader = ScriptedGrader()
    record = run_task("dev-checked", "independent",
                      options("independent-exhausted", 300, "independent", launcher("300"), grader,
                              max_candidates=3))
    check("dry-run: an exhausted envelope starts no further candidate",
          len(record["candidates"]) == 1 and record["stop_reason"] == "envelope-exhausted"
          and record["totals"]["remaining"] == 0
          and not (scratch / "work" / "independent-exhausted" / "dev-checked" / "independent" / "2").exists(),
          f"candidates={len(record['candidates'])} stop={record['stop_reason']}")
    check("dry-run: the single complete candidate is selected on the public check",
          record["selection_mode"] == "public" and record["selected"]["label"] == "independent-1")

    # 5. selection uses the public check only: a hidden-passing public failure loses
    grader = ScriptedGrader()
    record = run_task("dev-variant", "independent",
                      options("selection-public", 1000, "independent",
                              launcher("100", markers={1: "hidden-pass", 2: "public-pass"}), grader,
                              max_candidates=2))
    hidden_phases = [call["phase"] for call in grader.calls if call["kind"] == "hidden"]
    check("dry-run: selection takes the public-passing candidate, not the hidden-passing one",
          record["selected"]["label"] == "independent-2" and record["selection_mode"] == "public"
          and record["candidates"][0]["public_acceptance"] is False
          and record["candidates"][1]["public_acceptance"] is True)
    check("dry-run: the hidden manifest is run once, after selection, on the selection only",
          hidden_phases == ["grading"] and len(hidden_phases) == 1
          and record["candidates"][0]["hidden_acceptance"] is None
          and record["hidden_acceptance"] is False,
          f"hidden phases={hidden_phases}")

    # 6. a session with no log at all is MISSING, never imputed
    grader = ScriptedGrader()
    record = run_task("dev-generic", "repair",
                      options("missing-log", 1000, "repair", launcher("100", no_log=True), grader))
    candidate = record["candidates"][0]
    check("dry-run: a session whose log never appears is MISSING, with no invented spend",
          candidate["log_matched"] is False and candidate["charged"] == 0
          and record["totals"]["spent"] == 0 and record["missing"]
          and "MISSING" in record["missing"][0]["note"],
          str(record["missing"]))

    failures = [name for name, ok, _ in checks if not ok]
    print(f"\n{len(checks) - len(failures)}/{len(checks)} dry-run properties demonstrated")
    return len(checks) - len(failures), len(checks), failures


# --------------------------------------------------------------------------
# audit: re-check a written record against the world


def audit(record_path: Path) -> tuple[int, int, list[str]]:
    """Re-read a task record and re-derive its numbers from the session logs."""
    record = json.loads(record_path.read_text())
    checks: list[tuple[str, bool, str]] = []

    def check(name: str, condition: bool, detail: str = "") -> None:
        checks.append((name, bool(condition), detail))
        print(f"  {'ok  ' if condition else 'FAIL'} {name}{'' if condition else '  ' + detail}")

    destination = record_path.parent
    prompt = (destination / "prompt.md").read_text()
    check("the frozen prompt matches its recorded sha256",
          sha256_text(prompt) == record["prompt_sha256"] == record["identity"]["prompt_sha256"])
    check("the prompt states this task's budget",
          f"You have {record['cap']} generated (output) tokens" in prompt)
    check("the envelope's totals are its charges",
          record["totals"]["spent"] == sum(charge["charged"] for charge in record["charges"])
          and record["totals"]["generated"] == record["totals"]["spent"]
          and record["totals"]["charges"] == len(record["charges"]))
    check("every charge is charged at its actual spend and flags its own refusal",
          all(charge["charged"] == charge["usage"]["output_tokens"] for charge in record["charges"])
          and all((charge["overshoot"] > 0) == charge["refused"] for charge in record["charges"])
          and all(charge["allowance"] is not None for charge in record["charges"]))

    rule = recorded_rule(record)
    for candidate in record["candidates"]:
        label = candidate["label"]
        logs = audit_read_logs(candidate)
        matched = logs["matched"]
        check(f"{label}: the session log still matches the recorded work dir and start time",
              matched == candidate["log_matched"] and (not matched or bool(logs["calls"])),
              f"matched={matched} recorded={candidate['log_matched']}")
        if matched:
            check(f"{label}: the logs' per-call sums equal the recorded charges",
                  logs["generated"] == candidate["charged"]
                  and len(logs["calls"]) >= candidate["calls_charged"],
                  f"logs={logs['generated']} recorded={candidate['charged']} calls={len(logs['calls'])}")
        verdict = classify_stop(candidate)
        check(f"{label}: the stop re-derives from the recorded exit, request and charges",
              verdict["stop"] in STOP_STATES
              and (candidate.get("stop") in (None, verdict["stop"]))
              and (verdict["stop"] != STOP_SIGNAL or candidate["exit_signal"] in ("SIGTERM", "SIGKILL")),
              f"stop={verdict['stop']} recorded={candidate.get('stop')} exit={candidate['exit']} "
              f"signal={candidate['exit_signal']!r}")
        print(f"       stop[{label}]={verdict['stop']} ({verdict['why']}; "
              f"reaped-after={verdict['reaped_after_request_seconds']}s via {verdict['latency_source']}, "
              f"late_calls={verdict['late_calls_after_stop']})")
        check(f"{label}: the sealed snapshot's inventory hash is the recorded one",
              sealed_hash(destination / "sealed" / label) == candidate["sealed_source_sha256"])
        check(f"{label}: the public acceptance re-derives from the sealed snapshot",
              rederive_public(record["case"], destination / "sealed" / label) == candidate["public_acceptance"])

    selected = record.get("selected")
    if selected:
        if record.get("hidden_manifest_supplied"):
            check("the selection's hidden acceptance re-derives from the sealed snapshot",
                  rederive_hidden(record["case"], destination / "sealed" / selected["label"])
                  == selected["hidden_acceptance"])
        else:
            check("no hidden manifest was supplied, so hidden acceptance is None",
                  selected["hidden_acceptance"] is None)
    check("the recorded mechanism failures are the ones its runner's rule derives",
          record["mechanism_failures"] == [{"candidate": candidate["label"],
                                            "problems": rule(candidate, record["cap"])}
                                           for candidate in record["candidates"]
                                           if rule(candidate, record["cap"])],
          json.dumps(record["mechanism_failures"]))
    check("the declared session count matches the candidate list",
          record["session_budget"]["sessions_this_task"] == len(record["candidates"])
          and record["candidates_started"] == len(record["candidates"]))
    check("the selected candidate is complete, and public-passing whenever one passed",
          selected is None or (selected["complete"]
                               and (selected["public_acceptance"] or record["selection_mode"] == "last-complete")))

    failures = [name for name, ok, _ in checks if not ok]
    print(f"\n{len(checks) - len(failures)}/{len(checks)} audit checks passed for {record_path}")
    return len(checks) - len(failures), len(checks), failures


def reclassify(record_path: Path, out: Path | None = None) -> tuple[int, int, list[str]]:
    """Re-derive the tri-state stop for an existing record, without touching it.

    A runner v1 record carries `killed_by_harness` and no `stop`. This reads what
    the record does carry — exit code, exit signal, the signal the harness sent,
    the charge list with each charge's observation time, the refusal, and the
    finish time — and derives the v2 verdict, printing the timeline the verdict
    rests on. The record itself is never rewritten: the reclassification is a
    derived reading of frozen evidence, and `--out` writes it beside, not over,
    the record.
    """
    record = json.loads(record_path.read_text())
    checks: list[tuple[str, bool, str]] = []

    def check(name: str, condition: bool, detail: str = "") -> None:
        checks.append((name, bool(condition), detail))
        print(f"  {'ok  ' if condition else 'FAIL'} {name}{'' if condition else '  ' + detail}")

    v1 = record.get("runner_sha256") == LEGACY_RUNNER_SHA256
    print(f"record      {record_path}")
    print(f"runner      {record.get('runner_sha256')}  ({'v1, pre-tri-state' if v1 else 'v2'})")
    print(f"case/policy {record['case']} / {record['policy']}   cap={record['cap']}")
    candidates = []
    for candidate in record["candidates"]:
        verdict = classify_stop(candidate)
        spent = sum(charge["charged"] for charge in candidate.get("charges") or [])
        item = {"label": candidate["label"], **verdict,
                "exit": candidate.get("exit"), "ended_by_overshoot": bool(candidate.get("ended_by_overshoot")),
                "overshoot": candidate.get("overshoot"), "spent": spent,
                "calls": len(candidate.get("charges") or []),
                "late_call_keys": candidate.get("late_call_keys") or [],
                "unflagged_after_refusal": unflagged_after_refusal(candidate),
                "recorded_killed_by_harness": candidate.get("killed_by_harness"),
                "recorded_stop": candidate.get("stop"),
                "recorded_mechanism_failures": candidate.get("mechanism_failures", [])}
        candidates.append(item)
        refusal = next((charge for charge in candidate.get("charges") or [] if charge.get("refused")), None)
        print(f"\n  candidate {candidate['label']}")
        print(f"    refusal observed      {refusal and refusal.get('observed_utc')}  "
              f"(call #{refusal and refusal.get('key', '').rsplit('#', 1)[-1]}, "
              f"overshoot {refusal and refusal.get('overshoot')})")
        print(f"    stop requested at     {candidate.get('stop_requested_utc') or '(not recorded: v1)'}")
        print(f"    finished at           {candidate.get('finished_utc')}")
        print(f"    signal sent / exit    {candidate.get('kill_signal_sent') or '(none)'} / "
              f"{candidate.get('exit')} ({candidate.get('exit_signal') or 'no signal'})")
        print(f"    reaped after request  {verdict['reaped_after_request_seconds']}s "
              f"({verdict['latency_source']}, grace {candidate.get('grace_seconds', DEFAULT_GRACE_SECONDS)}s)")
        print(f"    late calls            {verdict['late_calls_after_stop']} "
              f"{candidate.get('late_call_keys') or []}")
        print(f"    spend                 {spent} generated over {item['calls']} calls")
        print(f"    STOP                  {verdict['stop']}  — {verdict['why']}")
        check(f"{candidate['label']}: an overshoot-ended candidate re-classifies as a stop",
              not candidate.get("ended_by_overshoot") or verdict["stop"] in (STOP_SIGNAL, STOP_GRACEFUL),
              verdict["stop"])
        check(f"{candidate['label']}: the re-derivation is consistent with the record",
              verdict["stop"] in STOP_STATES
              and (candidate.get("stop") in (None, verdict["stop"]))
              and (v1 or candidate.get("stop") == verdict["stop"]),
              f"recorded={candidate.get('stop')} derived={verdict['stop']}")
        check(f"{candidate['label']}: reclassification leaves the spend and charges as recorded",
              spent == candidate.get("charged")
              and len(candidate.get("charges") or []) == candidate.get("calls_charged"),
              f"rederived={spent} recorded={candidate.get('charged')} calls={item['calls']}")
        check(f"{candidate['label']}: late calls stay visible and charged",
              len(candidate.get("late_call_keys") or []) == int(candidate.get("late_calls_after_stop") or 0)
              and all(any(charge["key"] == key for charge in record["charges"])
                      for key in candidate.get("late_call_keys") or []))
    check("the record's envelope total is its charge list, unchanged by reclassification",
          record["totals"]["spent"] == sum(charge["charged"] for charge in record["charges"]))
    if out is not None:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps({"schema": "m2-stop-reclassification-v1", "record": str(record_path),
                                   "record_sha256": sha256_path(record_path),
                                   "record_runner_sha256": record.get("runner_sha256"),
                                   "reclassified_by": sha256_path(Path(__file__)),
                                   "reclassified_utc": now_iso(), "candidates": candidates},
                                  indent=2) + "\n")
        print(f"\nwrote {out} (the record itself is unchanged)")
    failures = [name for name, ok, _ in checks if not ok]
    print(f"\n{len(checks) - len(failures)}/{len(checks)} reclassification checks passed for {record_path}")
    return len(checks) - len(failures), len(checks), failures


def audit_read_logs(candidate: dict) -> dict:
    """Re-read a candidate's calls from the original logs, else from the evidence copies."""
    work_dir = Path(candidate["work_dir"])
    started = candidate["started_utc"]
    read = m2_usage.read_calls(work_dir, started)
    if read["matched"]:
        return read
    copies = candidate.get("raw_session_log_copies") or []
    if not copies:
        return read
    root = TMP / "audit-sessions" / candidate["label"]
    shutil.rmtree(root, ignore_errors=True)
    slug = m2_usage.slug_for(work_dir)
    for index, copy in enumerate(copies, start=1):
        source = Path(copy)
        session_dir = root / slug / f"session-copy-{index}"
        session_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, session_dir / ("session.v3.jsonl.zstd" if source.name.endswith(".zstd")
                                            else "session.v3.jsonl"))
    return m2_usage.read_calls(work_dir, started, root=root)


def sealed_hash(sealed: Path) -> str | None:
    if not sealed.is_dir():
        return None
    entries = {}
    for path in sorted(sealed.rglob("*")):
        if path.is_file():
            entries[path.relative_to(sealed).as_posix()] = sha256_path(path)
    return sha256_bytes(json.dumps(entries, sort_keys=True).encode())


def rederive_public(case: str, sealed: Path) -> bool:
    if not (sealed / "main.my").is_file():
        return False
    root = TMP / "audit-grade" / case
    graded = copy_for_grading(sealed, root)
    return bool(with_cache_env(root, public_only, case, graded)["public_acceptance"])


def rederive_hidden(case: str, sealed: Path) -> bool | None:
    if not (sealed / "main.my").is_file():
        return None
    root = TMP / "audit-grade-hidden" / case
    graded = copy_for_grading(sealed, root)
    verdict = with_cache_env(root, m2_run.grade, root, case, graded)
    return bool(verdict.get("hidden_acceptance"))


# --------------------------------------------------------------------------
# pilot


def run_pilot(options: Options, session_budget: int) -> int:
    """The approved cell list: one participant at a time, never over budget."""
    for case, policy in PILOT_ORDER:
        destination = options.evidence_root / case / policy
        if (destination / "record.json").exists():
            print(f"skip   {case}/{policy}: a record already exists")
            continue
        used = sessions_used(options.evidence_root)
        check_session_budget(used, 1, session_budget)
        if other_participant_running():
            raise SystemExit("enforcing_runner: another participant looks alive:\n  "
                             + "\n  ".join(other_participant_running()))
        print(f"run    {case}/{policy}  cap={options.cap}  sessions_used={used}/{session_budget}", flush=True)
        record = run_task(case, policy, options)
        candidate = record["candidates"][0] if record["candidates"] else None
        print(f"       calls={record['calls_charged']} spend={record['totals']['spent']}"
              f" overshoot={'yes' if record['totals']['refused'] else 'no'}"
              f" complete={candidate and candidate['complete']}"
              f" public={'ok' if record['public_acceptance'] else 'fail'}"
              f" hidden={record['hidden_acceptance']}"
              f" wall={record['wall_seconds']:.0f}s", flush=True)
        if record["mechanism_failures"]:
            print(f"STOP   mechanism failure recorded in {destination}/record.json")
            return 2
        if record["missing"]:
            print(f"STOP   missing observation recorded in {destination}/record.json: {record['missing']}")
            return 3
    return 0


# --------------------------------------------------------------------------
# CLI


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cap", type=int, default=DEFAULT_CAP,
                        help=f"generated-token cap per task (default {DEFAULT_CAP})")
    parser.add_argument("--case", help="a case under cases/dev or cases/test")
    parser.add_argument("--policy", choices=POLICIES, help="repair or independent")
    parser.add_argument("--pilot", action="store_true",
                        help="run the approved cell list, one participant at a time")
    parser.add_argument("--session-budget", type=int, default=DEFAULT_SESSION_BUDGET,
                        help="participant sessions this cohort may ever spend (default 8)")
    parser.add_argument("--max-candidates", type=int, default=DEFAULT_MAX_CANDIDATES)
    parser.add_argument("--sessions-allowed", type=int, default=0,
                        help="sessions one task may start (default: --max-candidates)")
    parser.add_argument("--poll", type=float, default=DEFAULT_POLL_SECONDS)
    parser.add_argument("--grace", type=float, default=DEFAULT_GRACE_SECONDS)
    parser.add_argument("--session-deadline", type=float, default=DEFAULT_SESSION_DEADLINE)
    parser.add_argument("--session-root", type=Path, default=m2_usage.SESSION_ROOT)
    parser.add_argument("--cohort-id", default="pilot-5000",
                        help="cohort id written into records and exported as MYLANG_COHORT "
                             "(default pilot-5000, the pilot's id)")
    parser.add_argument("--work-root", type=Path, default=WORK_ROOT)
    parser.add_argument("--evidence-root", type=Path, default=EVIDENCE_ROOT)
    parser.add_argument("--keep-work", action="store_true")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--audit", type=Path, help="re-check one written record against the world")
    parser.add_argument("--reclassify", type=Path,
                        help="re-derive the tri-state stop for an existing record (writes nothing)")
    parser.add_argument("--out", type=Path, help="with --reclassify: also write the verdict here")
    args = parser.parse_args()

    TMP.mkdir(parents=True, exist_ok=True)
    if args.selftest:
        _, _, failures = selftest()
        return 1 if failures else 0
    if args.dry_run:
        _, _, failures = dry_run()
        return 1 if failures else 0
    if args.audit:
        _, _, failures = audit(args.audit)
        return 1 if failures else 0
    if args.reclassify:
        _, _, failures = reclassify(args.reclassify, args.out)
        return 1 if failures else 0

    validate_cap(args.cap)
    options = Options(cap=args.cap, work_root=args.work_root, evidence_root=args.evidence_root,
                      session_root=args.session_root, cohort_id=args.cohort_id,
                      poll_seconds=args.poll, grace_seconds=args.grace,
                      session_deadline=args.session_deadline, max_candidates=args.max_candidates,
                      sessions_allowed=args.sessions_allowed, keep_work=args.keep_work, grader=RealGrader())
    if args.pilot:
        return run_pilot(options, args.session_budget)
    if not args.case or not args.policy:
        parser.error("--case and --policy are required unless --pilot, --selftest, --dry-run, "
                     "--audit or --reclassify is given")
    used = sessions_used(args.evidence_root)
    check_session_budget(used, 1, args.session_budget)
    record = run_task(args.case, args.policy, options)
    print(json.dumps({"case": record["case"], "policy": record["policy"], "cap": record["cap"],
                      "calls": record["calls_charged"], "spent": record["totals"]["spent"],
                      "refused": record["totals"]["refused"], "public": record["public_acceptance"],
                      "hidden": record["hidden_acceptance"], "selection": record["selection_mode"],
                      "stop_reason": record["stop_reason"],
                      "mechanism_failures": record["mechanism_failures"]}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())

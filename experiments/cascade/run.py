#!/usr/bin/env python3
"""Run maintainer sessions for the cascading-benefit experiment.

One run is one fresh headless agent given one arm and one change request. The
runner builds a working copy that contains only the arm, the request, the docs
and the installed compiler; launches ``dsh --profile headless`` in it; verifies
the result with the task's hidden manifest through ``scripts/verify.py``; reads
the session log the harness wrote for that working-copy path; and writes
``runs/<arm>/<task>/<n>.json``.

    python3 experiments/cascade/run.py --arm B --task T1 --runs 3
    python3 experiments/cascade/run.py --arm B --task T1 --n 1 --dry-run
    python3 experiments/cascade/run.py --arm P1 --chain T2,T3,T7
    python3 experiments/cascade/run.py --arm B --task T1 --n 1 --verify-only

A run is discarded, not scored, when its session shows delegation (the maintainer
prompt forbids subagents, so a nonzero delegation depth means the cost is not one
agent's) or when no session log with usage records exists for its working copy.

Nothing here reads the hidden pack into a working copy before the agent session
ends: the hidden tests, goldens and manifest are copied in only for verification.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
HIDDEN = REPO.parent / "mylang-eval" / "cascade"
WORK = HERE / "work"
RUNS = HERE / "runs"
PROMPT = HERE / "maintainer_prompt.md"
# The compiler the experiment runs against is frozen under tools/bin so that a
# rebuild of the checkout (this repository is worked on while the experiment
# runs) cannot move the ground under a session. Fall back to the checkout only
# when the frozen copy is absent.
FROZEN = HERE / "tools" / "bin"
COMPILER = (FROZEN / "mylang") if (FROZEN / "mylang").is_file() else (REPO / "zig-out" / "bin" / "mylang")
QBE = (FROZEN / "qbe") if (FROZEN / "qbe").is_file() else (REPO / "zig-out" / "bin" / "qbe")
VERIFY = REPO / "scripts" / "verify.py"
SESSION_ROOT = Path.home() / ".dsh" / "sessions"


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def toolchain() -> dict:
    """The frozen compiler's identity, recorded in every run."""
    record = {"compiler": str(COMPILER), "qbe": str(QBE)}
    for name, path in (("compiler_sha256", COMPILER), ("qbe_sha256", QBE)):
        try:
            record[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        except OSError:
            record[name] = None
    return record


def arm_dir(arm: str) -> Path:
    """A design name under designs/, or a directory path."""
    candidate = Path(arm)
    if candidate.is_dir():
        return candidate.resolve()
    return (HERE / "designs" / arm).resolve()


def chain_name(repetition: int, step: int, attempt: int) -> str:
    """Storage name for one chained run: repetition, step and attempt are all keys.

    Omitting any of them lets a later chain overwrite an earlier one, which is
    exactly how a promising 14% lead could be lost rather than replicated.
    """
    return f"chain-r{repetition}-s{step}-a{attempt}"


def build_working_copy(arm: str, task: str, run: int, chain_parent: Path | None = None, chain_step: int | None = None,
                       chain_repetition: int = 1, chain_attempt: int = 1) -> Path:
    """A fresh directory holding only the arm, the request, the docs and the compiler."""
    project = arm_dir(arm)
    if not (project / "main.my").is_file():
        raise SystemExit(f"run: {project} is not an arm (no main.my)")
    request = HERE / "pack" / task / "request.md"
    if not request.is_file():
        raise SystemExit(f"run: no request for {task}")
    # A chained run is a different measurement from an independent one — it
    # starts from the previous result, not from the frozen arm — so it gets its
    # own working copy and its own record instead of overwriting run 1.
    directory = WORK / arm / task / (chain_name(chain_repetition, chain_step, chain_attempt)
                                    if chain_step is not None else str(run))
    if directory.exists():
        shutil.rmtree(directory)
    (directory / "bin").mkdir(parents=True)
    source = chain_parent if chain_parent is not None else project
    shutil.copytree(
        source, directory / "project", symlinks=False,
        ignore=shutil.ignore_patterns(".mylang-cache", "__pycache__", "_verify"),
    )
    for name, target in (("mylang", COMPILER), ("qbe", QBE)):
        # A symlink outside the project root: the guest-test snapshot walks the
        # project and refuses to run through a symlink inside it.
        os.symlink(target, directory / "bin" / name)
    shutil.copy2(request, directory / "request.md")
    docs = REPO / "docs"
    if docs.is_dir():
        shutil.copytree(docs, directory / "docs", symlinks=False, ignore=shutil.ignore_patterns("__pycache__"))
    (directory / "HOWTO.md").write_text(
        "# Working copy\n\n"
        "`project/` is the reader you are changing; `project/request.md` is the change\n"
        "request (also at `request.md`). `bin/mylang` is the installed compiler.\n\n"
        "```sh\n"
        "cd project\n"
        "../bin/mylang test tests        # the port's own guest suite\n"
        "../bin/mylang run main.my -- <file.sexp> --render\n"
        "```\n\n"
        "`docs/` is the mylang language and tooling documentation.\n"
    )
    return directory


def maintainer_prompt(arm: str, task: str) -> str:
    template = PROMPT.read_text()
    return template.replace("{arm}", arm).replace("{task}", task)


def launcher(cli: str = "dsh") -> list[str]:
    """The argv template for one agent session, from velocity/goal.json.

    The template is the repository's record of how a headless agent is started
    (``solver.command_templates``), so a second agent CLI is a second template
    here rather than a second runner.
    """
    goal = REPO / "velocity" / "goal.json"
    try:
        solver = json.loads(goal.read_text()).get("solver", {})
    except (OSError, json.JSONDecodeError):
        solver = {}
    templates = solver.get("command_templates", {})
    template = templates.get(cli) or templates.get(solver.get("default", "dsh"))
    if not template:
        return ["dsh", "--profile", "headless", "{prompt}"]
    return list(template)


def launch(directory: Path, prompt: str, timeout: float, cli: str = "dsh", turn_cap: int = 30) -> dict:
    """Run one headless session in the working copy.

    The compiler's global cache is pointed inside the working copy: the session's
    own sandbox is rooted there, so a default cache path in the home directory is
    unwritable and the agent would spend turns discovering that instead of
    working on the change.
    """
    started = datetime.now(timezone.utc)
    command = [
        part.replace("{prompt}", prompt).replace("{turn_cap}", str(turn_cap))
        for part in launcher(cli)
    ]
    environment = dict(os.environ)
    # Forced, not defaulted, and *both* caches: a sweep runs several sessions at
    # once (a shared compiler cache makes concurrent native tools race), and the
    # compiler's local cache defaults to a directory anchored at its install
    # location — inside the repository, which the session's workspace-write
    # sandbox cannot write. Every maintainer session before this fix spent turns
    # on `failed to create output directory .../.zig-cache/tmp/...:
    # ReadOnlyFileSystem`; see experiments/elegance-metrics/findings.
    environment["ZIG_GLOBAL_CACHE_DIR"] = str(directory / ".cache" / "zig-global")
    environment["ZIG_LOCAL_CACHE_DIR"] = str(directory / ".cache" / "zig-local")
    try:
        result = subprocess.run(command, cwd=directory, capture_output=True, text=True, timeout=timeout, env=environment)
        timed_out = False
        exit_code = result.returncode
        stdout, stderr = result.stdout, result.stderr
    except subprocess.TimeoutExpired as expired:
        timed_out = True
        exit_code = -1
        stdout = (expired.stdout or b"").decode(errors="replace") if isinstance(expired.stdout, bytes) else (expired.stdout or "")
        stderr = (expired.stderr or b"").decode(errors="replace") if isinstance(expired.stderr, bytes) else (expired.stderr or "")
    return {
        "command": command,
        "env": {name: environment[name] for name in ("ZIG_GLOBAL_CACHE_DIR", "ZIG_LOCAL_CACHE_DIR")},
        "started_utc": started.isoformat(),
        "finished_utc": now(),
        "seconds": (datetime.now(timezone.utc) - started).total_seconds(),
        "timed_out": timed_out,
        "exit": exit_code,
        "stdout": stdout,
        "stderr": stderr,
    }


def green_text(text: str) -> bool:
    """A check output that reports no failures at all."""
    return ", 0 failed" in text or "0 failed across" in text


def phase_summary(usage_by_step: dict[int, float], first_edit_step: int | None, green_step: int | None) -> dict:
    """Token cost split by phase: before the first edit, edit-to-green, after.

    Reading and assessment are real maintenance costs and stay in the total; the
    split is what makes them visible instead of implicit.
    """
    def total(low: int, high: int | None) -> float:
        return round(sum(cost for step, cost in usage_by_step.items()
                         if step > low and (high is None or step <= high)), 1)

    if first_edit_step is None:
        return {"read": total(-1, None), "edit": None, "verify": None}
    read = total(-1, first_edit_step)
    if green_step is None:
        return {"read": read, "edit": total(first_edit_step, None), "verify": None}
    return {"read": read, "edit": total(first_edit_step, green_step), "verify": total(green_step, None)}


def session_log_text(directory: Path, since: datetime):
    """Yield the decoded text of every session log written for a working copy.

    Matching is by the `cwd` recorded in each session header, the same rule the
    signal reader uses, so a caller can count diagnostics the agent was shown
    without guessing at directory-name encodings.
    """
    cutoff = since.timestamp() - 5.0
    for path in sorted(SESSION_ROOT.glob("*/session-*/session.v3.jsonl.zstd")):
        try:
            if path.stat().st_mtime < cutoff:
                continue
        except OSError:
            continue
        text = subprocess.run(["zstd", "-dc", "--", str(path)], capture_output=True).stdout.decode(errors="replace")
        for line in text.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            if record.get("type") == "session":
                if record.get("cwd") == str(directory):
                    yield text
                break


def read_session_logs(directory: Path, since: datetime) -> dict:
    """Sum the harness session logs written for this working-copy path.

    ``dsh`` keys a session directory by the session's current directory and each
    session file records that path in its header, so the match is by recorded
    ``cwd``, not by guessing the directory-name encoding. Child sessions spawned
    by delegation run in the same directory and are counted in the same sum; the
    maximum ``delegationDepth`` is what the discard rule reads.
    """
    cutoff = since.timestamp() - 5.0
    records = []
    sessions = []
    usage = {"inputTokens": 0, "outputTokens": 0, "reasoningTokens": 0, "cacheReadTokens": 0, "totalTokens": 0}
    models: dict[str, int] = {}
    efforts: dict[str, int] = {}
    turns = set()
    steps = set()
    tools: dict[str, int] = {}
    tool_seconds: dict[str, float] = {}
    compiler_seconds = 0.0
    compiler_calls = 0
    pending: dict[str, tuple[str, float, bool, bool, bool, int]] = {}
    usage_by_step: dict[int, float] = {}
    first_edit_step = None
    green_step = None
    failures = 0
    bytes_read = 0
    max_depth = 0
    # A green check only counts as progress once something has been edited: the
    # maintainer prompt requires running the unchanged suite first, so the first
    # green of a session is the baseline, not a solution.
    first_edit_ms = None
    edits = 0
    baseline_green_ms = None
    candidate_green_ms = None
    candidate_green_step = None
    check_events: list[dict] = []
    first_time = None
    last_time = None
    for path in sorted(SESSION_ROOT.glob("*/session-*/session.v3.jsonl.zstd")):
        try:
            if path.stat().st_mtime < cutoff:
                continue
        except OSError:
            continue
        text = subprocess.run(["zstd", "-dc", str(path)], capture_output=True).stdout.decode(errors="replace")
        header = None
        matched = False
        for line in text.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            kind = record.get("type")
            if kind == "session":
                header = record
                if record.get("cwd") != str(directory):
                    break
                matched = True
                sessions.append(str(path.parent))
                depth = record.get("delegationDepth", 0)
                if isinstance(depth, int) and depth > max_depth:
                    max_depth = depth
            elif kind == "request/header" and matched:
                config = (record.get("data") or {}).get("header", {}).get("config", {})
                for key, bucket in (("model", models), ("reasoningEffort", efforts)):
                    if config.get(key):
                        bucket[config[key]] = bucket.get(config[key], 0) + 1
            elif kind == "assistant/message" and matched:
                data = record.get("data") or {}
                source = (data.get("message") or {}).get("source") or {}
                if source.get("model"):
                    models[source["model"]] = models.get(source["model"], 0) + 1
                call_usage = data.get("usage") or {}
                for key in usage:
                    value = call_usage.get(key)
                    if isinstance(value, (int, float)):
                        usage[key] += value
                # Attribute each call's billable tokens to the session step that
                # produced them, so read / edit / verify phases can be costed.
                step_key = data.get("step")
                step_cost = (call_usage.get("inputTokens", 0) + call_usage.get("outputTokens", 0))
                if isinstance(step_key, int):
                    usage_by_step[step_key] = usage_by_step.get(step_key, 0) + step_cost
                stamp = record.get("time")
                if isinstance(stamp, (int, float)):
                    first_time = stamp if first_time is None else min(first_time, stamp)
                    last_time = stamp if last_time is None else max(last_time, stamp)
            elif kind == "step/start" and matched:
                data = record.get("data") or {}
                turns.add(data.get("turn"))
                steps.add((data.get("turn"), data.get("step")))
            elif kind == "tool/call" and matched:
                data = record.get("data") or {}
                name = data.get("name", "?")
                tools[name] = tools.get(name, 0) + 1
                stamp = record.get("time")
                if isinstance(stamp, (int, float)):
                    arguments = str(data.get("arguments") or "")
                    is_check = "mylang" in arguments and any(
                        verb in arguments for verb in (" test", " check", " run", " verify")
                    )
                    pending[data.get("callId", "")] = (
                        name, stamp, "mylang" in arguments, is_check, name in ("write", "edit"),
                        data.get("step") if isinstance(data.get("step"), int) else -1,
                    )
            elif kind == "tool/result" and matched:
                data = record.get("data") or {}
                message = data.get("message") or {}
                call = (message.get("source") or {}).get("callId", "")
                name, started_at, is_compiler_call, is_check, is_edit, call_step = pending.pop(
                    call, ("", None, False, False, False, -1))
                text = ""
                for block in message.get("content") or []:
                    if isinstance(block, dict) and block.get("type") == "tool-result":
                        for item in block.get("content") or []:
                            if isinstance(item, dict) and item.get("type") == "text":
                                text += item.get("text") or ""
                finished_at = record.get("time")
                if started_at is not None and isinstance(finished_at, (int, float)):
                    elapsed = (finished_at - started_at) / 1000.0
                    tool_seconds[name] = tool_seconds.get(name, 0.0) + elapsed
                    if is_compiler_call:
                        compiler_seconds += elapsed
                        compiler_calls += 1
                if name == "read":
                    bytes_read += len(text)
                if is_edit:
                    edits += 1
                    if first_edit_ms is None and isinstance(finished_at, (int, float)):
                        first_edit_ms = finished_at
                        first_edit_step = call_step
                if is_check and isinstance(finished_at, (int, float)):
                    green = ", 0 failed" in text or "0 failed across" in text
                    outcome = "green" if green else ("red" if (" failed" in text or "error[" in text) else "unknown")
                    phase = "baseline" if first_edit_ms is None else "candidate"
                    check_events.append({"step": len(check_events) + 1, "phase": phase,
                                         "outcome": outcome, "ms": finished_at})
                    if green and phase == "baseline" and baseline_green_ms is None:
                        baseline_green_ms = finished_at
                    if green and phase == "candidate" and candidate_green_ms is None:
                        candidate_green_ms = finished_at
                        candidate_green_step = len(check_events)
                        green_step = call_step
                if not green_text(text) and (" failed" in text or "error[" in text):
                    failures += 1
        if header is None:
            continue
        if not matched:
            continue
        records.append(str(path))
    # Token accounting, from the provider's own fields. The provider maps
    # `inputTokens = prompt_tokens - cached_tokens` and
    # `outputTokens = completion_tokens`, with `reasoningTokens` a *detail of*
    # completion_tokens -- so reasoning is already inside output, and
    # `totalTokens == inputTokens + outputTokens + cacheReadTokens` holds call for
    # call (verified on 38 consecutive calls of one session, 38/38).
    #
    # The cascade's original term added reasoning to output, which double-counted
    # it; v1 is kept only so the published table can be reproduced.
    usage["cost_v1_input_output_reasoning"] = usage["inputTokens"] + usage["outputTokens"] + usage["reasoningTokens"]
    usage["cost_v2_input_output"] = usage["inputTokens"] + usage["outputTokens"]
    usage["provider_total_tokens"] = usage["inputTokens"] + usage["outputTokens"] + usage["cacheReadTokens"]
    usage["reasoning_share_of_cost_v1"] = (
        round(usage["reasoningTokens"] / usage["cost_v1_input_output_reasoning"], 4)
        if usage["cost_v1_input_output_reasoning"] else None
    )
    return {
        "logs": records,
        "session_dirs": sessions,
        "sessions": len(sessions),
        "usage": usage,
        "models": models,
        "efforts": efforts,
        "delegation_depth": max_depth,
        "turns": len(turns),
        "steps": len(steps),
        "tool_calls": tools,
        "tool_seconds": {name: round(value, 3) for name, value in sorted(tool_seconds.items())},
        "compiler_seconds": round(compiler_seconds, 3),
        "compiler_calls": compiler_calls,
        "bytes_read": bytes_read,
        "failure_results": failures,
        "edits": edits,
        "first_edit_ms": first_edit_ms,
        "baseline_green_ms": baseline_green_ms,
        "first_green_ms": candidate_green_ms,
        "first_candidate_green_step": candidate_green_step,
        "check_events": check_events,
        "phases": phase_summary(usage_by_step, first_edit_step, green_step),
        "phase_ms": {
            "read": None if first_edit_ms is None or first_time is None else first_edit_ms - first_time,
            "edit": None if candidate_green_ms is None or first_edit_ms is None else candidate_green_ms - first_edit_ms,
            "verify": None if candidate_green_ms is None or last_time is None else last_time - candidate_green_ms,
        },
        "first_event_ms": first_time,
        "last_event_ms": last_time,
        "log_seconds": None if first_time is None or last_time is None else (last_time - first_time) / 1000.0,
    }


BOOL_PARAM = re.compile(r"\b\w+:\s*bool\b")


def numstat_path(raw: str) -> str:
    """The new-side path from a ``git diff --numstat`` row.

    Comparing two directory trees makes git print the two roots with its
    ``{old => new}`` shorthand, so a row's third field is not a plain path.
    """
    text = raw.strip()
    if "{" in text and "}" in text:
        prefix = text[:text.index("{")]
        inner, _, rest = text[text.index("{") + 1:].partition("}")
        _, _, new = inner.partition(" => ")
        return prefix + new + rest
    if " => " in text:
        _, _, new = text.partition(" => ")
        return new
    return text


def hidden_test_names() -> set[str]:
    """Basenames of the pack's hidden tests, which verification copies into place."""
    return {path.name for path in HIDDEN.glob("T*/tests/*.my")}


def diff_against_arm(directory: Path, reference: Path) -> dict:
    """Files and lines changed, ignoring the compiler's own cache directory.

    The patch is also scanned for new boolean parameters: the pack reports that
    count as a coupling signal (a dialect or a mode that arrives as a flag is
    exactly the shape the pack is meant to notice), so it is measured from the
    added lines rather than judged by eye.
    """
    result = subprocess.run(
        ["git", "diff", "--no-index", "--no-renames", "--numstat", "--", str(reference), str(directory / "project")],
        capture_output=True, text=True,
    )
    added = removed = 0
    files = []
    for line in result.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) != 3:
            continue
        plus, minus, path = parts
        path = numstat_path(path)
        root = str(directory / "project")
        if path.startswith(root + "/"):
            relative = path[len(root) + 1:]
        elif path.lstrip("/").startswith(root.lstrip("/") + "/"):
            relative = path.lstrip("/")[len(root.lstrip("/")) + 1:]
        else:
            relative = path
        # Compiler and bytecode caches are the toolchain's droppings, wherever a
        # session chose to put them (`.mylang-cache`, `.cache/zig-local`, ...).
        if (
            ".mylang-cache" in relative
            or relative.startswith(".cache")
            or "/.cache" in relative
            or "__pycache__" in relative
            or Path(relative).name in hidden_test_names()
        ):
            continue
        files.append(relative)
        if plus.isdigit():
            added += int(plus)
        if minus.isdigit():
            removed += int(minus)
    # Count new boolean parameters per changed file rather than over the whole
    # tree: the compiler writes its own Zig runtime sources into the working
    # copy while a session runs, and a directory-wide scan would count those.
    new_bool_params = 0
    for relative in sorted(files):
        patch = subprocess.run(
            ["git", "diff", "--no-index", "--no-renames", "--no-color", "--",
             str(reference / relative), str(directory / "project" / relative)],
            capture_output=True, text=True,
        ).stdout
        new_bool_params += sum(
            1 for line in patch.splitlines()
            if line.startswith("+") and not line.startswith("+++") and BOOL_PARAM.search(line)
        )
    return {"files_changed": sorted(files), "added": added, "removed": removed, "new_bool_params": new_bool_params}


def declarations(project: Path) -> dict:
    """Qualified public declaration names per module, for the api-diff companion signal."""
    names = {}
    for path in sorted(project.rglob("*.my")):
        if ".mylang-cache" in str(path):
            continue
        result = subprocess.run([str(COMPILER), "list-declarations", str(path)], capture_output=True, text=True)
        if result.returncode != 0:
            continue
        try:
            data = json.loads(result.stdout)
        except json.JSONDecodeError:
            continue
        module = data.get("module") or path.stem
        for declaration in data.get("declarations") or []:
            if declaration.get("exported"):
                names[f"{module}::{declaration.get('name')}"] = declaration.get("kind")
    return names


def interface_changes(directory: Path, reference: Path, label: str) -> dict:
    """Classified interface changes against the frozen arm (mylang api-diff)."""
    cache = HERE / ".cache" / "api"
    cache.mkdir(parents=True, exist_ok=True)
    # The label carries the reference too: a chained run's reference is the
    # previous step's result, not the frozen arm, and the two must not share a
    # cached interface file.
    stamp = hashlib.sha256(str(reference).encode()).hexdigest()[:8]
    baseline = cache / f"{label.replace('/', '_')}-{stamp}.json"
    if not baseline.is_file():
        subprocess.run(
            [str(COMPILER), "api-diff", str(reference / "main.my"), f"--write={baseline}"],
            cwd=cache, capture_output=True, text=True,
        )
    before = declarations(reference)
    after = declarations(directory / "project")
    changed = subprocess.run(
        [str(COMPILER), "api-diff", str(directory / "project" / "main.my"), f"--against={baseline}", "--json"],
        cwd=cache, capture_output=True, text=True,
    )
    try:
        classified = json.loads(changed.stdout)
    except json.JSONDecodeError:
        classified = {"error": changed.stderr.strip()[:200] or "api-diff produced no JSON"}
    return {
        "api_diff": {
            key: classified.get(key)
            for key in ("additive", "compatible", "breaking", "unchanged")
            if key in classified
        } or classified,
        "declarations_before": len(before),
        "declarations_after": len(after),
        "declarations_added": sorted(set(after) - set(before)),
        "declarations_removed": sorted(set(before) - set(after)),
    }


HOST_FAILURE = re.compile(r"host failure|NativeToolFailed|sub-compilation of .* failed")


def infrastructure_failures(report_path: Path) -> list[str]:
    """Commands that died in the toolchain rather than disagreeing about the change."""
    if not report_path.is_file():
        return []
    report = json.loads(report_path.read_text())
    hits = []
    for step in report.get("steps", []):
        for command in step.get("commands", []):
            stderr = command.get("stderr") or ""
            if HOST_FAILURE.search(stderr):
                hits.append(step.get("id", "?"))
    return hits


def verify(directory: Path, task: str) -> dict:
    """Copy the hidden material in and run scripts/verify.py over it."""
    hidden = HIDDEN / task
    if not (hidden / "verify.json").is_file():
        raise SystemExit(f"run: no hidden manifest at {hidden / 'verify.json'}")
    staging = directory / "_verify"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir()
    shutil.copytree(HERE / "pack" / "harness", staging / "harness")
    for name in ("verify.json", "cases.tsv"):
        if (hidden / name).is_file():
            shutil.copy2(hidden / name, staging / name)
    for name in ("golden", "inputs"):
        if (hidden / name).is_dir():
            shutil.copytree(hidden / name, staging / name)
    if (hidden / "tests").is_dir():
        shutil.copytree(hidden / "tests", directory / "project" / "tests", dirs_exist_ok=True)
    environment = dict(os.environ)
    environment["ZIG_GLOBAL_CACHE_DIR"] = str(directory / ".cache" / "zig-global")
    environment["ZIG_LOCAL_CACHE_DIR"] = str(directory / ".cache" / "zig-local")
    result = subprocess.run(
        [sys.executable, str(VERIFY), "verify.json", "--report", str(staging / "report.json")],
        cwd=staging, capture_output=True, text=True, env=environment,
    )
    report = json.loads((staging / "report.json").read_text()) if (staging / "report.json").is_file() else {}
    return {
        "passed": bool(report.get("selected_passed")) and result.returncode == 0,
        "exit": result.returncode,
        "report": str(staging / "report.json"),
        "steps": [{"id": step["id"], "status": step["status"]} for step in report.get("steps", [])],
        "infrastructure_failures": infrastructure_failures(staging / "report.json"),
    }


def prune_caches(directory: Path) -> list[str]:
    """Drop the compiler's caches from a finished working copy.

    The sources, the request, the session transcript and the verification report
    are the evidence; the object caches are not, and sixty-three of them are
    gigabytes.
    """
    removed = []
    for relative in (".cache", ".zig-cache", ".mylang-cache",
                     "project/.mylang-cache", "project/.cache", "project/.zig-cache"):
        target = directory / relative
        if target.exists():
            shutil.rmtree(target, ignore_errors=True)
            removed.append(relative)
    # The verification scaffold is reproducible from the hidden pack; its report
    # is the evidence and stays.
    staging = directory / "_verify"
    for name in ("harness", "golden", "inputs", "cases.tsv", "verify.json"):
        target = staging / name
        if target.is_dir():
            shutil.rmtree(target, ignore_errors=True)
            removed.append(f"_verify/{name}")
        elif target.is_file():
            target.unlink()
            removed.append(f"_verify/{name}")
    return removed


def one_run(arm: str, task: str, run: int, timeout: float, dry_run: bool, verify_only: bool, chain_parent: Path | None,
            cli: str = "dsh", keep_caches: bool = False, chain_step: int | None = None,
            chain_repetition: int = 1, chain_attempt: int = 1) -> dict:
    directory = build_working_copy(arm, task, run, chain_parent, chain_step, chain_repetition, chain_attempt)
    reference = arm_dir(arm) if chain_parent is None else chain_parent
    record = {
        "version": 1,
        "arm": arm,
        "task": task,
        "run": run,
        "toolchain": toolchain(),
        "chain_parent": None if chain_parent is None else str(chain_parent),
        "chain": chain_step is not None,
        "chain_step": chain_step,
        "chain_repetition": chain_repetition if chain_step is not None else None,
        "chain_attempt": chain_attempt if chain_step is not None else None,
        "work_dir": str(directory),
        "request": str(directory / "request.md"),
    }
    if verify_only:
        record["launched"] = False
    else:
        prompt = maintainer_prompt(arm, task)
        (directory / "PROMPT.md").write_text(prompt)
        if dry_run:
            record.update(launched=False, dry_run=True, command=[part.replace("{prompt}", prompt) for part in launcher(cli)])
            return record
        record.update(launched=True)
        session = launch(directory, prompt, timeout, cli)
        (directory / "session.txt").write_text(session.pop("stdout"))
        (directory / "session.err").write_text(session.pop("stderr"))
        record["session_launch"] = session
        started = datetime.fromisoformat(session["started_utc"])
        record["session"] = read_session_logs(directory, started)
    record["diff"] = diff_against_arm(directory, reference)
    record["interface"] = interface_changes(directory, reference, arm)
    record["verify"] = verify(directory, task)
    session = record.get("session") or {}
    if record.get("launched") and not session.get("logs"):
        record["verdict"] = "discarded-no-log"
    elif session.get("delegation_depth", 0) > 0:
        record["verdict"] = "discarded-delegation"
    elif record["verify"]["passed"]:
        record["verdict"] = "passed"
    elif record["verify"].get("infrastructure_failures"):
        # The toolchain died; that says nothing about the change, so the cell is
        # rerun rather than scored as a failure.
        record["verdict"] = "discarded-infrastructure"
    else:
        record["verdict"] = "failed"
    if not keep_caches and not dry_run:
        record["pruned"] = prune_caches(directory)
    record["finished_utc"] = now()
    return record


def save(record: dict) -> Path:
    label = record["arm"].strip("/").replace("/", "_").replace("..", "_")
    if record.get("chain"):
        name = chain_name(record.get("chain_repetition") or 1, record["chain_step"], record.get("chain_attempt") or 1)
    else:
        name = str(record["run"])
    path = RUNS / label / record["task"] / f"{name}.json"
    if path.is_file():
        # Never lose a run: any existing record with the same key is preserved
        # beside the new one, whatever its verdict.
        previous = json.loads(path.read_text())
        index = 1
        while (path.parent / f"{name}.previous-{index}.json").exists():
            index += 1
        (path.parent / f"{name}.previous-{index}.json").write_text(json.dumps(previous, indent=2) + "\n")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(record, indent=2) + "\n")
    (path.parent / f"{path.stem}.session.txt").write_text(
        (Path(record["work_dir"]) / "session.txt").read_text() if (Path(record["work_dir"]) / "session.txt").is_file() else ""
    )
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--arm", required=True, help="a design under designs/ or a directory path")
    parser.add_argument("--task", help="task id, e.g. T1")
    parser.add_argument("--n", type=int, default=1, help="run index (default 1)")
    parser.add_argument("--runs", type=int, default=1, help="number of independent runs to launch")
    parser.add_argument("--chain", help="comma-separated task ids run in sequence, each on the previous result")
    parser.add_argument("--chain-rep", type=int, default=None, help="chain repetition key (default: --n)")
    parser.add_argument("--attempt", type=int, default=1, help="attempt key within a chain repetition")
    parser.add_argument("--timeout", type=float, default=7200.0, help="seconds per session (default 7200)")
    parser.add_argument("--cli", default="dsh", help="command template to use from velocity/goal.json (default dsh)")
    parser.add_argument("--dry-run", action="store_true", help="build the working copy and print the command only")
    parser.add_argument("--verify-only", action="store_true", help="skip the session; verify what is in the working copy")
    parser.add_argument("--no-save", action="store_true", help="do not write a run record")
    parser.add_argument("--keep-caches", action="store_true", help="keep the working copy's compiler caches")
    args = parser.parse_args()
    if args.chain and args.task:
        raise SystemExit("run: --chain and --task are exclusive")
    if not args.chain and not args.task:
        raise SystemExit("run: one of --task or --chain is required")
    if args.chain:
        parent = None
        repetition = args.chain_rep if args.chain_rep is not None else args.n
        for index, task in enumerate([part.strip() for part in args.chain.split(",") if part.strip()], start=1):
            record = one_run(args.arm, task, args.n, args.timeout, args.dry_run, args.verify_only, parent,
                             args.cli, args.keep_caches, index, repetition, args.attempt)
            if not args.no_save and not args.dry_run:
                path = save(record)
                print(f"{record['verdict']:<22} chain {task} -> {path}")
            else:
                print(json.dumps(record, indent=2))
            if record.get("dry_run"):
                break
            if not record["verify"]["passed"]:
                print(f"chain stops: {task} did not verify")
                return 1
            parent = Path(record["work_dir"]) / "project"
        return 0
    status = 0
    for offset in range(args.runs):
        run = args.n + offset
        record = one_run(args.arm, args.task, run, args.timeout, args.dry_run, args.verify_only, None, args.cli, args.keep_caches)
        if args.dry_run or args.no_save:
            print(json.dumps(record, indent=2))
        else:
            path = save(record)
            token_cost = (record.get("session") or {}).get("usage", {}).get("cost")
            print(f"{record['verdict']:<22} {args.arm}/{args.task}/{run}  cost={token_cost}  {path}")
        if record.get("verdict") in ("failed", "discarded-no-log"):
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""One attempt: a case, an arm, a repetition, and a sealed, graded snapshot.

The participant works in a copy holding only the faulty project, the task brief,
the public examples and `bin/mylang` (the arm's wrapper). Everything the
measurement needs is coordinator-side: the event log the wrapper appends to, the
invocation limit it enforces, the sealed snapshot taken afterwards, and the
public and hidden grading of that snapshot with the frozen compiler — never the
participant's editable files and never the participant's wrapper.

    python3 experiments/diagnostic-feedback/run.py --cohort m1 --arm json_fix \
        --case checked-result-a --repeat 1 [--attempt 1] [--reason "…"]

Evidence goes to `cohorts/<cohort>/runs/<arm>/<case>/<repeat>/<attempt>/` and an
existing destination is refused.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(REPO / "experiments" / "cascade"))
import cohort  # noqa: E402
import conditions  # noqa: E402
import events  # noqa: E402
import run as runlib  # noqa: E402

CASES = HERE / "cases"
COHORTS = HERE / "cohorts"
WORK = HERE / "work"
VERIFY = REPO / "scripts" / "verify.py"
INVOCATION_LIMIT = 20

PROMPT = """# Fix the program

{request}

You are working in `project/`. `bin/mylang` is the installed compiler:
`bin/mylang check project/main.my`, `bin/mylang run project/main.my -- <arguments>`.

The same behavior is required for every input, not only the examples in `public/`.
Read `public/expected.json` for the examples this task will be checked against, and run them however you like.

Constraints:

- Work only inside this directory; do not read or write anything outside it and do not spawn subagents.
- At most {limit} compiler invocations are available for this attempt.
- Change only what the request requires.

When you are done, reply with a short final message: what you changed and the exact command you ran with its result.
"""


def case_directory(case: str) -> Path:
    for split in ("test", "dev"):
        candidate = CASES / split / case
        if (candidate / "project").is_dir():
            return candidate
    raise SystemExit(f"no case {case!r} under {CASES}")


def public_checks(case: str) -> list[dict]:
    path = case_directory(case) / "public" / "expected.json"
    return json.loads(path.read_text())["cases"] if path.is_file() else []


def build(cohort_id: str, arm: str, case: str, repetition: int, attempt: int) -> tuple[Path, str]:
    source = case_directory(case)
    directory = WORK / cohort_id / arm / case / str(repetition) / str(attempt)
    if directory.exists():
        shutil.rmtree(directory)
    shutil.copytree(source / "project", directory / "project")
    if (source / "public").is_dir():
        shutil.copytree(source / "public", directory / "public")
    conditions.install(directory / "bin", arm)
    (directory / "request.md").write_text((source / "case.json").read_text()
                                          if False else (source / "request.md").read_text())
    limit = INVOCATION_LIMIT
    (directory / "PROMPT.md").write_text(PROMPT.format(
        request=(source / "request.md").read_text().split("\n", 1)[-1].strip(), limit=limit))
    initial, _ = events.inventory(directory / "project")
    return directory, initial


def grade(directory: Path, case: str, snapshot: Path) -> dict:
    """Run the public examples and the hidden manifest against the sealed copy.

    Grading uses the frozen compiler directly: the participant's wrapper, limits
    and environment play no part in it.
    """
    checks = public_checks(case)
    public_failures = []
    for check in checks:
        completed = subprocess.run(
            [str(runlib.COMPILER), "run", str(snapshot / "main.my"), "--", *check.get("args", [])],
            capture_output=True, text=True, cwd=snapshot,
        )
        if completed.returncode != 0 or completed.stdout != check["stdout"]:
            public_failures.append({"args": check.get("args", []), "exit": completed.returncode,
                                    "expected": check["stdout"], "actual": completed.stdout})
    hidden = case_directory(case) / "hidden" / "verify.json"
    manifest = json.loads(hidden.read_text())
    for step in manifest["steps"]:
        # `args` is this study's field; verify.py accepts only its own step keys,
        # so the run command is built here and the custom key is removed.
        args = step.pop("args")
        step["commands"] = [[str(runlib.COMPILER), "run", str(snapshot / "main.my"), "--", *args]]
    staging = directory / "_verify"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir()
    (staging / "verify.json").write_text(json.dumps(manifest, indent=2) + "\n")
    environment = dict(os.environ)
    environment["ZIG_GLOBAL_CACHE_DIR"] = str(directory / ".cache" / "zig-global")
    environment["ZIG_LOCAL_CACHE_DIR"] = str(directory / ".cache" / "zig-local")
    completed = subprocess.run(
        [sys.executable, str(VERIFY), "verify.json", "--report", str(staging / "report.json")],
        cwd=staging, capture_output=True, text=True, env=environment,
    )
    # A verifier that could not run must be visible, not mistaken for a failed
    # candidate: an empty or absent report is a grader incident.
    report_path = staging / "report.json"
    report = {}
    if report_path.is_file() and report_path.stat().st_size:
        try:
            report = json.loads(report_path.read_text())
        except json.JSONDecodeError:
            report = {}
    grader_ok = bool(report)
    return {
        "public_acceptance": not public_failures and bool(checks),
        "public_failures": public_failures,
        "hidden_acceptance": grader_ok and bool(report.get("selected_passed")) and completed.returncode == 0,
        "grader_ok": grader_ok,
        "grader_stderr": "" if grader_ok else completed.stderr.strip()[-400:],
        "hidden_steps": [{"id": step["id"], "status": step["status"]} for step in report.get("steps", [])],
    }


def one(cohort_id: str, arm: str, case: str, repetition: int, attempt: int, reason: str | None,
        predecessor: Path | None, dry_run: bool, keep_work: bool = False) -> dict:
    root = COHORTS / cohort_id
    destination = cohort.attempt_dir(root, arm, case, repetition, attempt)
    directory, initial = build(cohort_id, arm, case, repetition, attempt)
    event_log = directory / ".events" / "events.jsonl"
    os.environ["MYLANG_EVENT_LOG"] = str(event_log)
    os.environ["MYLANG_PROJECT"] = str(directory / "project")
    os.environ["MYLANG_LIMIT"] = str(INVOCATION_LIMIT)
    os.environ["MYLANG_COHORT"] = cohort_id
    os.environ["MYLANG_ATTEMPT"] = f"{arm}/{case}/{repetition}/{attempt}"
    os.environ["MYLANG_INITIAL_HASH"] = initial
    prompt = (directory / "PROMPT.md").read_text()
    if dry_run:
        return {"dry_run": True, "arm": arm, "case": case, "repetition": repetition, "attempt": attempt,
                "work_dir": str(directory), "event_log": str(event_log),
                "command": [part.replace("{prompt}", prompt[:60] + "…") for part in runlib.launcher("dsh")]}
    cohort.reserve(destination)
    session = runlib.launch(directory, prompt, 900.0)
    (destination / "session.txt").write_text(session.pop("stdout"))
    (destination / "session.err").write_text(session.pop("stderr"))
    snapshot = destination / "sealed"
    sealed_hash = cohort.seal(directory / "project", snapshot)
    started = datetime.fromisoformat(session["started_utc"])
    session_signals = runlib.read_session_logs(directory.resolve(), started)
    event_records, coverage = events.read_events(event_log)
    metrics = events.aggregate(event_records, initial)
    grading = grade(directory, case, snapshot)
    record = {
        "version": 2,
        "cohort_id": cohort_id,
        "arm": arm,
        "case": case,
        "repetition": repetition,
        "attempt": attempt,
        "attempt_reason": reason,
        "predecessor": str(predecessor) if predecessor else None,
        "work_dir": str(directory),
        "initial_source_sha256": initial,
        "sealed_source_sha256": sealed_hash,
        "termination": "timeout" if session.get("timed_out") else "completed",
        "session_launch": session,
        "session": session_signals,
        "events": {"coverage": coverage, "metrics": metrics},
        "grading": grading,
        "hidden_acceptance": grading["hidden_acceptance"],
        "public_acceptance": grading["public_acceptance"],
        "finished_utc": datetime.now(timezone.utc).isoformat(),
    }
    (destination / "record.json").write_text(json.dumps(record, indent=2) + "\n")
    shutil.copy2(event_log, destination / "events.jsonl") if event_log.is_file() else None
    # The sealed snapshot, the events and the transcript are the evidence; the
    # working copy is scratch, and a hundred of them fill a quota.
    runlib.prune_caches(directory)
    if not keep_work:
        shutil.rmtree(directory, ignore_errors=True)
    return record


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cohort", required=True)
    parser.add_argument("--arm", required=True, choices=conditions.CONDITIONS)
    parser.add_argument("--case", required=True)
    parser.add_argument("--repeat", type=int, default=1)
    parser.add_argument("--attempt", type=int, default=1)
    parser.add_argument("--reason", default=None, help="required when attempt > 1")
    parser.add_argument("--predecessor", type=Path, default=None)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--keep-work", action="store_true", help="keep the per-attempt working copy (debugging)")
    args = parser.parse_args()
    if args.attempt > 1 and not args.reason:
        raise SystemExit("a retry needs --reason; it is recorded with a link to its predecessor")
    manifest_path = COHORTS / args.cohort / "manifest.json"
    if not args.dry_run and manifest_path.is_file():
        manifest = cohort.load(manifest_path)
        if not cohort.scheduled(manifest, args.arm, args.case, args.repeat):
            raise SystemExit(f"{args.arm}/{args.case}/{args.repeat} is not in the {args.cohort} schedule")
    record = one(args.cohort, args.arm, args.case, args.repeat, args.attempt, args.reason,
                 args.predecessor, args.dry_run, args.keep_work)
    if args.dry_run:
        print(json.dumps(record, indent=2))
        return 0
    metrics = record["events"]["metrics"]
    print(f"{'HIDDEN-OK' if record['hidden_acceptance'] else 'hidden-NO':<10} {args.arm}/{args.case}/{args.repeat}"
          f"  invocations={metrics['invocations']} failed={metrics['failed_compiler_invocations']}"
          f" failed_on_changed={metrics['failed_checks_on_changed_source']}"
          f" public={'ok' if record['public_acceptance'] else 'fail'}"
          f" outcome={'timeout' if record['termination'] == 'timeout' else 'completed'}")
    return 0 if record["hidden_acceptance"] else 1


if __name__ == "__main__":
    sys.exit(main())

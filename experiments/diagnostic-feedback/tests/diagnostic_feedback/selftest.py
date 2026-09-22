#!/usr/bin/env python3
"""M0 acceptance: the regressions the plan requires before any cohort is frozen.

Every check runs on temporary fixtures with a scripted fake compiler, so no model
call and no real session is involved.

    python3 experiments/diagnostic-feedback/tests/diagnostic_feedback/selftest.py
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
FEEDBACK = HERE.parents[1]
sys.path.insert(0, str(FEEDBACK))
import cohort  # noqa: E402
import conditions  # noqa: E402
import events  # noqa: E402

RESULTS: list[tuple[str, bool, str]] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    RESULTS.append((name, bool(condition), detail))
    print(f"  {'ok  ' if condition else 'FAIL'} {name}{'' if condition else '  ' + detail}")


FAKE = '''#!/usr/bin/env python3
"""Scripted compiler: takes the next step from a plan file, one call at a time."""
import json
import os
import sys
from pathlib import Path

root = Path(os.environ["FAKE_ROOT"])
counter = root / "counter"
index = int(counter.read_text()) if counter.is_file() else 0
counter.write_text(str(index + 1))
plan = json.loads((root / "plan.json").read_text())
step = plan[min(index, len(plan) - 1)]
for name in step.get("edit", []):
    (root / "project" / name).write_text("module main\\n\\n\\ndef main() -> int:\\n    return 0\\n")
sys.stdout.write(step.get("stdout", ""))
sys.stderr.write(step.get("stderr", ""))
sys.exit(step.get("exit", 0))
'''

DIAGNOSTIC = "main.my:5:5: error[E_TYPE]: expected int, found bool\n      return a > b\n      ^\n"


def fixture(root: Path, plan: list[dict]) -> Path:
    """A working copy with a fake compiler and one arm's wrapper installed."""
    (root / "project").mkdir(parents=True)
    (root / "project" / "main.my").write_text("module main\n")
    (root / "bin").mkdir()
    fake = root / "fake-compiler"
    fake.write_text(FAKE)
    fake.chmod(0o755)
    (root / "plan.json").write_text(json.dumps(plan))
    conditions.install(root / "bin", "json_fix", compiler=fake)
    return root


def invoke(root: Path, arm: str = "json_fix", args: list[str] | None = None,
           log: Path | None = None, limit: int = 20) -> subprocess.CompletedProcess:
    conditions.install(root / "bin", arm, compiler=root / "fake-compiler")
    environment = {**os.environ, "FAKE_ROOT": str(root),
                   "MYLANG_EVENT_LOG": str(log if log else root / ".events" / "events.jsonl"),
                   "MYLANG_PROJECT": str(root / "project"), "MYLANG_LIMIT": str(limit),
                   "MYLANG_INITIAL_HASH": events.inventory(root / "project")[0]}
    return subprocess.run([str(root / "bin" / "mylang"), *(args or ["check", "project/main.my"])],
                          capture_output=True, text=True, cwd=root, env=environment)


def main() -> int:
    # Scratch on the workspace filesystem: /tmp here is a 16 GB tmpfs, and a
    # study that fills it breaks its own tooling.
    scratch = FEEDBACK / ".tmp" / "selftest"
    shutil.rmtree(scratch, ignore_errors=True)
    scratch.mkdir(parents=True)
    try:
        # 1. prose is not a measurement
        root = fixture(scratch / "prose", [{"stderr": DIAGNOSTIC, "exit": 1}])
        (root / "transcript.txt").write_text(DIAGNOSTIC * 3)
        check("assistant prose contributes no events", events.read_events(root / ".events" / "events.jsonl")[1]["missing"])

        # 2. one process, several diagnostics
        root = fixture(scratch / "multi", [{"stderr": DIAGNOSTIC.replace("E_TYPE", "E_TYPE") + DIAGNOSTIC.replace("E_UNKNOWN_NAME", "E_UNKNOWN_NAME"), "exit": 1}])
        invoke(root)
        records, coverage = events.read_events(root / ".events" / "events.jsonl")
        check("one process with two diagnostics is one event", len(records) == 1 and len(records[0]["diagnostic_codes"]) == 2,
              f"{len(records)} events, {records[0]['diagnostic_codes'] if records else []}")

        # 3. two compiler calls in one shell command
        root = fixture(scratch / "two", [{"stderr": DIAGNOSTIC, "exit": 1}])
        conditions.install(root / "bin", "text", compiler=root / "fake-compiler")
        environment = {**os.environ, "FAKE_ROOT": str(root), "MYLANG_EVENT_LOG": str(root / ".events" / "events.jsonl"),
                       "MYLANG_PROJECT": str(root / "project"), "MYLANG_LIMIT": "20",
                       "MYLANG_INITIAL_HASH": events.inventory(root / "project")[0]}
        subprocess.run(["bash", "-c", "bin/mylang check project/main.my; bin/mylang check project/main.my"],
                       cwd=root, env=environment, capture_output=True)
        records, _ = events.read_events(root / ".events" / "events.jsonl")
        check("two invocations in one shell command are two events", len(records) == 2, f"{len(records)}")

        # 4. a clean check
        root = fixture(scratch / "clean", [{"stdout": "ok\n", "exit": 0}])
        completed = invoke(root)
        records, _ = events.read_events(root / ".events" / "events.jsonl")
        check("a successful check is one clean event",
              records[0]["outcome"] == "success" and records[0]["diagnostic_codes"] == [] and completed.stdout == "ok\n")

        # 5. failure with non-diagnostic stderr
        root = fixture(scratch / "crash", [{"stderr": "segmentation fault\n", "exit": 139}])
        invoke(root)
        records, _ = events.read_events(root / ".events" / "events.jsonl")
        check("a crash is not a source error", records[0]["outcome"] == "runtime_failure" and records[0]["diagnostic_codes"] == [])

        # 6. repeated delivery of the same event
        root = fixture(scratch / "dupe", [{"stderr": DIAGNOSTIC, "exit": 1}])
        invoke(root)
        log = root / ".events" / "events.jsonl"
        log.write_text(log.read_text() + log.read_text())
        records, coverage = events.read_events(log)
        check("a repeated delivery is counted once", len(records) == 1 and coverage["duplicates"] == 1)

        # 7. truncated event
        root = fixture(scratch / "trunc", [{"stderr": DIAGNOSTIC, "exit": 1}])
        invoke(root)
        log = root / ".events" / "events.jsonl"
        log.write_text(log.read_text().rstrip("\n")[:-12])
        records, coverage = events.read_events(log)
        check("a truncated event is missing, not clean", coverage["truncated"] == 1 and not records)

        # 8. source changing under the compiler
        root = fixture(scratch / "moving", [{"stderr": DIAGNOSTIC, "exit": 1, "edit": ["main.my"]}])
        invoke(root)
        records, _ = events.read_events(root / ".events" / "events.jsonl")
        metrics = events.aggregate(records, "unrelated-initial-hash")
        check("a source change during a check is flagged and not counted",
              records[0]["source_stable"] is False and metrics["failed_checks_on_changed_source"] == 0)

        # 9. a green compiler run is not task acceptance
        root = fixture(scratch / "green", [{"exit": 0}])
        invoke(root)
        records, _ = events.read_events(root / ".events" / "events.jsonl")
        initial = events.inventory(root / "project")[0]
        metrics = events.aggregate(records, initial)
        check("first compiler green is recorded but is not acceptance",
              metrics["first_compiler_green_ns"] is not None and "hidden_acceptance" not in metrics)

        # 10. the invocation limit is enforced by the runner's wrapper
        root = fixture(scratch / "limit", [{"exit": 0}])
        log = root / ".events" / "events.jsonl"
        for _ in range(3):
            invoke(root, limit=3, log=log)
        blocked = invoke(root, limit=3, log=log)
        records, _ = events.read_events(log)
        # The refused call is itself recorded: an attempt that runs out of its
        # invocation budget is an unsuccessful attempt, not an excluded row.
        check("the invocation limit stops the compiler", blocked.returncode == 66
              and records[-1]["outcome"] == "limit_reached" and len(records) == 4,
              f"exit={blocked.returncode} records={len(records)}")

        # 11. rendering: one remedy, two representations, identical data
        root = fixture(scratch / "render", [{"stderr": DIAGNOSTIC, "exit": 1}])
        outputs = {}
        for arm in conditions.CONDITIONS:
            log = root / f".events/{arm}.jsonl"
            invoke(root, arm=arm, log=log)
            records, _ = events.read_events(log)
            outputs[arm] = (records[0], )
        text_plain = invoke(root, arm="text", log=root / ".events/t1.jsonl").stderr
        text_fix = invoke(root, arm="text_fix", log=root / ".events/t2.jsonl").stderr
        json_plain = json.loads(invoke(root, arm="json", log=root / ".events/t3.jsonl").stderr)
        json_fix = json.loads(invoke(root, arm="json_fix", log=root / ".events/t4.jsonl").stderr)
        fields = ("code", "message", "path", "line", "column", "snippet", "notes")
        check("text is unchanged and text_fix appends a remedy",
              text_plain == DIAGNOSTIC and "note:" in text_fix and DIAGNOSTIC.strip() in text_fix)
        check("json and json_fix carry the same diagnostic fields",
              all(json_plain["diagnostics"][0][field] == json_fix["diagnostics"][0][field] for field in fields))
        check("the remedy text is identical across representations",
              json_fix["diagnostics"][0]["suggested_fix"]
              and json_fix["diagnostics"][0]["suggested_fix"] in text_fix
              and "suggested_fix" not in json_plain["diagnostics"][0])
        check("no suggestion matches means the arm still renders the diagnostic",
              json.loads(invoke(root, arm="json_fix", log=root / ".events/t5.jsonl").stderr)["count"] == 1)

        # 11b. the grading path itself, on a real case: the reference repair must
        # grade hidden-OK and the faulty source must not. This is the check whose
        # absence let a broken grader reach the M1 pilot.
        import importlib.util
        spec = importlib.util.spec_from_file_location("dfrun", FEEDBACK / "run.py")
        dfrun = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(dfrun)
        case = "dev-bool"
        reference = FEEDBACK / "cases" / "dev" / case
        probe = scratch / "grade"
        (probe / "project").mkdir(parents=True)
        (probe / "project" / "main.my").write_text((reference / "reference" / "main.my").read_text())
        hidden_ok = dfrun.grade(probe, case, probe / "project")["hidden_acceptance"]
        (probe / "project" / "main.my").write_text((reference / "project" / "main.my").read_text())
        hidden_no = dfrun.grade(probe, case, probe / "project")["hidden_acceptance"]
        check("the grader accepts the reference repair and rejects the faulty source",
              hidden_ok and not hidden_no, f"reference={hidden_ok} faulty={hidden_no}")

        # 12. evidence is reserved, never overwritten
        destination = scratch / "evidence"
        cohort.reserve(destination)
        refused = False
        try:
            cohort.reserve(destination)
        except SystemExit:
            refused = True
        check("an existing attempt directory is refused", refused)

        # 13. incompatible manifests cannot be pooled
        left = cohort.new_manifest("a", ["c"], ["text"], 1, {"compiler_sha256": "x", "model": "m"}, 1)
        right = cohort.new_manifest("b", ["c"], ["text"], 1, {"compiler_sha256": "y", "model": "m"}, 1)
        check("differing identities are reported", cohort.incompatible(left, right) == ["compiler_sha256"])

        # 14. a follow-up cannot change a frozen cohort's numbers
        manifest = cohort.new_manifest("frozen", ["case"], ["text"], 1, {"compiler_sha256": "x"}, 1)
        root = scratch / "frozen"
        (root / "runs" / "text" / "case" / "1" / "1").mkdir(parents=True)
        (root / "runs" / "text" / "case" / "1" / "1" / "record.json").write_text(json.dumps(
            {"arm": "text", "case": "case", "repetition": 1, "attempt": 1, "hidden_acceptance": True,
             "events": {"metrics": {"failed_checks_on_changed_source": 2}}}))
        before = score_cohort(manifest, root)
        (root / "runs" / "text" / "case" / "1" / "2").mkdir(parents=True)
        (root / "runs" / "text" / "case" / "1" / "2" / "record.json").write_text(json.dumps(
            {"arm": "text", "case": "case", "repetition": 1, "attempt": 2, "hidden_acceptance": True,
             "events": {"metrics": {"failed_checks_on_changed_source": 99}}}))
        after = score_cohort(manifest, root)
        check("an unlisted follow-up does not change the score", before == after)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    failures = [name for name, ok, _ in RESULTS if not ok]
    print(f"\n{len(RESULTS) - len(failures)}/{len(RESULTS)} checks passed")
    return 1 if failures else 0


def score_cohort(manifest: dict, root: Path) -> dict:
    """The scorer's contract in miniature: manifest-listed attempts only."""
    totals: dict[str, int] = {}
    for row in manifest["schedule"]:
        directory = root / "runs" / row["arm"] / row["case"] / str(row["repetition"])
        listed = {1}
        for attempt in sorted(directory.iterdir()) if directory.is_dir() else []:
            if int(attempt.name) not in listed:
                continue
            record = json.loads((attempt / "record.json").read_text())
            totals[row["arm"]] = totals.get(row["arm"], 0) + record["events"]["metrics"]["failed_checks_on_changed_source"]
    return totals


if __name__ == "__main__":
    sys.exit(main())

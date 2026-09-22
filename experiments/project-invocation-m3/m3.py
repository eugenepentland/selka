#!/usr/bin/env python3
"""M3: does project configuration remove repeated invocation work?

One bounded test of one claim: specifying a project's root, entrypoint and
verification manifest once reduces the effort agents spend delivering correct
changes across that project's workflows. The design, thresholds and stopping
rules are the frozen M3 runbook; this file is its runner.

    python3 experiments/project-invocation-m3/m3.py materialize
    python3 experiments/project-invocation-m3/m3.py selftest
    python3 experiments/project-invocation-m3/m3.py preflight --all
    python3 experiments/project-invocation-m3/m3.py freeze --cohort pilot --seed 20260920
    python3 experiments/project-invocation-m3/m3.py run --cohort pilot --dry-run
    python3 experiments/project-invocation-m3/m3.py run --cohort pilot --max-new-sessions 8
    python3 experiments/project-invocation-m3/m3.py monitor --cohort pilot
    python3 experiments/project-invocation-m3/m3.py score --cohort pilot

Only `run` may launch model sessions; every other command is a local check,
freezing, monitoring or scoring step. `freeze` refuses an existing cohort, and
`run` re-verifies the entire frozen identity before each new session.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import functools
import hashlib
import json
import os
from pathlib import Path
import random
import shutil
import statistics
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
for extra in (HERE, REPO / "experiments" / "diagnostic-feedback", REPO / "experiments" / "cascade"):
    sys.path.insert(0, str(extra))

from m3lib import cases as caselib  # noqa: E402
from m3lib import grading, pack, scoring, workspace  # noqa: E402
import cohort  # noqa: E402  — the immutable manifest, seal and reservation rules
import events  # noqa: E402  — the M1 invocation accounting, reused unchanged
import run as cascade_run  # noqa: E402  — the repository's headless session launcher

COHORTS = HERE / "cohorts"
WORK = HERE / "work"
EVIDENCE = HERE / "evidence"
CONTROLS = HERE / "controls" / "base"
LAUNCHER = HERE / "project"
SEEDS = {"pilot": 20260920, "main": 20260921}
DEADLINE_SECONDS = 900.0
CACHE_POLICY = ("fresh per-session ZIG_GLOBAL_CACHE_DIR/ZIG_LOCAL_CACHE_DIR and project verification "
                "cache under the session's .m3/, outside the application source tree")
REPETITIONS = {"pilot": 2, "main": 3}
ARMS = {"pilot": ["manual"], "main": ["manual", "automatic"]}
PURPOSE = {"pilot": "M3 headroom pilot: manual arm only, two fresh sessions per development task",
           "main": "M3 main cohort: six held-out tasks x two arms x three repetitions"}
PROMPT_HEADER = """# Session

You are one participant in a bounded experiment on how agents deliver correct
changes. Everything you need is in this working copy.
"""


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def digest_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def digest_file(path: Path) -> str:
    return digest_bytes(path.read_bytes())


def case_pack_digest() -> str:
    """A hash of every brief, mutation and hidden fixture in the case pack."""
    digest = hashlib.sha256()
    digest.update((HERE / "m3lib" / "cases.py").read_bytes())
    for path in sorted((HERE / "pack" / "cases").rglob("*")):
        if path.is_file():
            digest.update(path.relative_to(HERE).as_posix().encode())
            digest.update(path.read_bytes())
    return digest.hexdigest()


def runner_digest() -> str:
    """A hash of the runner itself: a cohort freezes the code that scored it."""
    digest = hashlib.sha256()
    for path in [HERE / "m3.py", *sorted((HERE / "m3lib").glob("*.py"))]:
        digest.update(path.name.encode())
        digest.update(path.read_bytes())
    return digest.hexdigest()


@functools.lru_cache(maxsize=1)
def model_settings() -> dict:
    """The model identity the eventual participant sessions use, from the harness."""
    settings = Path.home() / ".dsh" / "settings.yaml"
    model, effort = "deepseek-v4-flash", "max"
    if settings.is_file():
        for line in settings.read_text().splitlines():
            if "model:" in line:
                model = line.split("model:", 1)[1].strip()
            if "reasoningEffort:" in line:
                effort = line.split("reasoningEffort:", 1)[1].strip()
    return {"model": model, "reasoning_effort": effort,
            "settings_sha256": digest_file(settings) if settings.is_file() else None,
            "launcher": cascade_run.launcher("dsh")}


def observed_identity(split: str) -> dict:
    """Everything a cohort freezes: tools, applications, cases, rules and settings."""
    tools = pack.load_tools()
    applications = {name: pack.verify_app(name) for name in pack.APP_SPECS}
    return {
        "version": "m3-cohort-identity-v1",
        "compiler_sha256": tools["tools"]["mylang"]["sha256"],
        "host_sha256": (tools["tools"].get("mylang-io") or {}).get("sha256"),
        "qbe_sha256": tools["tools"]["qbe"]["sha256"],
        "workflow_scripts_digest": tools["scripts_digest"],
        "events_module_sha256": tools["events_module"]["sha256"],
        "launcher_sha256": digest_file(LAUNCHER),
        "runner_sha256": runner_digest(),
        "case_pack_sha256": case_pack_digest(),
        "applications": {name: record["digest"] for name, record in applications.items()},
        "arms": ARMS[split],
        "repetitions": REPETITIONS[split],
        "session_deadline_s": DEADLINE_SECONDS,
        "invocation_limit": None,
        "cache_policy": CACHE_POLICY,
        "case_split": split,
        "model": model_settings()["model"],
        "reasoning_effort": model_settings()["reasoning_effort"],
    }


def identity_differences(frozen: dict, observed: dict) -> list[str]:
    """Fields that differ between a frozen manifest and the current checkout."""
    ignored = {"captured_utc"}
    differences = []
    for key in sorted(set(frozen) | set(observed)):
        if key in ignored:
            continue
        if frozen.get(key) != observed.get(key):
            differences.append(f"{key}: frozen={frozen.get(key)!r} observed={observed.get(key)!r}")
    return differences


# ── materialize ───────────────────────────────────────────────────────────────

def cmd_materialize(args) -> int:
    tools = pack.materialize_tools()
    print(f"frozen tools: {tools['tools']['mylang']['sha256'][:16]} compiler, "
          f"host {'present' if (tools['tools'].get('mylang-io') or {}).get('present') else 'absent'}")
    for name in pack.APP_SPECS:
        record = pack.materialize_app(name)
        print(f"frozen application {name}: {len(record['files'])} files, digest {record['digest'][:16]}")
    return 0


# ── preflight ─────────────────────────────────────────────────────────────────

def prepare_variant(case: dict, variant: str, destination: Path) -> dict:
    """Materialize one preflight variant of an application: reference, seed or wrong repair."""
    snapshot = pack.APPS / case["application"] / "snapshot"
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(snapshot, destination,
                    ignore=shutil.ignore_patterns("__pycache__", ".mylang-cache", ".cache", ".zig-cache"))
    evidence = {"variant": variant, "edits": []}
    if variant == "reference":
        return evidence
    edits = [case["mutation"]] if variant == "regression" else (
        [case["mutation"]] + list(case["wrong_repairs"][0]["edits"]))
    if variant.startswith("wrong:"):
        wanted = variant.split(":", 1)[1]
        repair = next((row for row in case["wrong_repairs"] if row["name"] == wanted), None)
        if repair is None:
            raise SystemExit(f"case {case['id']}: no wrong repair {wanted!r}")
        edits = [case["mutation"]] + list(repair["edits"])
    for edit in edits:
        target = destination / edit["file"]
        text = target.read_text()
        if text.count(edit["find"]) != 1:
            raise SystemExit(f"case {case['id']}: edit for {edit['file']} does not match exactly once")
        target.write_text(text.replace(edit["find"], edit["replace"]))
        evidence["edits"].append({"file": edit["file"],
                                  "find_sha256": digest_bytes(edit["find"].encode()),
                                  "replace_sha256": digest_bytes(edit["replace"].encode())})
    return evidence


def preflight_case(case: dict, expected: dict, arms: dict | None = None) -> dict:
    """Reference passes, the seeded regression fails, wrong repairs are rejected."""
    tools = pack.TOOLS
    frozen_app = pack.APPS / case["application"] / "snapshot"
    root = WORK / "preflight" / case["id"]
    result = {"case": case["id"], "split": case["split"], "application": case["application"],
              "status": case["status"], "checks": {}}
    if case["status"] == "declared":
        result.update(ready=False, blocked_on=case.get("blocked_on"),
                      note="declared task specification: no runnable seed exists while the "
                           "application snapshot does not compile with the frozen toolchain")
        return result

    reference = root / "reference"
    prepare_variant(case, "reference", reference)
    staged = root / "staging"
    measured = grading.measure_hidden(reference, case={**case, "cases_root": str(caselib.CASES_ROOT)},
                                      tools=tools, staging=staged)
    if expected:
        drift = {step: {"frozen": expected.get(step), "measured": measured.get(step)}
                 for step in measured if expected.get(step) != measured.get(step)}
        result["checks"]["oracle_stable"] = {"passed": not drift, "drift": drift}
    result["checks"]["oracle"] = {"frozen_values": measured}

    reference_grade = grading.grade(reference, case={**case, "cases_root": str(caselib.CASES_ROOT)},
                                    app=case["application"], tools=tools, frozen_app=frozen_app,
                                    cases_root=caselib.CASES_ROOT, staging=root / "grade-reference",
                                    cache=root / "cache-reference", expected=measured)
    result["checks"]["reference"] = {
        "public_passed": reference_grade["public_acceptance"],
        "hidden_passed": reference_grade["hidden_acceptance"],
        "passed": reference_grade["accepted"],
        "public_seconds": reference_grade["public"]["elapsed_seconds"],
    }

    regression = root / "regression"
    prepare_variant(case, "regression", regression)
    regression_grade = grading.grade(regression, case={**case, "cases_root": str(caselib.CASES_ROOT)},
                                     app=case["application"], tools=tools, frozen_app=frozen_app,
                                     cases_root=caselib.CASES_ROOT, staging=root / "grade-regression",
                                     cache=root / "cache-regression", expected=measured)
    failed_public = [step["id"] for step in regression_grade["public"]["steps"]
                     if step["status"] != "passed"]
    failed_hidden = [step["id"] for step in (regression_grade["hidden"] or {}).get("steps", [])
                     if step["status"] != "passed"]
    result["checks"]["regression"] = {
        "public_failed_steps": failed_public, "hidden_failed_steps": failed_hidden,
        "public_rejects": bool(failed_public), "hidden_rejects": bool(failed_hidden),
        "passed": bool(failed_public and failed_hidden)}

    wrong_results = []
    for repair in case["wrong_repairs"]:
        directory = root / f"wrong-{repair['name']}"
        prepare_variant(case, f"wrong:{repair['name']}", directory)
        graded = grading.grade(directory, case={**case, "cases_root": str(caselib.CASES_ROOT)},
                               app=case["application"], tools=tools, frozen_app=frozen_app,
                               cases_root=caselib.CASES_ROOT, staging=root / f"grade-wrong-{repair['name']}",
                               cache=root / f"cache-wrong-{repair['name']}", expected=measured)
        hidden_failed = [step["id"] for step in (graded["hidden"] or {}).get("steps", [])
                         if step["status"] != "passed"]
        wrong_results.append({"name": repair["name"], "hidden_failed_steps": hidden_failed,
                              "rejected_by_hidden": bool(hidden_failed),
                              "public_passed": graded["public_acceptance"]})
    result["checks"]["wrong_repairs"] = {"results": wrong_results,
                                         "passed": all(row["rejected_by_hidden"] for row in wrong_results)}

    if arms is None:
        arms = arm_equivalence(case, reference, root / "arms")
    result["checks"]["arms"] = arms
    result["ready"] = bool(result["checks"]["reference"]["passed"]
                           and result["checks"]["regression"]["passed"]
                           and result["checks"]["wrong_repairs"]["passed"]
                           and arms["passed"])
    return result


def application_readiness() -> dict:
    """Does each frozen application pass its own public workload with frozen tools?"""
    tools = pack.TOOLS
    readiness = {}
    for name in pack.APP_SPECS:
        snapshot = pack.APPS / name / "snapshot"
        root = WORK / "preflight" / f"readiness-{name}"
        # Probe in scratch space: compiling writes caches into the working tree,
        # and the frozen snapshot's bytes are an identity nothing may mutate.
        probe = root / "probe"
        if probe.exists():
            shutil.rmtree(probe)
        shutil.copytree(snapshot, probe,
                        ignore=shutil.ignore_patterns("__pycache__", ".mylang-cache", ".cache"))
        staging = root / "staging"
        if staging.exists():
            shutil.rmtree(staging)
        grading.stage(snapshot, staging, tools=tools, app=name, frozen_app=snapshot, tests_restored=False)
        public = grading.run_manifest(staging / "verify.json", tools=tools, destination=staging,
                                      cache=root / "cache", timeout=1800.0)
        readiness[name] = {
            "snapshot_ok": pack.verify_app(name)["ok"],
            "snapshot_digest": pack.load_app(name)["digest"],
            "public_passed": public["selected_passed"],
            "public_seconds": public["elapsed_seconds"],
            "public_steps": public["steps"],
            "diagnostics": compile_diagnostics(name, probe),
            "ready": bool(public["selected_passed"]),
        }
    return readiness


def compile_diagnostics(app: str, probe: Path) -> dict:
    """The compiler's own verdict on an application copy, for the readiness record."""
    compiler = pack.TOOLS / "bin" / "mylang"
    entry = probe / pack.load_app(app)["entry"]
    completed = subprocess.run([str(compiler), "check-project", str(entry), "--diagnostics=json"],
                               cwd=probe, capture_output=True, text=True, timeout=600)
    codes: list[str] = []
    for line in completed.stdout.splitlines() + completed.stderr.splitlines():
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        code = (record.get("diagnostic") or {}).get("code")
        if code and code not in codes:
            codes.append(code)
    detail = completed.stdout.strip() or completed.stderr.strip()
    return {"exit": completed.returncode, "codes": codes, "detail_tail": detail[-500:]}


def arm_equivalence(case: dict, source: Path, root: Path) -> dict:
    """Explicit and automatic resolution must agree on the same source, from any cwd."""
    if root.exists():
        shutil.rmtree(root)
    root.mkdir(parents=True)
    request = caselib.request_text(case, "manual", int(DEADLINE_SECONDS))
    built = workspace.build(root / "ws", cohort_id="selftest", arm="manual", case=case,
                            app_snapshot=source, tools=pack.TOOLS, launcher=LAUNCHER,
                            request_text=request, docs_repo=REPO)
    comparisons = []
    working_directories = ["app", "app/tests", "app/sexpr", "."]
    for relative in working_directories:
        cwd = (root / "ws" / relative).resolve()
        if not cwd.is_dir():
            continue
        automatic = run_launcher(root / "ws", cwd, arm="automatic", explicit=None)
        explicit = run_launcher(root / "ws", cwd, arm="manual",
                                explicit=((root / "ws").resolve() / "app" / "main.my",
                                          (root / "ws").resolve() / "app" / "verify.json"))
        comparisons.append({"cwd": relative, "automatic": automatic, "explicit": explicit,
                            "agreement": launcher_agreement(automatic, explicit)})
    passed = all(row["agreement"]["identical"] for row in comparisons)
    return {"passed": passed, "comparisons": comparisons,
            "consistent_effective": len({json.dumps(row["automatic"].get("effective"), sort_keys=True)
                                         for row in comparisons if row["automatic"].get("effective")}) == 1}


def launcher_agreement(left: dict, right: dict) -> dict:
    """Do two launcher invocations produce the same effective command and feedback?"""
    fields = {}
    for key in ("effective", "status", "exit"):
        fields[key] = left.get(key) == right.get(key)
    if left.get("feedback") is None or right.get("feedback") is None:
        fields["feedback"] = left.get("feedback") == right.get("feedback")
    else:
        # The report path and elapsed time are per-attempt by design; everything
        # the workflow actually resolved and reported must be identical.
        drop = ("elapsed_seconds", "report_path", "captured_utc")
        fields["feedback"] = {key: value for key, value in left["feedback"].items() if key not in drop} == \
                             {key: value for key, value in right["feedback"].items() if key not in drop}
    return {"identical": all(fields.values()), "fields": fields}


def comparable_effective(effective: dict | None) -> dict | None:
    """The resolved selection, without the fresh-report path that must differ per attempt."""
    if not effective:
        return None
    return {key: value for key, value in effective.items() if key != "report"}


def run_launcher(ws: Path, cwd: Path, *, arm: str, explicit: tuple | None, extra_env: dict | None = None,
                 timeout: float = 1800.0) -> dict:
    """Run the participant launcher once and summarize its effective command and feedback."""
    ledger = ws / ".m3"
    environment = dict(os.environ)
    # The workspace's own environment record carries the cache relocation and the
    # ledgers, so a coordinator-run launcher behaves exactly like a session's.
    if (ledger / "environment.json").is_file():
        environment.update(json.loads((ledger / "environment.json").read_text()))
    environment.update({
        "PATH": f"{ws / 'bin'}{os.pathsep}{os.environ.get('PATH', '')}",
        "MYLANG_M3_ARM": arm,
        "MYLANG_M3_PROJECT": str(ws / "app" / "project.json"),
        "MYLANG_M3_TOOLS": str(pack.TOOLS),
        "MYLANG_M3_CACHE": str(ledger / "cache"),
        "MYLANG_M3_REPORTS": str(ledger / "reports"),
        "MYLANG_M3_RESOLUTION_LOG": str(ledger / "resolution.jsonl"),
        "MYLANG_EVENT_LOG": str(ledger / "events.jsonl"),
        "MYLANG_M3_APP": str(ws / "app"),
        "MYLANG_M3_COHORT": "selftest",
        "MYLANG_M3_ATTEMPT": arm,
        "PYTHONDONTWRITEBYTECODE": "1",
    })
    if extra_env:
        environment.update(extra_env)
    argv = [sys.executable, str(ws / "bin" / "project"), "verify"]
    if explicit:
        argv += ["--entry", str(explicit[0]), "--manifest", str(explicit[1])]
    started = time.monotonic()
    completed = subprocess.run(argv, cwd=cwd, capture_output=True, text=True, timeout=timeout,
                               env=environment)
    summary = {"arm": arm, "cwd": str(cwd), "exit": completed.returncode,
               "seconds": round(time.monotonic() - started, 3),
               "stdout_tail": completed.stdout.strip()[-300:],
               "stderr_tail": completed.stderr.strip()[-300:]}
    try:
        summary["feedback"] = json.loads(completed.stdout.strip().splitlines()[-1])
    except (json.JSONDecodeError, IndexError):
        summary["feedback"] = None
    summary["status"] = (summary["feedback"] or {}).get("status")
    summary["effective"] = comparable_effective(effective_from_resolution(ws, arm))
    return summary


def effective_from_resolution(ws: Path, arm: str) -> dict | None:
    """The last resolution event's effective command, which is the launcher's own record."""
    path = ws / ".m3" / "resolution.jsonl"
    if not path.is_file():
        return None
    rows = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    rows = [row for row in rows if row.get("arm") == arm]
    return rows[-1].get("effective") if rows else None


def cmd_preflight(args) -> int:
    if args.application:
        selected_cases = [caselib.load(case_id) for case_id, case in caselib.CASES.items()
                          if case["application"] == args.application]
    elif args.case:
        selected_cases = [caselib.load(args.case)]
    else:
        if not args.all:
            raise SystemExit("preflight needs --all, --case ID or --application NAME")
        selected_cases = [caselib.load(case_id) for case_id in caselib.CASES]
    readiness = application_readiness()
    print("application readiness:")
    for name, record in readiness.items():
        print(f"  {name}: ready={record['ready']} public={record['public_passed']} "
              f"seconds={record['public_seconds']} diagnostics={record['diagnostics']['codes']}")
    frozen_oracles = load_oracles()
    shared_arms = None
    authored = [case for case in selected_cases if case["status"] == "authored"]
    if len(authored) > 1:
        # Resolution does not depend on which regression is seeded, so the
        # equivalence check runs once on the frozen application and every case
        # record points at it.
        first = authored[0]
        reference = WORK / "preflight" / first["id"] / "reference"
        prepare_variant(first, "reference", reference)
        shared_arms = arm_equivalence(first, reference, WORK / "preflight" / "arms")
        print(f"  arm equivalence: passed={shared_arms['passed']} "
              f"({len(shared_arms['comparisons'])} working directories)")
    results = []
    for case in selected_cases:
        record = preflight_case(case, frozen_oracles.get(case["id"], {}), shared_arms)
        results.append(record)
        if record["status"] == "declared":
            print(f"  {case['id']}: BLOCKED — {record['blocked_on']}")
        else:
            print(f"  {case['id']}: ready={record.get('ready')} "
                  f"reference={record['checks']['reference']['passed']} "
                  f"regression={record['checks']['regression']['passed']} "
                  f"wrong_repairs={record['checks']['wrong_repairs']['passed']} "
                  f"arms={record['checks']['arms']['passed']}")
    report = {"version": "m3-preflight-v1", "captured_utc": now(),
              "identity": observed_identity(args.split), "applications": readiness,
              "cases": results,
              "ready_applications": sorted(name for name, record in readiness.items() if record["ready"]),
              "ready_cases": sorted(record["case"] for record in results
                                    if record.get("ready") and record["status"] == "authored"),
              "blocked_cases": sorted(record["case"] for record in results
                                      if record["status"] == "declared" or not record.get("ready"))}
    write_oracles({record["case"]: record["checks"]["oracle"]["frozen_values"]
                   for record in results
                   if record["status"] == "authored" and "oracle" in record["checks"]})
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    (EVIDENCE / "preflight.json").write_text(json.dumps(report, indent=2) + "\n")
    (EVIDENCE / "readiness.md").write_text(readiness_text(report) + "\n")
    print(f"preflight: {len(report['ready_cases'])} ready, {len(report['blocked_cases'])} blocked "
          f"→ {EVIDENCE / 'preflight.json'}")
    return 0 if not report["blocked_cases"] else 1


def readiness_text(report: dict) -> str:
    """The readiness stop, written so a reader can act on it without the JSON."""
    lines = ["# M3 readiness", "", f"captured {report['captured_utc']}", "",
             "## Applications", "",
             "| application | snapshot | public workload | seconds | compiler diagnostics | ready |",
             "| --- | --- | --- | ---: | --- | --- |"]
    for name, record in sorted(report["applications"].items()):
        codes = ", ".join(record["diagnostics"]["codes"]) or "none"
        lines.append(f"| {name} | {record['snapshot_digest'][:16]} | "
                     f"{'passed' if record['public_passed'] else 'failed'} | {record['public_seconds']} | "
                     f"{codes} | {record['ready']} |")
    lines += ["", "## Cases", "",
              "| case | split | application | preflight |", "| --- | --- | --- | --- |"]
    for record in report["cases"]:
        if record["status"] == "declared":
            state = f"blocked — {record.get('blocked_on')}"
        else:
            state = (f"ready={record.get('ready')} reference={record['checks']['reference']['passed']} "
                     f"regression={record['checks']['regression']['passed']} "
                     f"wrong-repairs={record['checks']['wrong_repairs']['passed']} "
                     f"arms={record['checks']['arms']['passed']}")
        lines.append(f"| {record['case']} | {record['split']} | {record['application']} | {state} |")
    if report["blocked_cases"]:
        lines += ["", "## Readiness blocker", "",
                  "The runbook's rule is explicit: if either named application cannot pass preflight "
                  "with the chosen current toolchain, stop and report readiness as the blocker before "
                  "spending on participants. No port of an incompatible application was attempted; "
                  "the scored task pack was not frozen and no session was launched.", ""]
        for name, record in sorted(report["applications"].items()):
            if not record["ready"]:
                lines += [f"### {name}", "",
                          f"- public workload: {'passed' if record['public_passed'] else 'failed'}",
                          f"- compiler diagnostics: {', '.join(record['diagnostics']['codes']) or 'none'}",
                          "", "```", record["diagnostics"]["detail_tail"], "```", ""]
    return "\n".join(lines)


def load_oracles() -> dict:
    path = EVIDENCE / "oracles.json"
    return json.loads(path.read_text()) if path.is_file() else {}


def write_oracles(oracles: dict) -> None:
    """Persist every measured hidden oracle value; an existing value is never rewritten."""
    path = EVIDENCE / "oracles.json"
    existing = load_oracles()
    for case_id, values in oracles.items():
        for step_id, measured in values.items():
            if step_id in existing.get(case_id, {}) and existing[case_id][step_id] != measured:
                raise SystemExit(f"case {case_id}: hidden oracle {step_id} changed since it was frozen")
            existing.setdefault(case_id, {})[step_id] = measured
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(existing, indent=2, sort_keys=True) + "\n")


# ── freeze ────────────────────────────────────────────────────────────────────

def cmd_freeze(args) -> int:
    split = args.cohort
    root = COHORTS / split
    if (root / "manifest.json").exists():
        raise SystemExit(f"cohort {split} is already frozen at {root / 'manifest.json'}; "
                         "a frozen cohort is never rewritten")
    preflight = EVIDENCE / "preflight.json"
    if not preflight.is_file():
        raise SystemExit("freeze needs a preflight report; run `preflight --all` first")
    report = json.loads(preflight.read_text())
    scheduled = caselib.SPLITS[split]
    blocked = [case_id for case_id in scheduled if case_id in report["blocked_cases"]]
    if blocked:
        raise SystemExit(
            "freeze refused: the scheduled pack is not preflight-ready; blocked cases: "
            + ", ".join(blocked)
            + "\nThe runbook stops here rather than spending on participants: "
              "see evidence/preflight.json and evidence/readiness.md")
    if split == "main":
        pilot = COHORTS / "pilot" / "readout.json"
        if not pilot.is_file():
            raise SystemExit("freeze --cohort main refuses without a completed pilot readout")
        readout = json.loads(pilot.read_text())
        if not readout.get("gate", {}).get("passed"):
            raise SystemExit("freeze --cohort main refuses unless the pilot is complete, valid and "
                             "passes the declared gate")
    identity = observed_identity(split)
    manifest = cohort.new_manifest(split, scheduled, ARMS[split], REPETITIONS[split], identity,
                                   args.seed, PURPOSE[split])
    root.mkdir(parents=True, exist_ok=True)
    cohort.save(manifest, root / "manifest.json")
    (root / "identity.json").write_text(json.dumps(identity, indent=2) + "\n")
    print(f"frozen {split}: {len(scheduled)} cases x {len(ARMS[split])} arms x "
          f"{REPETITIONS[split]} repetitions = {len(manifest['schedule'])} cells, seed {args.seed}")
    return 0


# ── run ───────────────────────────────────────────────────────────────────────

def cell_directory(root: Path, arm: str, case: str, repetition: int) -> Path:
    return root / "runs" / arm / case / str(repetition)


def terminal_record(root: Path, arm: str, case: str, repetition: int) -> dict | None:
    directory = cell_directory(root, arm, case, repetition)
    if not directory.is_dir():
        return None
    attempts = sorted((path for path in directory.iterdir() if path.name.isdigit()),
                      key=lambda path: int(path.name))
    for attempt in reversed(attempts):
        record = attempt / "record.json"
        if record.is_file():
            return json.loads(record.read_text())
    return None


def scheduled_cells(manifest: dict) -> list[dict]:
    return manifest["schedule"]


def cell_key(row: dict) -> str:
    return f"{row['arm']}/{row['case']}/{row['repetition']}"


def cmd_run(args) -> int:
    root = COHORTS / args.cohort
    manifest_path = root / "manifest.json"
    if not manifest_path.is_file():
        preflight_path = EVIDENCE / "preflight.json"
        preflight = json.loads(preflight_path.read_text()) if preflight_path.is_file() else {}
        if preflight.get("blocked_cases"):
            raise SystemExit(
                f"no frozen cohort at {manifest_path}: freeze refused the pack because it is not "
                f"preflight-ready ({', '.join(preflight['blocked_cases'])}).\n"
                f"The runbook stops before spending on participants; see {EVIDENCE / 'readiness.md'} "
                "and cohorts/%s/readout.md" % args.cohort)
        raise SystemExit(f"no frozen cohort at {manifest_path}: run `freeze --cohort {args.cohort}` first")
    manifest = cohort.load(manifest_path)
    identity = observed_identity(manifest["identity"]["case_split"])
    differences = identity_differences(manifest["identity"], identity)
    if differences and not args.dry_run:
        raise SystemExit("refusing to run: the frozen identity no longer matches the checkout:\n  "
                         + "\n  ".join(differences))
    cells = scheduled_cells(manifest)
    pending = [row for row in cells if terminal_record(root, row["arm"], row["case"], row["repetition"]) is None]
    if args.cell:
        pending = [row for row in pending if cell_key(row) == args.cell]
    if args.attempt > 1 and not args.reason:
        raise SystemExit("a retry needs --reason; it is recorded with a link to its predecessor")
    print(f"cohort {args.cohort}: {len(cells)} scheduled, {len(cells) - len(pending)} terminal, "
          f"{len(pending)} pending; maximum new sessions this invocation: "
          f"{args.max_new_sessions if args.max_new_sessions is not None else 'unlimited'}")
    if args.dry_run:
        for index, row in enumerate(cells, start=1):
            state = "done" if terminal_record(root, row["arm"], row["case"], row["repetition"]) else "pending"
            print(f"  {index:02d}. {cell_key(row):<42} {state}")
        print(f"dry-run: would launch at most {len(pending)} of {len(cells)} cells")
        return 0
    launched = 0
    for row in pending:
        if args.max_new_sessions is not None and launched >= args.max_new_sessions:
            print(f"stopping at --max-new-sessions {args.max_new_sessions}")
            break
        differences = identity_differences(manifest["identity"],
                                           observed_identity(manifest["identity"]["case_split"]))
        if differences:
            raise SystemExit("refusing to continue: the frozen identity changed mid-cohort:\n  "
                             + "\n  ".join(differences))
        run_cell(root, args.cohort, row, attempt=args.attempt, reason=args.reason)
        launched += 1
    return 0


def run_cell(root: Path, cohort_id: str, row: dict, *, attempt: int = 1,
             reason: str | None = None) -> dict:
    """One session: fresh workspace, one participant, a sealed snapshot and grading."""
    case = caselib.load(row["case"])
    directory = WORK / cohort_id / row["arm"] / row["case"] / str(row["repetition"])
    destination = cohort.attempt_dir(root, row["arm"], row["case"], row["repetition"], attempt)
    if destination.exists():
        raise SystemExit(f"attempt directory already exists: {destination} — a retry is a new attempt")
    if directory.exists():
        if attempt == 1:
            raise SystemExit(
                f"an unfinished attempt already owns {directory}; it is preserved rather than "
                "silently resumed. Inspect it, then start a new attempt with "
                "`run --attempt N --reason ...`.")
        preserved = directory.with_name(f"{directory.name}-attempt-{attempt - 1}")
        if preserved.exists():
            raise SystemExit(f"cannot preserve the interrupted workspace: {preserved} exists")
        directory.rename(preserved)
    request = caselib.request_text(case, row["arm"], int(DEADLINE_SECONDS))
    built = workspace.build(directory, cohort_id=cohort_id, arm=row["arm"], case=case,
                            app_snapshot=pack.APPS / case["application"] / "snapshot",
                            tools=pack.TOOLS, launcher=LAUNCHER, request_text=request, docs_repo=REPO)
    cwd = workspace.initial_working_directory(directory, case)
    prompt = PROMPT_HEADER + "\n" + request + f"\n\n---\nWorking copy: `{directory}`\n"
    cohort.reserve(destination)
    environment = dict(os.environ)
    environment.update(built["environment"])
    environment["PATH"] = f"{directory / 'bin'}{os.pathsep}{os.environ.get('PATH', '')}"
    environment["ZIG_GLOBAL_CACHE_DIR"] = str(directory / ".m3" / "cache" / "zig-global")
    environment["ZIG_LOCAL_CACHE_DIR"] = str(directory / ".m3" / "cache" / "zig-local")
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    session = launch_session(directory, cwd, prompt, environment, DEADLINE_SECONDS)
    (destination / "session.txt").write_text(session.pop("stdout", ""))
    (destination / "session.err").write_text(session.pop("stderr", ""))
    sealed = destination / "sealed"
    sealed_hash = workspace.seal(directory / "app", sealed)
    session_logs = cascade_run.read_session_logs(cwd, datetime.fromisoformat(session["started_utc"]))
    event_records, coverage = events.read_events(directory / ".m3" / "events.jsonl")
    resolutions = read_resolution_events(directory / ".m3" / "resolution.jsonl")
    graded = grading.grade(sealed, case={**case, "cases_root": str(caselib.CASES_ROOT)},
                           app=case["application"], tools=pack.TOOLS,
                           frozen_app=pack.APPS / case["application"] / "snapshot",
                           cases_root=caselib.CASES_ROOT, staging=destination / "grading",
                           cache=destination / "grading-cache",
                           expected=load_oracles().get(case["id"], {}))
    submitted_seconds = session["seconds"] + graded["public"]["elapsed_seconds"]
    elapsed = min(DEADLINE_SECONDS, submitted_seconds)
    accepted = bool(graded["accepted"] and not session["timed_out"])
    record = {
        "version": "m3-cell-v1", "cohort_id": cohort_id, "arm": row["arm"], "case": row["case"],
        "application": case["application"], "repetition": row["repetition"], "attempt": attempt,
        "attempt_reason": reason,
        "predecessor": str(cohort.attempt_dir(root, row["arm"], row["case"], row["repetition"],
                                              attempt - 1)) if attempt > 1 else None,
        "workspace": str(directory), "initial_working_directory": str(cwd),
        "initial_source_sha256": built["initial_source_sha256"], "sealed_source_sha256": sealed_hash,
        "session": session, "session_logs": session_logs,
        "events": {"coverage": coverage, "metrics": events.aggregate(event_records,
                                                                    built["initial_source_sha256"])},
        "resolution_events": resolutions,
        "grading": graded, "public_acceptance": graded["public_acceptance"],
        "hidden_acceptance": graded["hidden_acceptance"], "accepted": accepted,
        "timed_out": session["timed_out"], "elapsed_seconds": elapsed,
        "finished_utc": now(),
    }
    (destination / "record.json").write_text(json.dumps(record, indent=2) + "\n")
    if (directory / ".m3" / "events.jsonl").is_file():
        shutil.copy2(directory / ".m3" / "events.jsonl", destination / "events.jsonl")
    if (directory / ".m3" / "resolution.jsonl").is_file():
        shutil.copy2(directory / ".m3" / "resolution.jsonl", destination / "resolution.jsonl")
    shutil.rmtree(directory, ignore_errors=True)
    print(f"{'ACCEPTED' if accepted else 'not-accepted'}  {cell_key(row)}  "
          f"elapsed={elapsed:.1f}s  public={graded['public_acceptance']}  hidden={graded['hidden_acceptance']}")
    return record


def read_resolution_events(path: Path) -> list[dict]:
    if not path.is_file():
        return []
    rows = []
    for line in path.read_text(errors="replace").splitlines():
        if not line.strip():
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            rows.append({"schema": "m3-resolution-v1", "record_error": "unparseable line"})
    return rows


def launch_session(directory: Path, cwd: Path, prompt: str, environment: dict, timeout: float) -> dict:
    """One headless participant session, in the case's initial working directory."""
    started = datetime.now(timezone.utc)
    command = [part.replace("{prompt}", prompt).replace("{turn_cap}", "30")
               for part in cascade_run.launcher("dsh")]
    try:
        completed = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=timeout,
                                   env=environment)
        timed_out, exit_code = False, completed.returncode
        stdout, stderr = completed.stdout, completed.stderr
    except subprocess.TimeoutExpired as expired:
        timed_out, exit_code = True, -1
        stdout = (expired.stdout or b"").decode(errors="replace") if isinstance(expired.stdout, bytes) \
            else (expired.stdout or "")
        stderr = (expired.stderr or b"").decode(errors="replace") if isinstance(expired.stderr, bytes) \
            else (expired.stderr or "")
    return {"command": command, "cwd": str(cwd), "started_utc": started.isoformat(),
            "finished_utc": now(), "seconds": (datetime.now(timezone.utc) - started).total_seconds(),
            "timed_out": timed_out, "exit": exit_code, "stdout": stdout, "stderr": stderr}


# ── monitor ───────────────────────────────────────────────────────────────────

def cmd_monitor(args) -> int:
    root = COHORTS / args.cohort
    if not (root / "manifest.json").is_file():
        preflight_path = EVIDENCE / "preflight.json"
        preflight = json.loads(preflight_path.read_text()) if preflight_path.is_file() else {}
        print(f"cohort {args.cohort}: not frozen — nothing to monitor")
        if preflight.get("blocked_cases"):
            print(f"  readiness blocker: {', '.join(preflight['blocked_cases'])}")
            print(f"  evidence: {preflight_path} and {EVIDENCE / 'readiness.md'}")
            print("  no session was launched, so there are no integrity or status records yet")
        return 0
    manifest = cohort.load(root / "manifest.json")
    counts = {"scheduled": len(manifest["schedule"]), "completed": 0, "pending": 0,
              "snapshot_ok": 0, "snapshot_missing": 0, "snapshot_mismatch": 0,
              "events_missing": 0, "resolution_missing": 0, "grader_incidents": 0, "timeouts": 0,
              "accepted": 0, "identity_mismatch": 0}
    problems: list[str] = []
    observed = observed_identity(manifest["identity"]["case_split"])
    for difference in identity_differences(manifest["identity"], observed):
        counts["identity_mismatch"] += 1
        problems.append(f"identity: {difference}")
    for row in manifest["schedule"]:
        record = terminal_record(root, row["arm"], row["case"], row["repetition"])
        if record is None:
            counts["pending"] += 1
            continue
        counts["completed"] += 1
        counts["accepted"] += 1 if record.get("accepted") else 0
        counts["timeouts"] += 1 if record.get("timed_out") else 0
        attempts = sorted((path for path in cell_directory(root, row["arm"], row["case"],
                                                           row["repetition"]).iterdir()
                           if path.name.isdigit()), key=lambda path: int(path.name))
        latest = attempts[-1]
        sealed = latest / "sealed"
        if not sealed.is_dir():
            counts["snapshot_missing"] += 1
            problems.append(f"{cell_key(row)}: sealed snapshot missing")
        else:
            digest, _ = workspace.inventory(sealed)
            if digest != record.get("sealed_source_sha256"):
                counts["snapshot_mismatch"] += 1
                problems.append(f"{cell_key(row)}: sealed snapshot hash mismatch")
            else:
                counts["snapshot_ok"] += 1
        if not (latest / "events.jsonl").is_file():
            counts["events_missing"] += 1
        if not (latest / "resolution.jsonl").is_file():
            counts["resolution_missing"] += 1
        if record.get("grading") and not (record["grading"].get("public") or {}).get("grader_ok"):
            counts["grader_incidents"] += 1
    print(f"cohort {args.cohort}: {counts['completed']}/{counts['scheduled']} completed, "
          f"{counts['pending']} pending")
    print(f"  sealed snapshots verified {counts['snapshot_ok']}, missing {counts['snapshot_missing']}, "
          f"mismatched {counts['snapshot_mismatch']}")
    print(f"  ledgers: compiler event logs missing {counts['events_missing']}, "
          f"resolution ledgers missing {counts['resolution_missing']}")
    print(f"  incidents: timeouts {counts['timeouts']}, grader {counts['grader_incidents']}, "
          f"identity mismatches {counts['identity_mismatch']}")
    print(f"  accepted submissions so far: {counts['accepted']}")
    for problem in problems[:10]:
        print(f"  ! {problem}")
    print("treatment comparisons are deliberately absent here; they belong to the frozen readout")
    return 0


# ── score ─────────────────────────────────────────────────────────────────────

def collect_rows(root: Path, manifest: dict) -> list[dict]:
    rows = []
    for row in manifest["schedule"]:
        case = caselib.load(row["case"])
        record = terminal_record(root, row["arm"], row["case"], row["repetition"])
        rows.append({"arm": row["arm"], "case": row["case"], "application": case["application"],
                     "repetition": row["repetition"], "record": record})
    return rows


def cell_events(root: Path, row: dict) -> list[dict]:
    """Every compiler process recorded for one cell, in start order."""
    path = cell_directory(root, row["arm"], row["case"], row["repetition"]) / "1" / "events.jsonl"
    records, _ = events.read_events(path)
    return sorted(records, key=lambda item: item.get("started_monotonic_ns") or 0)


def invocation_failures(records: list[dict], resolutions: list[dict]) -> list[dict]:
    """Failures that look like invocation/selection mistakes rather than source errors.

    A source diagnostic is not by itself evidence of an invocation mistake; the
    candidate set is every failed or misused compiler process plus every
    resolution failure that never reached a compiler. Whether a candidate is
    *avoidable* is decided only by the replay below.
    """
    failures = []
    for event in records:
        outcome = event.get("outcome")
        if outcome in ("invocation_misuse", "infrastructure_failure", "limit_reached"):
            failures.append({"kind": "compiler_invocation", "outcome": outcome,
                             "argv": event.get("argv"), "cwd": event.get("cwd"),
                             "diagnostic_codes": event.get("diagnostic_codes"),
                             "finished_monotonic_ns": event.get("finished_monotonic_ns")})
        elif outcome in ("source_error", "runtime_failure"):
            codes = set(event.get("diagnostic_codes") or [])
            if codes & {"E_MODULE_NAME", "E_MODULE_READ", "E_MAIN", "E_FILE_READ"}:
                failures.append({"kind": "compiler_invocation", "outcome": outcome,
                                 "argv": event.get("argv"), "cwd": event.get("cwd"),
                                 "diagnostic_codes": event.get("diagnostic_codes"),
                                 "finished_monotonic_ns": event.get("finished_monotonic_ns")})
    for resolution in resolutions:
        if resolution.get("outcome") == "resolution_failure":
            failures.append({"kind": "resolution_failure", "outcome": "resolution_failure",
                             "error": resolution.get("error"), "cwd": resolution.get("cwd"),
                             "argv": resolution.get("backend_argv")})
    return failures


def replay_failures(root: Path, manifest: dict, rows: list[dict]) -> list[dict]:
    """Classify avoidable invocation failures by replaying the same sealed source.

    A failure counts only when a coordinator replay of the *same source snapshot*
    with corrected root/entry/command selection removes that invocation error. The
    replay may surface a separate source error; that is recorded and the failure
    is still classified as avoidable. Replay work is outside participant cost and
    is never shown to the participant.
    """
    replays = []
    for row in rows:
        record = row["record"]
        if not record:
            continue
        attempt = cell_directory(root, row["arm"], row["case"], row["repetition"]) / "1"
        sealed = attempt / "sealed"
        if not sealed.is_dir():
            continue
        records = cell_events(root, row)
        candidates = invocation_failures(records, record.get("resolution_events", []))
        for index, failure in enumerate(candidates, start=1):
            result = replay_one(root, row, sealed, records, failure, index)
            replays.append(result)
    return replays


def rebase_argument(part: str, original_app: str, new_app: Path) -> str:
    """Move an argument from the original working copy onto the replay copy."""
    if original_app and original_app in part:
        return part.replace(original_app, str(new_app))
    return part


def replay_one(root: Path, row: dict, sealed: Path, records: list[dict], failure: dict,
               index: int) -> dict:
    """Re-run one failed invocation with corrected selection on the sealed snapshot."""
    case = caselib.load(row["case"])
    workspace_root = root / "replays" / row["arm"] / row["case"] / str(row["repetition"]) / str(index)
    if workspace_root.exists():
        shutil.rmtree(workspace_root)
    request = caselib.request_text(case, "automatic", int(DEADLINE_SECONDS))
    built = workspace.build(workspace_root, cohort_id="replay", arm="automatic", case=case,
                            app_snapshot=sealed, tools=pack.TOOLS, launcher=LAUNCHER,
                            request_text=request, docs_repo=REPO)
    app = (workspace_root / "app").resolve()
    original_app = ""
    original_cwd = failure.get("cwd") or ""
    if original_cwd:
        candidate = Path(original_cwd)
        # The original working copy is gone; its application root was a sibling.
        original_app = str(candidate.parent / "app") if candidate.name != "app" else str(candidate)
    started = time.monotonic()
    if failure["kind"] == "resolution_failure":
        outcome = run_launcher(workspace_root, app, arm="automatic", explicit=None)
        corrected = {"argv": ["project", "verify"], "cwd": str(app)}
        original = {"argv": failure.get("argv"), "cwd": original_cwd}
    else:
        forwarded = [rebase_argument(part, original_app, app) for part in failure.get("argv", [])]
        if forwarded and forwarded[0] in ("mylang", "mylang-io"):
            forwarded[0] = str(workspace_root / "bin" / forwarded[0])
        corrected_cwd = app
        if original_cwd and original_app:
            suffix = Path(original_cwd).resolve().relative_to(Path(original_app).resolve()) \
                if str(original_cwd).startswith(original_app) else None
            if suffix and (app / suffix).is_dir():
                corrected_cwd = app / suffix
        environment = dict(os.environ)
        environment.update(built["environment"])
        environment["PATH"] = f"{workspace_root / 'bin'}{os.pathsep}{os.environ.get('PATH', '')}"
        completed = subprocess.run(forwarded, cwd=corrected_cwd, capture_output=True, text=True,
                                   timeout=900, env=environment)
        outcome = {"exit": completed.returncode, "stdout_tail": completed.stdout.strip()[-300:],
                   "stderr_tail": completed.stderr.strip()[-400:]}
        corrected = {"argv": forwarded, "cwd": str(corrected_cwd)}
        original = {"argv": failure.get("argv"), "cwd": original_cwd}
    elapsed = round(time.monotonic() - started, 3)
    removed = outcome.get("exit") == 0
    recovery = next((item for item in records
                     if item.get("outcome") == "success"
                     and (item.get("started_monotonic_ns") or 0) >= (failure.get("finished_monotonic_ns") or 0)),
                    None)
    result = {"cohort": root.name, "arm": row["arm"], "case": row["case"],
              "repetition": row["repetition"], "failure": failure, "original": original,
              "corrected": corrected, "replay": outcome, "replay_seconds": elapsed,
              "invocation_error_removed": removed, "avoidable": bool(removed),
              "recovery_seconds": None if (recovery is None or not failure.get("finished_monotonic_ns"))
              else round(((recovery["finished_monotonic_ns"] - failure["finished_monotonic_ns"]) / 1e9), 3),
              "note": "the replay runs the sealed source snapshot with corrected root/entry/command "
                      "selection; a separate source error may remain and is reported by the replay outcome"}
    result_path = root / "replays" / row["arm"] / row["case"] / str(row["repetition"]) / f"{index}.json"
    result_path.parent.mkdir(parents=True, exist_ok=True)
    result_path.write_text(json.dumps(result, indent=2) + "\n")
    result["evidence"] = str(result_path)
    shutil.rmtree(workspace_root, ignore_errors=True)
    return result


def cmd_score(args) -> int:
    root = COHORTS / args.cohort
    manifest_path = root / "manifest.json"
    if not manifest_path.is_file():
        # No cohort was frozen. When the preflight records a readiness blocker,
        # that stop *is* the result of this stage, and it is published in the same
        # JSON + Markdown shape a scored cohort would use.
        preflight_path = EVIDENCE / "preflight.json"
        preflight = json.loads(preflight_path.read_text()) if preflight_path.is_file() else {}
        if preflight.get("blocked_cases"):
            readout = not_run_readout(args.cohort, preflight)
            write_readout(root, readout)
            print(readout_text(readout))
            print(f"wrote {root / 'readout.json'} and {root / 'readout.md'}")
            return 0
        raise SystemExit(f"no frozen cohort at {manifest_path}")
    manifest = cohort.load(manifest_path)
    rows = collect_rows(root, manifest)
    preflight = json.loads((EVIDENCE / "preflight.json").read_text()) if (EVIDENCE / "preflight.json").is_file() else {}
    recorded = [row for row in rows if row["record"]]
    if not recorded:
        readout = not_run_readout(args.cohort, preflight, manifest=manifest)
        write_readout(root, readout)
        print(f"{args.cohort}: not-run (readiness blocker); wrote {root / 'readout.json'}")
        return 0
    if args.cohort == "pilot":
        readout = score_pilot(root, manifest, rows)
    else:
        readout = score_main(root, manifest, rows)
    write_readout(root, readout)
    print(readout_text(readout))
    print(f"wrote {root / 'readout.json'} and {root / 'readout.md'}")
    return 0


def incidents(root: Path, rows: list[dict]) -> dict:
    """Everything that must be disclosed before a readout is believed."""
    timeouts, missing, grader, changed_tests, infrastructure, unknown_evidence = [], [], [], [], [], []
    for row in rows:
        key = f"{row['arm']}/{row['case']}/{row['repetition']}"
        record = row["record"]
        if not record:
            missing.append(key)
            continue
        if record.get("timed_out"):
            timeouts.append(key)
        grading_record = record.get("grading") or {}
        if not (grading_record.get("public") or {}).get("grader_ok", True):
            grader.append(key)
        if grading_record.get("public_tests_changed_by_participant"):
            changed_tests.append(key)
        metrics = (record.get("events") or {}).get("metrics") or {}
        if metrics.get("infrastructure_failures"):
            infrastructure.append({"cell": key, "count": metrics["infrastructure_failures"]})
        if scoring.restricted_seconds(record) is None:
            unknown_evidence.append(key)
    return {"timeouts": timeouts, "missing_records": missing, "grader_incidents": grader,
            "public_tests_changed_by_participant": changed_tests,
            "infrastructure_failures": infrastructure, "unknown_restricted_time": unknown_evidence,
            "note": "a missing or corrupted record is unknown evidence and blocks a definitive "
                    "decision; it is never scored as zero seconds"}


def implementation_effort() -> dict:
    """One-time implementation size, in its own units, for the break-even record."""
    files = [LAUNCHER, HERE / "m3.py", *sorted((HERE / "m3lib").glob("*.py"))]
    lines = 0
    for path in files:
        lines += len(path.read_text().splitlines())
    case_pack = sum(len(path.read_text(errors="replace").splitlines())
                    for path in sorted((HERE / "pack" / "cases").rglob("*")) if path.is_file())
    return {"wrapper_and_runner_lines": lines, "case_pack_lines": case_pack,
            "note": "engineering time and model-generated tokens are recorded in their own units; "
                    "these are physical line counts of the authored instrument, not elapsed time"}


def not_run_readout(cohort_id: str, preflight: dict, manifest: dict | None = None) -> dict:
    """The published result when the readiness gate stops the experiment."""
    blocked = preflight.get("blocked_cases", [])
    return {
        "version": "m3-readout-v1", "captured_utc": now(), "cohort": cohort_id,
        "status": "not-run",
        "identity": (manifest or {}).get("identity", preflight.get("identity")),
        "cells": 0, "recorded": 0,
        "applications": {name: {"ready": record["ready"], "public_passed": record["public_passed"],
                                "public_seconds": record["public_seconds"],
                                "diagnostics": record["diagnostics"]["codes"]}
                         for name, record in preflight.get("applications", {}).items()},
        "blocker": {
            "kind": "readiness",
            "summary": "no participant session was launched: the frozen application pack is not "
                       "preflight-ready, and the runbook stops here rather than spending on "
                       "participants",
            "blocked_cases": blocked,
            "ready_applications": preflight.get("ready_applications", []),
            "ready_cases": preflight.get("ready_cases", []),
            "detail": next((record.get("blocked_on") for record in preflight.get("cases", [])
                            if record.get("status") == "declared"), None),
            "preflight_evidence": str(EVIDENCE / "preflight.json"),
            "readiness_evidence": str(EVIDENCE / "readiness.md"),
        },
        "gate": {"evaluated": False, "passed": None,
                 "reason": "the headroom pilot was not run because the runbook's readiness check "
                           "failed before any participant was engaged"},
        "decision_rule": {"row": "not-reached",
                          "verdict": "the predeclared decision rule cannot be applied without a "
                                     "scored cohort; the readiness stop takes precedence"},
        "next_action": "do not spend on participants; either supply a current second application "
                       "snapshot (a working-tree application that compiles with the frozen "
                       "toolchain) or re-specify the experiment",
    }


def score_pilot(root: Path, manifest: dict, rows: list[dict]) -> dict:
    """The headroom gate: 3 of 8 sessions with an avoidable invocation failure, one per application."""
    replays = replay_failures(root, manifest, rows)
    sessions = []
    for row in rows:
        record = row["record"]
        if not record:
            continue
        session_replays = [item for item in replays if item["case"] == row["case"]
                           and item["arm"] == row["arm"] and item["repetition"] == row["repetition"]]
        avoidable = [item for item in session_replays if item["avoidable"]]
        recovery_seconds = sum(item.get("recovery_seconds") or 0 for item in avoidable)
        sessions.append({"arm": row["arm"], "case": row["case"], "application": row["application"],
                         "repetition": row["repetition"], "avoidable_failures": len(avoidable),
                         "invocation_failures": len(session_replays),
                         "recovery_seconds": recovery_seconds,
                         "accepted": record.get("accepted"),
                         "timed_out": record.get("timed_out")})
    affected = [session for session in sessions if session["avoidable_failures"]]
    per_application = {application: sum(1 for session in affected if session["application"] == application)
                       for application in sorted({session["application"] for session in sessions})}
    gate_passed = bool(len(affected) >= 3 and per_application
                       and all(count >= 1 for count in per_application.values()))
    return {
        "version": "m3-readout-v1", "captured_utc": now(), "cohort": "pilot", "status": "scored",
        "identity": manifest["identity"], "cells": len(rows), "recorded": len(sessions),
        "gate": {"evaluated": True, "threshold": "at least 3 of 8 sessions with an avoidable "
                                                 "invocation failure, at least one in each application",
                 "affected_sessions": len(affected), "per_application": per_application,
                 "passed": gate_passed},
        "incidents": incidents(root, rows),
        "sessions": sessions, "replays": replays,
        "decision": ("the gate passed: freeze the main cohort with the preserved task pack"
                     if gate_passed else
                     "the gate failed: publish the pilot and stop M3; this workload does not "
                     "establish enough remaining invocation friction to justify the intervention"),
    }


def score_main(root: Path, manifest: dict, rows: list[dict]) -> dict:
    """Restricted delivery time, per-case and per-application, with a case bootstrap."""
    replay_rows = replay_failures(root, manifest, rows)
    means = scoring.case_means(rows)
    applications = sorted({row["application"] for row in rows})
    per_case = {}
    for (application, arm, case), value in sorted(means.items()):
        per_case.setdefault(f"{application}/{case}", {})[arm] = value
    per_application = {application: {arm: scoring.arm_mean(means, application, arm) for arm in manifest["arms"]}
                       for application in applications}
    per_application_saving = {application: scoring.saving(means, application=application)
                              for application in applications}
    overall = scoring.saving(means)
    interval = scoring.bootstrap(rows, applications)
    acceptance = scoring.acceptance(rows)
    avoidable = {arm: sum(1 for item in replay_rows if item["arm"] == arm and item["avoidable"])
                 for arm in manifest["arms"]}
    recorded = [row for row in rows if row["record"]]
    evidence_complete = len(recorded) == len(rows)
    decisions = scoring.decision(overall, interval["interval"], per_application_saving, acceptance,
                                 avoidable, evidence_complete)
    manual_mean = scoring.overall_mean(means, "manual")
    automatic_mean = scoring.overall_mean(means, "automatic")
    per_task_saving = None if (manual_mean is None or automatic_mean is None) else manual_mean - automatic_mean
    return {
        "version": "m3-readout-v1", "captured_utc": now(), "cohort": "main", "status": "scored",
        "identity": manifest["identity"], "cells": len(rows), "recorded": len(recorded),
        "missing_evidence": [f"{row['arm']}/{row['case']}/{row['repetition']}"
                             for row in rows if not row["record"]],
        "primary": {"restricted_seconds": {"manual": manual_mean, "automatic": automatic_mean},
                    "saving": overall, "saving_interval": interval["interval"],
                    "interval_detail": interval,
                    "per_application_saving": per_application_saving,
                    "per_application_means": per_application, "per_case_means": per_case},
        "acceptance": acceptance,
        "incidents": incidents(root, rows),
        "secondary": {"avoidable_invocation_failures": avoidable,
                      "replays": replay_rows,
                      "per_case_metrics": [{"arm": row["arm"], "case": row["case"],
                                            "repetition": row["repetition"],
                                            "events": ((row["record"] or {}).get("events") or {}).get("metrics"),
                                            "session": ((row["record"] or {}).get("session_logs") or {}),
                                            "elapsed_seconds": (row["record"] or {}).get("elapsed_seconds")}
                                           for row in rows]},
        "configuration": {"wrapper_and_runner_lines": implementation_effort()["wrapper_and_runner_lines"],
                          "case_pack_lines": implementation_effort()["case_pack_lines"],
                          "break_even": scoring.break_even(0.0, per_task_saving),
                          "note": "break-even is engineering setup time divided by observed positive "
                                  "per-task time saved; with no observed saving there is none to report"},
        "decision": decisions,
        "limitations": ["six distinct tasks and two applications are not 36 independent "
                        "generalisation examples; the interval is descriptive",
                        "equal observed acceptance is not a non-inferiority proof"],
    }


def write_readout(root: Path, readout: dict) -> None:
    root.mkdir(parents=True, exist_ok=True)
    (root / "readout.json").write_text(json.dumps(readout, indent=2, sort_keys=True) + "\n")
    (root / "readout.md").write_text(readout_text(readout) + "\n")


def readout_text(readout: dict) -> str:
    lines = [f"# M3 cohort {readout['cohort']}", "",
             f"captured {readout['captured_utc']}  ·  status **{readout['status']}**", ""]
    if readout["status"] == "not-run":
        blocker = readout["blocker"]
        lines += ["## Readiness blocker", "", blocker["summary"], "",
                  f"- ready applications: {', '.join(blocker['ready_applications']) or 'none'}",
                  f"- ready cases: {', '.join(blocker.get('ready_cases', [])) or 'none'}",
                  f"- blocked cases: {', '.join(blocker['blocked_cases']) or 'none'}",
                  f"- detail: {blocker['detail']}",
                  f"- evidence: `{blocker['preflight_evidence']}`, `{blocker['readiness_evidence']}`", ""]
        if readout.get("applications"):
            lines += ["| application | public workload | seconds | diagnostics | ready |",
                      "| --- | --- | ---: | --- | --- |"]
            for name, record in sorted(readout["applications"].items()):
                codes = ", ".join(record["diagnostics"]) or "none"
                lines.append(f"| {name} | {'passed' if record['public_passed'] else 'failed'} | "
                             f"{record['public_seconds']} | {codes} | {record['ready']} |")
            lines.append("")
        lines += ["## Gate", "", f"not evaluated — {readout['gate']['reason']}", "",
                  "## Decision rule", "",
                  f"- row: **{readout['decision_rule']['row']}**",
                  f"- {readout['decision_rule']['verdict']}", "",
                  "## Next action", "", readout["next_action"], ""]
        return "\n".join(lines)
    lines += [f"cells {readout['cells']}  ·  recorded {readout['recorded']}", ""]
    if readout["cohort"] == "pilot":
        gate = readout["gate"]
        lines += ["## Headroom gate", "",
                  f"- threshold: {gate['threshold']}",
                  f"- affected sessions: {gate['affected_sessions']}",
                  f"- per application: {gate['per_application']}",
                  f"- **passed: {gate['passed']}**", "",
                  "## Incidents", "",
                  f"- missing records: {readout.get('incidents', {}).get('missing_records') or 'none'}",
                  f"- timeouts: {readout.get('incidents', {}).get('timeouts') or 'none'}",
                  f"- grader incidents: {readout.get('incidents', {}).get('grader_incidents') or 'none'}",
                  "",
                  "## Decision", "", readout["decision"], "",
                  "| arm | case | rep | avoidable failures | recovery s | accepted |",
                  "| --- | --- | ---: | ---: | ---: | --- |"]
        for session in readout["sessions"]:
            lines.append(f"| {session['arm']} | {session['case']} | {session['repetition']} | "
                         f"{session['avoidable_failures']} | {session['recovery_seconds']} | "
                         f"{session['accepted']} |")
        return "\n".join(lines)
    primary = readout["primary"]
    lines += ["## Primary: restricted delivery time", "",
              f"- manual mean: {primary['restricted_seconds']['manual']}",
              f"- automatic mean: {primary['restricted_seconds']['automatic']}",
              f"- saving: {primary['saving']}  95% interval {primary['saving_interval']}",
              f"- per application: {primary['per_application_saving']}", "",
              "## Acceptance", "", f"```json\n{json.dumps(readout['acceptance'], indent=2)}\n```", "",
              "## Incidents", ""]
    incident_report = readout.get("incidents", {})
    for name in ("timeouts", "missing_records", "grader_incidents", "unknown_restricted_time",
                 "public_tests_changed_by_participant", "infrastructure_failures"):
        value = incident_report.get(name)
        lines.append(f"- {name}: {value if value else 'none'}")
    lines += ["", "## Configuration and break-even", "",
              f"- wrapper and runner lines: {readout['configuration']['wrapper_and_runner_lines']}",
              f"- case pack lines: {readout['configuration']['case_pack_lines']}",
              f"- break-even: {readout['configuration']['break_even']}", "",
              "## Decision rule", "",
              f"- row: **{readout['decision']['row']}**", f"- {readout['decision']['verdict']}", "",
              "## Limitations", ""]
    lines += [f"- {item}" for item in readout["limitations"]]
    return "\n".join(lines)


# ── selftest ──────────────────────────────────────────────────────────────────

def cmd_selftest(args) -> int:
    checks = []
    checks.append(check_resolution_equivalence())
    checks.append(check_negative_controls())
    checks.append(check_invocation_counting())
    checks.append(check_evidence_integrity())
    checks.append(check_attempt_immutability())
    checks.append(check_scoring_synthetic())
    report = {"version": "m3-selftest-v1", "captured_utc": now(),
              "passed": all(check["passed"] for check in checks), "checks": checks}
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    (EVIDENCE / "selftest.json").write_text(json.dumps(report, indent=2) + "\n")
    for check in checks:
        print(f"{'PASS' if check['passed'] else 'FAIL'}  {check['name']}")
        for detail in check.get("failures", [])[:5]:
            print(f"      ! {detail}")
    print(f"selftest: {'PASS' if report['passed'] else 'FAIL'} → {EVIDENCE / 'selftest.json'}")
    return 0 if report["passed"] else 1


def fixture_case() -> dict:
    """The authored case used for launcher checks: a real mutation on real sources."""
    return caselib.load("sexpr-percent")


def control_case(case_id: str = "control") -> dict:
    return {"id": case_id, "application": "control", "mutation": None, "working_directory": "app",
            "hidden": {"checks": []}}


def build_control_workspace(root: Path, *, case_id: str = "control") -> dict:
    """A fast project for launcher checks, with the nested directories the case table uses."""
    app = root / "app-source"
    if app.exists():
        shutil.rmtree(app)
    shutil.copytree(CONTROLS, app)
    for name in ("tests", "sexpr"):
        (app / name).mkdir(exist_ok=True)
        (app / name / "NOTE.txt").write_text("nested working directory for the launcher checks\n")
    return workspace.build(root / "ws", cohort_id="selftest", arm="manual", case=control_case(case_id),
                           app_snapshot=app, tools=pack.TOOLS, launcher=LAUNCHER,
                           request_text="control", docs_repo=REPO)


def oracle_for(case: dict, snapshot: Path, staging: Path) -> dict:
    """The frozen hidden oracle for a case, measured from the reference if not yet frozen."""
    frozen = load_oracles().get(case["id"], {})
    if frozen:
        return frozen
    if case["status"] != "authored":
        return {}
    return grading.measure_hidden(snapshot, case={**case, "cases_root": str(caselib.CASES_ROOT)},
                                  tools=pack.TOOLS, staging=staging)


def check_resolution_equivalence() -> dict:
    """Explicit and automatic resolution agree on the same source, from any working directory."""
    root = WORK / "selftest" / "resolution"
    if root.exists():
        shutil.rmtree(root)
    root.mkdir(parents=True)
    build_control_workspace(root)
    failures: list[str] = []
    summaries = []
    for relative in ("app", "app/tests", "app/sexpr", "."):
        cwd = (root / "ws" / relative).resolve()
        entry = (root / "ws" / "app" / "main.my").resolve()
        manifest = (root / "ws" / "app" / "verify.json").resolve()
        automatic = run_launcher(root / "ws", cwd, arm="automatic", explicit=None)
        explicit = run_launcher(root / "ws", cwd, arm="manual", explicit=(entry, manifest))
        agreement = launcher_agreement(automatic, explicit)
        summaries.append({"cwd": relative, "automatic_exit": automatic["exit"],
                          "explicit_exit": explicit["exit"], "agreement": agreement,
                          "effective": automatic["effective"]})
        if not agreement["identical"]:
            failures.append(f"{relative}: launcher feedback differs: {agreement['fields']}")
        if automatic["feedback"] is None or explicit["feedback"] is None:
            failures.append(f"{relative}: no JSON receipt was produced")
        if automatic["exit"] != 0:
            failures.append(f"{relative}: automatic resolution did not pass the control project")
    ledger_before = read_resolution_events(root / "ws" / ".m3" / "resolution.jsonl")
    events_before, _ = events.read_events(root / "ws" / ".m3" / "events.jsonl")
    manual_without_paths = run_launcher(root / "ws", root / "ws" / "app", arm="manual", explicit=None)
    if manual_without_paths["exit"] == 0:
        failures.append("the manual arm accepted a command with no entry/manifest")
    ledger = read_resolution_events(root / "ws" / ".m3" / "resolution.jsonl")
    if not any(row.get("outcome") == "resolution_failure" for row in ledger):
        failures.append("the manual form's missing paths were not recorded as a resolution failure")
    events_after, _ = events.read_events(root / "ws" / ".m3" / "events.jsonl")
    if len(events_after) != len(events_before):
        failures.append("a resolution failure before the compiler produced a compiler event")
    effective_set = {json.dumps(comparable_effective(row["effective"]), sort_keys=True)
                     for row in ledger if row.get("effective")}
    if len(effective_set) != 1:
        failures.append("resolved entry/manifest/compiler/cache differ across working directories: "
                        f"{len(effective_set)} distinct effective commands")
    # The same agreement on the frozen application itself, on its seeded source.
    case = fixture_case()
    real_root = root / "real"
    real_root.mkdir()
    seeded = real_root / "seeded"
    prepare_variant(case, "regression", seeded)
    # The snapshot is already seeded, so the workspace build must not apply the
    # same regression a second time.
    built = workspace.build(real_root / "ws", cohort_id="selftest", arm="manual",
                            case={**case, "mutation": None},
                            app_snapshot=seeded, tools=pack.TOOLS, launcher=LAUNCHER,
                            request_text=caselib.request_text(case, "manual", int(DEADLINE_SECONDS)),
                            docs_repo=REPO)
    real_entry = (real_root / "ws" / "app" / "main.my").resolve()
    real_manifest = (real_root / "ws" / "app" / "verify.json").resolve()
    real_automatic = run_launcher(real_root / "ws", real_root / "ws" / "app", arm="automatic",
                                  explicit=None)
    real_explicit = run_launcher(real_root / "ws", real_root / "ws" / "app", arm="manual",
                                 explicit=(real_entry, real_manifest))
    real_agreement = launcher_agreement(real_automatic, real_explicit)
    if not real_agreement["identical"]:
        failures.append(f"frozen application: arms differ: {real_agreement['fields']}")
    if real_automatic["exit"] == 0:
        failures.append("the seeded regression passed the public verification it must fail")
    return {"name": "resolution-equivalence", "passed": not failures, "failures": failures,
            "checks": {"working_directories": summaries, "resolution_events": len(ledger),
                       "distinct_effective": len(effective_set),
                       "frozen_application_agreement": real_agreement,
                       "seeded_public_exit": real_automatic["exit"]}}


def check_negative_controls() -> dict:
    """A wrong module header and a missing import are rejected in both arms."""
    root = WORK / "selftest" / "controls"
    if root.exists():
        shutil.rmtree(root)
    root.mkdir(parents=True)
    variants = {"good": None,
                "bad-header": ("module main", "module control_wrong"),
                "missing-import": ("module main", "module main\nimport absent.module as absent")}
    failures = []
    observed = {}
    for name, edit in variants.items():
        app = root / f"{name}-app"
        shutil.copytree(CONTROLS, app)
        if edit:
            target = app / "main.my"
            text = target.read_text()
            if text.count(edit[0]) != 1:
                failures.append(f"{name}: control edit did not match")
            target.write_text(text.replace(edit[0], edit[1]))
        workspace.build(root / f"{name}-ws", cohort_id="selftest", arm="manual",
                        case=control_case(f"control-{name}"), app_snapshot=app, tools=pack.TOOLS,
                        launcher=LAUNCHER, request_text="control", docs_repo=REPO)
        entry = (root / f"{name}-ws" / "app" / "main.my").resolve()
        manifest = (root / f"{name}-ws" / "app" / "verify.json").resolve()
        arms = {}
        for arm in ("manual", "automatic"):
            outcome = run_launcher(root / f"{name}-ws", root / f"{name}-ws" / "app", arm=arm,
                                   explicit=(entry, manifest) if arm == "manual" else None)
            receipt = outcome["feedback"] or {}
            arms[arm] = {"exit": outcome["exit"], "status": receipt.get("status"),
                         "diagnostic": json.dumps(receipt.get("diagnostics", {}))[:600]}
        observed[name] = arms
        if name == "good":
            if any(arm["exit"] != 0 for arm in arms.values()):
                failures.append(f"good control did not pass in both arms: {arms}")
        else:
            expected = "E_MODULE_NAME" if name == "bad-header" else "E_MODULE_READ"
            for arm, outcome in arms.items():
                if outcome["exit"] == 0 or expected not in (outcome["diagnostic"] or ""):
                    failures.append(f"{name}/{arm}: expected {expected} rejection, saw {outcome}")
    return {"name": "negative-controls", "passed": not failures, "failures": failures,
            "observed": observed}


def check_invocation_counting() -> dict:
    """One event per compiler process: grouping, diagnostics and repeated delivery change nothing."""
    root = WORK / "selftest" / "counting"
    if root.exists():
        shutil.rmtree(root)
    root.mkdir(parents=True)
    build_control_workspace(root, case_id="counting")
    app = root / "ws" / "app"
    (app / "multi.my").write_text("module multi\n\n\ndef main() -> int:\n"
                                  "    missing_one()\n    return 0\n")
    environment = dict(os.environ)
    environment.update(json.loads((root / "ws" / ".m3" / "environment.json").read_text()))
    environment["PATH"] = f"{root / 'ws' / 'bin'}{os.pathsep}{os.environ.get('PATH', '')}"
    log = root / "ws" / ".m3" / "events.jsonl"
    failures: list[str] = []
    compiler = root / "ws" / "bin" / "mylang"
    # Three compiler processes inside one shell command: three events.
    subprocess.run(["bash", "-c",
                    f"{compiler} check main.my >/dev/null 2>&1; "
                    f"{compiler} check main.my >/dev/null 2>&1; "
                    f"{compiler} check main.my >/dev/null 2>&1; true"],
                   cwd=app, capture_output=True, text=True, env=environment, timeout=600)
    first, _ = events.read_events(log)
    if len(first) != 3:
        failures.append(f"three grouped compiler processes produced {len(first)} events")
    # One compiler process that emits a diagnostic: exactly one event, and the
    # diagnostics it printed are recorded on that single event.
    subprocess.run([str(compiler), "check", "multi.my"], cwd=app, capture_output=True, text=True,
                   env=environment, timeout=600)
    second, _ = events.read_events(log)
    added = second[len(first):]
    if len(added) != 1:
        failures.append(f"one compiler process produced {len(added)} events")
    # A single process whose stderr carries three diagnostics is still one event:
    # the accounting unit is the process, not the diagnostic line.
    synthetic = ("a.my:1:1: error[E_ONE]: first\n  snippet one\n"
                 "b.my:2:2: error[E_TWO]: second\n  snippet two\n"
                 "c.my:3:3: error[E_THREE]: third\n  snippet three\n")
    parsed = events.parse_diagnostics(synthetic)
    if len(parsed) != 3:
        failures.append(f"the shared parser did not read three diagnostics from one stream: {len(parsed)}")
    if len(added) == 1 and len(added[0].get("diagnostic_codes") or []) != 1:
        failures.append("the single process did not record its one diagnostic code")
    # Repeated delivery of the same ledger changes no count.
    again, _ = events.read_events(log)
    if len(again) != len(second):
        failures.append("re-reading the ledger changed the event count")
    # A resolution failure before any compiler launch is recorded separately.
    run_launcher(root / "ws", app, arm="manual", explicit=None)
    resolutions = [row for row in read_resolution_events(root / "ws" / ".m3" / "resolution.jsonl")
                   if row.get("outcome") == "resolution_failure"]
    if not resolutions:
        failures.append("a resolution failure was not recorded in the resolution ledger")
    final, _ = events.read_events(log)
    if len(final) != len(second):
        failures.append("the resolution failure produced a compiler event")
    return {"name": "invocation-counting", "passed": not failures, "failures": failures,
            "events": len(final), "grouped_expectation": 3, "resolution_failures": len(resolutions)}


def check_evidence_integrity() -> dict:
    """Sealed evidence survives cleanup, and a check that edits source is invalidated."""
    case = fixture_case()
    root = WORK / "selftest" / "evidence"
    if root.exists():
        shutil.rmtree(root)
    root.mkdir(parents=True)
    failures = []
    seeded = root / "seeded"
    prepare_variant(case, "regression", seeded)
    sealed = root / "sealed"
    digest = workspace.seal(seeded, sealed)
    shutil.rmtree(seeded)
    graded = grading.grade(sealed, case={**case, "cases_root": str(caselib.CASES_ROOT)},
                           app=case["application"], tools=pack.TOOLS,
                           frozen_app=pack.APPS / case["application"] / "snapshot",
                           cases_root=caselib.CASES_ROOT, staging=root / "grading",
                           cache=root / "cache",
                           expected=oracle_for(case, sealed, root / "oracle-staging"))
    survived = bool(graded["public"] is not None and (graded["hidden"] or {}).get("steps") is not None)
    if not survived:
        failures.append("grading a sealed snapshot after deleting the working copy produced no verdict")
    if graded["public_acceptance"]:
        failures.append("the seeded regression passed public grading")
    # A manifest that edits the project during a check must invalidate the receipt.
    editing = root / "editing"
    shutil.copytree(CONTROLS, editing)
    manifest = {"version": 1, "steps": [
        {"id": "edit-during-check", "kind": "test", "timeout": 120,
         "commands": [["/bin/sh", "-c", "printf '# touched\\n' >> main.my"]]},
        {"id": "guest", "kind": "test", "timeout": 300, "commands": [["bin/mylang", "test", "main.my"]]}]}
    (editing / "verify.json").write_text(json.dumps(manifest, indent=2) + "\n")
    built = workspace.build(root / "editing-ws", cohort_id="selftest", arm="manual",
                            case={"id": "editing", "application": "control", "mutation": None,
                                  "working_directory": "app", "hidden": {"checks": []}},
                            app_snapshot=editing, tools=pack.TOOLS, launcher=LAUNCHER,
                            request_text="editing", docs_repo=REPO)
    outcome = run_launcher(root / "editing-ws", root / "editing-ws" / "app", arm="manual",
                           explicit=((root / "editing-ws" / "app" / "main.my").resolve(),
                                     (root / "editing-ws" / "app" / "verify.json").resolve()))
    receipt = outcome["feedback"] or {}
    if receipt.get("status") != "stale" or receipt.get("identity_unchanged") is not False:
        failures.append(f"a source change during the check did not invalidate the receipt: "
                        f"status={receipt.get('status')} identity_unchanged={receipt.get('identity_unchanged')}")
    return {"name": "evidence-integrity", "passed": not failures, "failures": failures,
            "sealed_digest": digest, "survived_cleanup": survived,
            "stale_receipt_status": receipt.get("status")}


def check_attempt_immutability() -> dict:
    """Terminal cells are never rerun; attempts and identities are never overwritten."""
    root = WORK / "selftest" / "immutability"
    if root.exists():
        shutil.rmtree(root)
    root.mkdir(parents=True)
    failures = []
    manifest = cohort.new_manifest("selftest", ["sexpr-percent"], ["manual"], 2,
                                   {"compiler_sha256": "x"}, 1, "selftest")
    cohort.save(manifest, root / "manifest.json")
    destination = cohort.attempt_dir(root, "manual", "sexpr-percent", 1, 1)
    cohort.reserve(destination)
    try:
        cohort.reserve(destination)
        failures.append("an existing attempt directory was accepted again")
    except SystemExit:
        pass
    if cohort.load(root / "manifest.json")["schedule"][0]["arm"] != "manual":
        failures.append("the frozen schedule changed after it was written")
    return {"name": "attempt-immutability", "passed": not failures, "failures": failures,
            "attempts": len(list((root / "runs").rglob("record.json")))}


def check_scoring_synthetic() -> dict:
    """Resampling keeps repetitions, missing evidence stays unknown, and signs are right."""
    failures = []
    rows = []
    for application in ("app-one", "app-two"):
        for index, case in enumerate(("a", "b", "c")):
            for arm in ("manual", "automatic"):
                for repetition in (1, 2, 3):
                    base = 600.0 - index * 50 - (100.0 if arm == "automatic" else 0.0)
                    rows.append({"application": application, "case": case, "arm": arm,
                                 "repetition": repetition,
                                 "record": {"accepted": True, "elapsed_seconds": base,
                                            "public_acceptance": True, "hidden_acceptance": True}})
    means = scoring.case_means(rows)
    if len(means) != 12:
        failures.append(f"expected 12 case/arm means, saw {len(means)}")
    if any(value is None for value in means.values()):
        failures.append("complete synthetic evidence produced an unknown case mean")
    saving = scoring.saving(means)
    if saving is None or saving <= 0:
        failures.append(f"the improvement sign is wrong: saving={saving}")
    slower = [dict(row) for row in rows]
    for row in slower:
        if row["arm"] == "automatic":
            row["record"] = dict(row["record"], elapsed_seconds=row["record"]["elapsed_seconds"] + 400)
    if not (scoring.saving(scoring.case_means(slower)) < 0):
        failures.append("a slower automatic arm did not produce a negative saving")
    broken = [dict(row) for row in rows]
    broken[0] = dict(broken[0], record=None)
    broken_means = scoring.case_means(broken)
    if not any(value is None for value in broken_means.values()):
        failures.append("a missing record was silently treated as a value")
    gate = scoring.decision(0.5, [0.1, 0.8], {"app-one": 0.4, "app-two": 0.5},
                            {"manual": {"accepted": 3}, "automatic": {"accepted": 3}},
                            {"manual": 5, "automatic": 1}, True)
    if gate["row"] != "keep":
        failures.append(f"the keep row was not selected for a clean positive result: {gate}")
    regression = scoring.decision(-0.05, [-0.2, 0.1], {"app-one": -0.1, "app-two": 0.0},
                                  {"manual": {"accepted": 3}, "automatic": {"accepted": 2}},
                                  {"manual": 5, "automatic": 6}, True)
    if regression["row"] != "regression":
        failures.append(f"an acceptance loss was not reported as a regression: {regression}")
    unknown = scoring.decision(0.3, [0.0, 0.5], {"app-one": 0.3}, {"manual": {"accepted": 1}},
                               {"manual": 1, "automatic": 1}, False)
    if unknown["row"] != "unknown-evidence":
        failures.append("missing evidence did not block a definitive decision")
    interval = scoring.bootstrap(rows, ["app-one", "app-two"], draws=200, seed=7)
    if interval["usable_draws"] != 200:
        failures.append(f"the bootstrap dropped draws: {interval['usable_draws']}")
    return {"name": "scoring-synthetic", "passed": not failures, "failures": failures,
            "saving": saving, "interval": interval["interval"]}


# ── entry point ───────────────────────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    materialize = commands.add_parser("materialize", help="copy the frozen tools and application snapshots")
    materialize.set_defaults(function=cmd_materialize)

    selftest = commands.add_parser("selftest", help="focused, no-model checks of the instrument")
    selftest.set_defaults(function=cmd_selftest)

    preflight = commands.add_parser("preflight", help="reference, regression and wrong-repair checks")
    preflight.add_argument("--all", action="store_true")
    preflight.add_argument("--case")
    preflight.add_argument("--application")
    preflight.add_argument("--split", default="pilot", choices=tuple(caselib.SPLITS))
    preflight.set_defaults(function=cmd_preflight)

    freeze = commands.add_parser("freeze", help="freeze one cohort manifest")
    freeze.add_argument("--cohort", required=True, choices=("pilot", "main"))
    freeze.add_argument("--seed", type=int, required=True)
    freeze.set_defaults(function=cmd_freeze)

    run = commands.add_parser("run", help="launch pending participant sessions")
    run.add_argument("--cohort", required=True, choices=("pilot", "main"))
    run.add_argument("--dry-run", action="store_true")
    run.add_argument("--max-new-sessions", type=int)
    run.add_argument("--cell", help="one ARM/CASE/REPETITION cell")
    run.add_argument("--attempt", type=int, default=1,
                     help="attempt number; a retry needs --reason and never overwrites its predecessor")
    run.add_argument("--reason", help="why a retry is being recorded")
    run.set_defaults(function=cmd_run)

    monitor = commands.add_parser("monitor", help="integrity and status only, never arm comparisons")
    monitor.add_argument("--cohort", required=True, choices=("pilot", "main"))
    monitor.set_defaults(function=cmd_monitor)

    score = commands.add_parser("score", help="score a frozen cohort and write its readout")
    score.add_argument("--cohort", required=True, choices=("pilot", "main"))
    score.set_defaults(function=cmd_score)

    args = parser.parse_args()
    return args.function(args)


if __name__ == "__main__":
    sys.exit(main())

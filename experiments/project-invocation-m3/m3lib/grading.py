#!/usr/bin/env python3
"""Sealed grading: the coordinator's public and hidden verdicts on frozen bytes.

Grading never runs the participant's launcher, environment or limits. It stages a
copy of the sealed snapshot, installs the *frozen* compiler, restores the frozen
public tests, adds the case's hidden fixtures, and runs real `verify.py`
manifests with the frozen tools. The public workload is byte-identical to the
one the participant could run; the hidden workload demands the same contract on
different inputs and is never feedback.

The public verdict is recorded with `tests_restored`, so a submission that
weakened a public test is visible as evidence rather than silently accepted.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

IGNORE = shutil.ignore_patterns("__pycache__", ".mylang-cache", ".cache", ".zig-cache", "_verify", ".m3")


def hash_tree(root: Path, relative: str) -> dict[str, str]:
    target = root / relative
    if not target.exists():
        return {}
    entries: dict[str, str] = {}
    for path in sorted(target.rglob("*")):
        if path.is_file() and "__pycache__" not in path.parts:
            entries[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    return entries


def frozen_tool_wrapper(real: Path) -> str:
    """A regular-file wrapper around a frozen tool.

    A symlink would be simpler, but the guest-test snapshot walker refuses to run
    through a symlink inside the project, and the staging directory *is* the
    project root during grading. The wrapper keeps every byte the participant's
    checks see identical while staying a regular file.
    """
    return f'#!/bin/sh\nexec "{real}" "$@"\n'


def stage(snapshot: Path, destination: Path, *, tools: Path, app: str, frozen_app: Path,
          tests_restored: bool) -> dict:
    """Build the grading tree: sealed source, frozen tools, frozen public tests."""
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(snapshot, destination, ignore=IGNORE)
    bin_directory = destination / "bin"
    if bin_directory.exists():
        shutil.rmtree(bin_directory)
    bin_directory.mkdir()
    for name in ("mylang", "mylang-io"):
        real = tools / "bin" / name
        if real.is_file():
            wrapper = bin_directory / name
            wrapper.write_text(frozen_tool_wrapper(real.resolve()))
            wrapper.chmod(0o755)
    evidence = {"tests_restored": False, "tests_before": hash_tree(snapshot, "tests"),
                "tests_frozen": hash_tree(frozen_app, "tests")}
    if tests_restored:
        target = destination / "tests"
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(frozen_app / "tests", target, ignore=IGNORE)
        evidence["tests_restored"] = True
        evidence["tests_changed_by_participant"] = evidence["tests_before"] != evidence["tests_frozen"]
    for name in ("fixtures",):
        if (frozen_app / name).is_dir():
            shutil.copytree(frozen_app / name, destination / name, dirs_exist_ok=True, ignore=IGNORE)
    return evidence


def run_manifest(manifest: Path, *, tools: Path, destination: Path, cache: Path, timeout: float) -> dict:
    """Run one real verify.py manifest with the frozen workflow scripts.

    The manifest is placed inside the staging directory first, because the
    verifier runs every step with the manifest's own directory as the working
    directory: a manifest left in coordinator storage would run the application's
    relative commands in the wrong tree.
    """
    sys.path.insert(0, str(tools / "scripts"))
    target = destination / manifest.name
    if manifest.resolve() != target.resolve():
        shutil.copy2(manifest, target)
    started = time.monotonic()
    environment = dict(os.environ)
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    environment["MYLANG_MEMORY_LIMIT"] = "2G"
    completed = subprocess.run(
        [sys.executable, str(tools / "scripts" / "verify.py"), str(target),
         "--report", str(destination / (target.stem + "-report.json")), "--cache-dir", str(cache)],
        cwd=destination, capture_output=True, text=True, timeout=timeout, env=environment)
    elapsed = time.monotonic() - started
    report = {}
    report_path = destination / (target.stem + "-report.json")
    if report_path.is_file() and report_path.stat().st_size:
        try:
            report = json.loads(report_path.read_text())
        except json.JSONDecodeError:
            report = {}
    steps = [{"id": step.get("id"), "kind": step.get("kind"), "status": step.get("status")}
             for step in report.get("steps", [])]
    return {"manifest": str(target), "exit": completed.returncode,
            "selected_passed": bool(report.get("selected_passed")),
            "full_manifest_passed": bool(report.get("full_manifest_passed")),
            "grader_ok": bool(report), "steps": steps, "elapsed_seconds": round(elapsed, 3),
            "stderr": completed.stderr[-600:] if not report else "",
            "report": str(report_path) if report_path.is_file() else None}


def hidden_manifest(case: dict, destination: Path, expected: dict | None = None) -> Path | None:
    """Write the case's hidden checks as a real v1 manifest inside the staging tree.

    The authored checks name commands relative to the staged application root
    (`bin/mylang run main.my -- fixtures/hidden/x.sexp`), which is exactly where
    the manifest is placed, so nothing about the coordinator's paths leaks into
    the check definitions. Values come from the frozen oracle measured on the
    pristine reference (`expected`); a diagnostic marker is authored, because it
    is the contract's message rather than an observed value.
    """
    checks = case.get("hidden", {}).get("checks")
    if not checks:
        return None
    expected = expected or {}
    manifest = {"version": 1, "steps": []}
    for step in checks:
        entry = {"id": step["id"], "kind": step.get("kind", "test"),
                 "commands": step["commands"], "timeout": step.get("timeout", 300)}
        measured = expected.get(step["id"])
        if measured is None:
            raise SystemExit(f"case {case['id']}: no frozen oracle value for hidden step {step['id']}")
        entry["expect_exit"] = measured["exit"]
        entry["expect_stdout"] = measured["stdout"]
        if "expect_stderr_contains" in step:
            entry["expect_stderr_contains"] = step["expect_stderr_contains"]
        if "depends_on" in step:
            entry["depends_on"] = step["depends_on"]
        manifest["steps"].append(entry)
    path = destination / "hidden-verify.json"
    path.write_text(json.dumps(manifest, indent=2) + "\n")
    return path


def measure_hidden(snapshot: Path, *, case: dict, tools: Path, staging: Path,
                   timeout: float = 300.0) -> dict:
    """Measure the hidden oracle from the pristine reference with frozen tools."""
    if staging.exists():
        shutil.rmtree(staging)
    stage(snapshot, staging, tools=tools, app=case["application"], frozen_app=snapshot,
          tests_restored=False)
    copy_hidden_fixtures(case, cases_root=Path(case["cases_root"]), destination=staging)
    measured: dict[str, dict] = {}
    environment = dict(os.environ)
    environment["MYLANG_MEMORY_LIMIT"] = "2G"
    for step in case["hidden"]["checks"]:
        argv = [str(staging / part) if part.startswith("bin/") else part for part in step["commands"][0]]
        completed = subprocess.run(argv, cwd=staging, capture_output=True, text=True,
                                   timeout=timeout, env=environment)
        measured[step["id"]] = {"exit": completed.returncode, "stdout": completed.stdout,
                                "stderr_tail": completed.stderr[-200:]}
    return measured


def copy_hidden_fixtures(case: dict, cases_root: Path, destination: Path) -> list[str]:
    source = cases_root / case["id"] / "hidden" / "fixtures"
    copied: list[str] = []
    if not source.is_dir():
        return copied
    for path in sorted(source.rglob("*")):
        if path.is_file():
            target = destination / "fixtures" / "hidden" / path.relative_to(source)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
            copied.append(target.relative_to(destination).as_posix())
    return copied


def grade(snapshot: Path, *, case: dict, app: str, tools: Path, frozen_app: Path,
          cases_root: Path, staging: Path, cache: Path, expected: dict | None = None,
          timeout: float = 1800.0) -> dict:
    """Public and hidden verdicts for one sealed snapshot."""
    evidence = stage(snapshot, staging, tools=tools, app=app, frozen_app=frozen_app, tests_restored=True)
    # The staged copy already carries the frozen public manifest; running it from
    # there keeps every relative command inside the staged tree.
    public = run_manifest(staging / "verify.json", tools=tools, destination=staging, cache=cache,
                          timeout=timeout)
    hidden_fixtures = copy_hidden_fixtures(case, cases_root, staging)
    hidden_path = hidden_manifest(case, staging, expected)
    hidden = (run_manifest(hidden_path, tools=tools, destination=staging, cache=cache, timeout=timeout)
              if hidden_path else None)
    return {
        "public_acceptance": bool(public["selected_passed"]),
        "public": public,
        "hidden_acceptance": bool(hidden and hidden["selected_passed"]),
        "hidden": hidden,
        "hidden_fixtures": hidden_fixtures,
        "tests_restored": evidence["tests_restored"],
        "public_tests_changed_by_participant": evidence.get("tests_changed_by_participant", False),
        "accepted": bool(public["selected_passed"] and hidden and hidden["selected_passed"]),
    }

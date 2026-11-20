#!/usr/bin/env python3
"""Profile one affected native-test edit against a forced run.

Uses the repository's large-project generators, warms a native-test cache, then
applies a used-helper edit and decomposes one `mylang test` invocation:

* whole `mylang test` wall and child work reports (checked/lowered/emitted),
* the edited project's `check-project --report --timings=json` phase p50 over
  the same edit path,
* the selected closure's `build --select-file --report` receipt
  (`compiled_functions`, `reused_functions`, `codegen_seconds`, `link_seconds`),
* the same decomposition for a `--force` run on the restored source.

The select file is the union of the dependency symbols of the tests the edit
actually executed, mapped to qualified names through `native-test-graph`.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(REPO_ROOT / "scripts"))
import profile_large_project as harness  # noqa: E402


def parse_json_lines(text):
    records = []
    for line in text.splitlines():
        if not line.startswith("{"):
            continue
        try:
            records.append(json.loads(line))
        except ValueError:
            continue
    return records


def work_reports(stderr):
    return [r for r in parse_json_lines(stderr) if r.get("version") == "work-report-v1"]


def run(argv, env, timeout=900.0, cwd=None):
    begin = time.monotonic()
    result = subprocess.run([str(item) for item in argv], env=env, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    return {
        "argv": [str(item) for item in argv],
        "exit": result.returncode,
        "wall_ms": (time.monotonic() - begin) * 1000,
        "stdout": result.stdout,
        "stderr": result.stderr,
    }


def native_tests(result):
    for line in result["stdout"].splitlines():
        if not line.startswith("{"):
            continue
        try:
            record = json.loads(line)
        except ValueError:
            continue
        if record.get("version") == "native-tests-v1":
            return record
    return None


def phase_ms(stderr, name):
    for record in parse_json_lines(stderr):
        if record.get("version") == "phase-timings-v1" and record.get("name") == name:
            return record.get("duration_ns", 0) / 1e6
    return None


def closed_closure(test_report, facts):
    """Qualified names of the dependency closure the executed tests selected."""
    by_symbol = {f["symbol"]: f["name"] for f in facts.get("functions", [])}
    selected = set()
    for test in (test_report or {}).get("tests", []):
        if test.get("status") not in ("passed", "failed"):
            continue
        for symbol in test.get("dependencies", []):
            name = by_symbol.get(symbol)
            if name:
                selected.add(name)
    return sorted(selected)


def build_receipt(result):
    for line in result["stdout"].splitlines():
        if not line.startswith("{"):
            continue
        try:
            record = json.loads(line)
        except ValueError:
            continue
        if record.get("version") == "qbe-build-v1":
            return {key: record.get(key) for key in (
                "output_changed", "compiled_functions", "reused_functions", "runtime_reused",
                "frontend_seconds", "codegen_seconds", "link_seconds", "native_seconds")}
    return None


def check_phases(compiler, entry, cache, env, timeout):
    result = run([compiler, "check-project", entry, "--report", "--timings=json", "--cache-dir=" + str(cache)], env, timeout)
    names = ("source_load_parse", "syntax_parse", "dependency_key_preparation", "fresh_body_check",
             "ordinary_body_replay", "retention_store_io", "source_merge", "effect_origin_passes", "total")
    return {name: phase_ms(result["stderr"], name) for name in names if phase_ms(result["stderr"], name) is not None}


def one_state(compiler, entry, cache, args, env, timeout, facts, zig, qbe, mode, library, select_dir):
    result = run([compiler, "test", entry, "--json", "--report", "--cache-dir=" + str(cache),
                  "--zig", zig, "--qbe", qbe, "--mode", mode] + args, env, timeout)
    report = native_tests(result)
    checks = {r.get("command"): {k: v for k, v in (r.get("checked_bodies") or {}).items()}
              for r in work_reports(result["stderr"])}
    selected = closed_closure(report, facts)
    select_path = Path(select_dir) / "select.txt"
    select_path.write_text("\n".join(selected) + "\n")
    library_path = Path(select_dir) / "profile.so"
    build = run([compiler, "build", entry, "--project", "--library", "-o", library_path,
                 "--select-file=" + str(select_path), "--zig", zig, "--qbe", qbe, "--mode", mode,
                 "--report", "--cache-dir=" + str(cache)], env, timeout)
    receipt = build_receipt(build)
    return {
        "test": {"exit": result["exit"], "wall_ms": result["wall_ms"], "report": report},
        "checked_children": checks,
        "selected_functions": len(selected),
        "build": receipt,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--workdir", type=Path, required=True)
    parser.add_argument("--family", default="managed")
    parser.add_argument("--target", type=int, default=100000)
    parser.add_argument("--qbe", default="zig-out/bin/qbe")
    parser.add_argument("--zig", default=shutil.which("zig"))
    parser.add_argument("--mode", default="ReleaseFast")
    parser.add_argument("--samples", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=900.0)
    args = parser.parse_args()
    workdir = args.workdir
    shutil.rmtree(workdir, ignore_errors=True)
    workdir.mkdir(parents=True, exist_ok=True)
    label = f"{args.family}-{args.target // 1000}k"
    root = workdir / "sources" / label
    if args.family == "ordinary":
        modules = 64
        functions_hint = max(1, args.target // (3 * modules))
        functions, lines, total_bytes = harness.size_ordinary(root, args.target, modules, functions_hint)
        entry, paths = harness.generate_ordinary_modules(root, modules, functions)
        edit = lambda token: harness.apply_ordinary_edit(paths, "implementation_edit", token)
        pristine_paths = [root / "m000.my", root / "m001.my", root / "conf.my", root / "main.my"]
    elif args.family == "managed":
        providers = 64
        functions_hint = max(1, args.target // (3 * providers))
        functions, lines, total_bytes = harness.size_managed(root, args.target, providers, functions_hint)
        entry, paths = harness.generate_managed(root, providers, functions)
        pricing = root / "pricing.my"
        original = "    return P.price(policy, subtotal) + P.tag(policy)"
        def edit(token, pricing=pricing, original=original):
            text = pricing.read_text()
            pricing.write_text(text.replace(original, original + f" + {token}"))
        pristine_paths = [root / "pricing.my", root / "conf.my", root / "main.my"]
    else:
        raise SystemExit(f"unknown family {args.family}")
    pristine = {path: path.read_text() for path in pristine_paths}
    entry = str(Path(entry).resolve())
    cache = workdir / "cache"
    select_dir = workdir / "profile"
    select_dir.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env["MYLANG_SEMANTIC_BUDGET"] = "16777216"
    compiler = str(args.compiler.resolve())
    facts_result = run([compiler, "native-test-graph", entry, "--cache-dir=" + str(cache)], env, args.timeout)
    facts = json.loads(facts_result["stdout"])
    document = {"version": "native-path-profile-v1", "compiler": compiler,
                "label": label, "entry": entry, "generated": {"lines": lines, "bytes": total_bytes},
                "host_load": Path("/proc/loadavg").read_text().strip(), "states": {}}
    # Warm cache: one full cold build, then discard the timing.
    warm = run([compiler, "test", entry, "--json", "--report", "--cache-dir=" + str(cache),
                "--zig", args.zig, "--qbe", args.qbe, "--mode", args.mode], env, args.timeout)
    document["warm_exit"] = warm["exit"]
    forced_states = []
    for _ in range(args.samples):
        for path, text in pristine.items():
            path.write_text(text)
        forced_states.append(one_state(compiler, entry, cache, ["--force"], env, args.timeout,
                                       facts, args.zig, args.qbe, args.mode, "", select_dir))
    edited_samples = []
    for index in range(args.samples):
        for path, text in pristine.items():
            path.write_text(text)
        edit(1000 + index)
        edited_samples.append(one_state(compiler, entry, cache, [], env, args.timeout,
                                        facts, args.zig, args.qbe, args.mode, "", select_dir))
    for path, text in pristine.items():
        path.write_text(text)
    document["states"]["forced_run"] = {
        "samples_ms": [s["test"]["wall_ms"] for s in forced_states],
        "median_ms": statistics.median([s["test"]["wall_ms"] for s in forced_states]),
        "test": forced_states[-1]["test"],
        "checked_children": forced_states[-1]["checked_children"],
        "selected_functions": forced_states[-1]["selected_functions"],
        "build": forced_states[-1]["build"],
    }
    last = edited_samples[-1]
    document["states"]["used_helper_edit"] = {
        "samples_ms": [s["test"]["wall_ms"] for s in edited_samples],
        "median_ms": statistics.median([s["test"]["wall_ms"] for s in edited_samples]),
        "test": last["test"],
        "checked_children": last["checked_children"],
        "selected_functions": last["selected_functions"],
        "build": last["build"],
    }
    document["states"]["used_helper_edit"]["check_phases_ms"] = check_phases(compiler, entry, cache, env, args.timeout)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "label": label,
                      "forced_median_ms": document["states"]["forced_run"]["median_ms"],
                      "used_helper_median_ms": document["states"]["used_helper_edit"]["median_ms"]}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

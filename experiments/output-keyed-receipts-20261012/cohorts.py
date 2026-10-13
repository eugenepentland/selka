#!/usr/bin/env python3
"""Run the measurement cohorts of cohorts.md and archive their raw evidence.

    python3 -B cohorts.py --tree PATH --cohort C1|C2|C3|C4 [--samples N]

C1 and C3 run in the target tree (C3 reverts its edit). C2 and C4 run in
scratch worktrees under work/.
Every timed sample takes an exclusive window: the coordinator through
`--timing-window-seconds`, other commands through `scripts/build-slot.sh
timing /usr/bin/time`. Queue time is recorded beside each sample and never
added to it. Medians are reported over the samples; nothing is summed.
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

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import matrix  # noqa: E402

TIME_LINE = re.compile(r"^COHORT-TIME ([0-9.]+) s ([0-9]+) KiB$", re.MULTILINE)


def run(argv, cwd, env, log: Path):
    started = time.monotonic()
    completed = subprocess.run(argv, cwd=cwd, env=env, capture_output=True, text=True, errors="replace")
    log.with_suffix(".stdout").write_text(completed.stdout)
    log.with_suffix(".stderr").write_text(completed.stderr)
    return completed, round(time.monotonic() - started, 3)


def tree_env(tree: Path, **extra) -> dict:
    env = dict(os.environ)
    env.pop("MYL_CORE_LEAKCHECK", None)
    env.update(ZIG_LOCAL_CACHE_DIR=str(tree / ".zig-cache"), TMPDIR=str(tree / ".tmp/work"), PWD=str(tree))
    env.update(extra)
    Path(env["TMPDIR"]).mkdir(parents=True, exist_ok=True)
    return env


def coordinator_sample(tree: Path, env: dict, out: Path, label: str, window: float | None, extra=()) -> dict:
    argv = ["python3", "-B", "scripts/verify_cache.py", "--zig", os.environ["ZIG"], "--profile", "complete", *extra]
    if window:
        argv += ["--timing-window-seconds", str(window)]
    completed, outer = run(argv, tree, env, out / label)
    report = matrix.latest_coordinator_report(tree, 0) or {}
    (out / (label + ".last-run.json")).write_text(json.dumps(report, indent=1, sort_keys=True))
    states = {}
    for row in report.get("actions", []):
        states[row.get("state")] = states.get(row.get("state"), 0) + 1
    language = matrix.action_rows(report).get("language", {})
    return {"label": label, "exit": completed.returncode, "success": report.get("success"),
            "request_seconds": report.get("elapsed_seconds"),
            "gate_admitted_seconds": report.get("gate_admitted_seconds"),
            "build_admitted_seconds": report.get("build_admitted_seconds"),
            "admission_waits": [round(a.get("admission_wait_seconds", 0), 3) for a in report.get("admissions", [])],
            "measurement_window": report.get("measurement_window"),
            "outer_seconds_including_queue": outer, "states": states,
            "language": {"state": language.get("state"),
                         "executed": [m.get("executed") for m in language.get("test_telemetry") or []]},
            "snapshot_statistics": report.get("snapshot_statistics"),
            "executed_actions": sorted(row.get("id") for row in report.get("actions", []) if row.get("state") == "execute"),
            "test_summaries": test_summaries(out, label),
            "action_keys": {row.get("id"): row.get("action_key") for row in report.get("actions", [])}}


SUMMARY = re.compile(r"^(\d+) passed, (\d+) cached, (\d+) failed, (\d+) skipped(.*)$", re.MULTILINE)


def test_summaries(out: Path, label: str) -> dict:
    """The guest-test reuse histogram of a gate: every `mylang test` summary line
    in its logs, counted, plus the totals."""
    lines = []
    for suffix in (".stdout", ".stderr"):
        try:
            lines += SUMMARY.findall((out / (label + suffix)).read_text(errors="replace"))
        except OSError:
            continue
    histogram = {}
    for line in lines:
        text = "%s passed, %s cached, %s failed, %s skipped%s" % line
        histogram[text] = histogram.get(text, 0) + 1
    totals = {"passed": sum(int(l[0]) for l in lines), "cached": sum(int(l[1]) for l in lines),
              "failed": sum(int(l[2]) for l in lines),
              "exec_receipt_hits": sum(int(m.group(1)) for l in lines for m in [re.search(r"(\d+) exec-receipt hits", l[4])] if m)}
    return {"lines": histogram, "totals": totals}


F9_TEST = "test_owned_commands_execute_without_nested_admission_and_expiry_cleans_up"


def failures(out: Path, label: str) -> list[str]:
    """Zig and Python test failures a coordinator request's logs name."""
    found = set()
    for suffix in (".stdout", ".stderr"):
        try:
            text = (out / (label + suffix)).read_text(errors="replace")
        except OSError:
            continue
        found.update(re.findall(r"^error: '(.+)' failed:", text, re.MULTILINE))
        found.update(name for name in re.findall(r"^FAIL: (\S+)", text, re.MULTILINE))
    return sorted(found)


def windowed_samples(tree: Path, env: dict, out: Path, prefix: str, window: float, count: int,
                     extra=(), attempts: int = 4) -> tuple[list, list]:
    """COUNT accepted samples. A sample that failed only on F9 (the expiry
    cleanup test, verification_measurement_test.py:120, which flakes under
    load) is voided, recorded and replaced, at most ATTEMPTS extra times."""
    accepted, voided = [], []
    index = 0
    while len(accepted) < count and index < count + attempts:
        index += 1
        label = "%s-%d" % (prefix, index)
        row = coordinator_sample(tree, env, out, label, window, extra)
        row["failed_tests"] = failures(out, label)
        if not row["success"] and row["failed_tests"] and all(F9_TEST in name for name in row["failed_tests"]):
            row["voided"] = "failed only on F9 (%s)" % F9_TEST
            voided.append(row)
            continue
        accepted.append(row)
    return accepted, voided


def timed_test(tree: Path, env: dict, out: Path, label: str, cache: Path) -> dict:
    argv = [str(tree / "scripts/build-slot.sh"), "timing", "/usr/bin/time", "-f", "COHORT-TIME %e s %M KiB",
            str(tree / "zig-out/bin/mylang"), "test", "tests/lang", "--json", "--cache-dir", str(cache)]
    completed, outer = run(argv, tree, env, out / label)
    found = TIME_LINE.findall(completed.stderr)
    summary = matrix.summarize_tests(matrix.parse_test_report(completed.stdout))
    return {"label": label, "exit": completed.returncode,
            "elapsed_seconds": float(found[-1][0]) if found else None,
            "max_rss_kib": int(found[-1][1]) if found else None,
            "queue_seconds": matrix.admission_queue_seconds(completed.stderr),
            "outer_seconds_including_queue": outer,
            "tests": {k: summary.get(k) for k in ("total", "eligible", "eligible_executed", "eligible_cached",
                                                     "exec_hits", "ir_hits", "failed", "by_reason", "exec_receipts")}}


def median(values):
    values = [v for v in values if isinstance(v, (int, float))]
    return {"n": len(values), "median": statistics.median(values) if values else None,
            "min": min(values) if values else None, "max": max(values) if values else None}


def add_worktree(target: Path, path: Path):
    guardian = HERE / "work/guardian-zig"
    if not guardian.exists():
        guardian.symlink_to((target / "../guardian-zig").resolve())
    if path.exists():
        subprocess.run(["git", "-C", str(target), "worktree", "remove", "--force", str(path)])
        shutil.rmtree(path, ignore_errors=True)
    subprocess.run(["git", "-C", str(target), "worktree", "add", "--detach", str(path), "HEAD"], check=True,
                   capture_output=True)
    (path / ".tmp/work").mkdir(parents=True, exist_ok=True)


def remove_worktree(target: Path, path: Path):
    subprocess.run(["git", "-C", str(target), "worktree", "remove", "--force", str(path)], capture_output=True)
    shutil.rmtree(path, ignore_errors=True)


def build(tree: Path, env: dict, out: Path, label: str) -> int:
    completed, _ = run([str(tree / "scripts/build-slot.sh"), "build", "zig", "build"], tree, env, out / label)
    return completed.returncode


def manifest(target: Path, tree: Path, out: Path, label: str):
    class Args:
        pass
    args = Args()
    for name, value in dict(tree=str(tree), work=None, evidence=str(out), dry_run=False, keep_work=False,
                            lang_entry=None, small_entry="tests/lang/frontend_numbers.my", old_ref="f6971a623",
                            build_env=None).items():
        setattr(args, name, value)
    frozen = dict(matrix.manifest(matrix.Context(args)), label=label, written=matrix.now())
    (out / ("manifest-" + label + ".json")).write_text(json.dumps(frozen, indent=1, sort_keys=True, default=str))
    return frozen


# `measurement_window_seconds` is part of the coordinator's
# `common.execution_limits`, so a windowed request never reuses an unwindowed
# receipt (finding F14). Primes therefore use the samples' own window.
C1_WINDOW = 900
C3_WINDOW = 1800


def c1(target: Path, out: Path, samples: int) -> dict:
    env = tree_env(target)
    before = manifest(target, target, out, "C1-before")
    prime = coordinator_sample(target, env, out, "prime", C1_WINDOW)
    prime["failed_tests"] = failures(out, "prime")
    rows, voided = windowed_samples(target, env, out, "sample", C1_WINDOW, samples)
    after = manifest(target, target, out, "C1-after")
    return {"cohort": "C1", "window_seconds": C1_WINDOW, "prime": prime, "samples": rows, "voided": voided,
            "compiler_stable": before["compiler_sha256"] == after["compiler_sha256"],
            "keys_stable": all(r["action_keys"] == prime["action_keys"] for r in rows),
            "request_seconds": median([r["request_seconds"] for r in rows]),
            "gate_admitted_seconds": median([r["gate_admitted_seconds"] for r in rows])}


def c2(target: Path, out: Path, samples: int) -> dict:
    tree = HERE / "work/c2-tree"
    add_worktree(target, tree)
    env = tree_env(tree)
    cache = HERE / "work/c2-cache"
    shutil.rmtree(cache, ignore_errors=True)
    result = {"cohort": "C2", "build": build(tree, env, out, "build-0")}
    manifest(target, tree, out, "C2-before")
    result["warm"] = [timed_test(tree, env, out, "warm-%d" % i, cache) for i in (1, 2)]
    c2 = []
    for i in range(1, samples + 1):
        with open(tree / "src/parser.zig", "a") as handle:
            handle.write("\n// cohort C2 edit %d\n" % i)
        status = build(tree, env, out, "build-c2-%d" % i)
        row = timed_test(tree, env, out, "c2-edit-%d" % i, cache)
        row["build_exit"] = status
        c2.append(row)
    result["c2"] = c2
    result["c2_elapsed"] = median([r["elapsed_seconds"] for r in c2])
    manifest(target, tree, out, "C2-after")
    subprocess.run(["git", "-C", str(tree), "checkout", "--", "src/parser.zig"])
    remove_worktree(target, tree)
    return result


def c3(target: Path, out: Path, samples: int) -> dict:
    """Complete verification after a comment edit, in the target tree itself:
    scratch trees under work/ nest deep enough to fail path-sensitive CLI tests
    (REPORT.md, row 12), which would turn every sample into a failing gate.
    The edit is reverted afterwards, whatever happens."""
    env = tree_env(target)
    manifest(target, target, out, "C3-before")
    result = {"cohort": "C3", "window_seconds": C3_WINDOW,
              "prime": coordinator_sample(target, env, out, "prime", C3_WINDOW)}
    result["prime"]["failed_tests"] = failures(out, "prime")
    rows, voided = [], []
    try:
        edit = 0
        while len(rows) < samples and edit < samples + 4:
            edit += 1
            with open(target / "src/parser.zig", "a") as handle:
                handle.write("\n// cohort C3 edit %d\n" % edit)
            accepted, void = windowed_samples(target, env, out, "edit-%d" % edit, C3_WINDOW, 1, attempts=0)
            rows += accepted
            voided += void
    finally:
        subprocess.run(["git", "-C", str(target), "checkout", "--", "src/parser.zig"])
    result["samples"] = rows
    result["voided"] = voided
    result["request_seconds"] = median([r["request_seconds"] for r in rows])
    result["gate_admitted_seconds"] = median([r["gate_admitted_seconds"] for r in rows])
    return result


STORES = {"mode": "evidence"}


def sharing_env(tree: Path, shared: Path, **extra) -> dict:
    """A worktree's launcher with its shared stores named explicitly (the
    defaults are off). Mode "evidence" names only the coordinator's evidence
    store; mode "all" also names the native compiler-artifact and test-receipt
    stores, which every gate test then sees (F18: one test is not hermetic
    against them)."""
    stores = {"MYLANG_VERIFICATION_SHARED_CACHE": str(shared / "verification")}
    if STORES["mode"] == "all":
        stores.update(MYLANG_COMPILER_SHARED_CACHE=str(shared / "compiler"), MYLANG_TEST_SHARED_CACHE=str(shared / "tests"))
    return tree_env(tree, **stores, **extra)


def c4(target: Path, out: Path, samples: int, shared: Path) -> dict:
    """One sample per fresh worktree, all sharing one set of stores that the
    first worktree fills, so later worktrees may reuse what it published. A
    sample that fails only on F9 is voided and replaced by another fresh tree."""
    shared.mkdir(parents=True, exist_ok=True)
    rows, voided = [], []
    index = 0
    while len(rows) < samples and index < samples + 3:
        index += 1
        tree = HERE / ("work/c4-tree-%d" % index)
        add_worktree(target, tree)
        env = sharing_env(tree, shared, CODEX_THREAD_ID="lane-f-c4-%d" % index, TERM="dumb")
        status = build(tree, env, out, "build-%d" % index)
        manifest(target, tree, out, "C4-%d" % index)
        row = coordinator_sample(tree, env, out, "sample-%d" % index, C3_WINDOW)
        row["build_exit"] = status
        row["failed_tests"] = failures(out, "sample-%d" % index)
        remove_worktree(target, tree)
        if not row["success"] and row["failed_tests"] and all(F9_TEST in name for name in row["failed_tests"]):
            row["voided"] = "failed only on F9 (%s)" % F9_TEST
            voided.append(row)
            continue
        rows.append(row)
    return {"cohort": "C4", "stores": STORES["mode"], "shared": str(shared), "samples": rows, "voided": voided,
            "keys_equal_to_first": [r["action_keys"] == rows[0]["action_keys"] for r in rows],
            "request_seconds": median([r["request_seconds"] for r in rows]),
            "gate_admitted_seconds": median([r["gate_admitted_seconds"] for r in rows])}


def c5(target: Path, out: Path, agents: int, shared: Path) -> dict:
    """Ten agents, one base commit: AGENTS fresh worktrees, each built under
    `build` admission (not timed), then every complete verification started at
    once with its own CODEX_THREAD_ID, all sharing one set of stores, with no
    timing window. Measures deduplication: how many requests executed each group."""
    shared.mkdir(parents=True, exist_ok=True)
    trees = [HERE / ("work/c5-tree-%d" % i) for i in range(1, agents + 1)]
    builds = []
    for i, tree in enumerate(trees, 1):
        add_worktree(target, tree)
        builds.append(build(tree, sharing_env(tree, shared), out, "build-%d" % i))
    manifest(target, trees[0], out, "C5")
    processes = []
    started = time.monotonic()
    for i, tree in enumerate(trees, 1):
        env = sharing_env(tree, shared, CODEX_THREAD_ID="lane-f-c5-%d" % i, TERM="dumb")
        argv = ["python3", "-B", "scripts/verify_cache.py", "--zig", os.environ["ZIG"], "--profile", "complete"]
        stdout = open(out / ("agent-%d.stdout" % i), "w")
        stderr = open(out / ("agent-%d.stderr" % i), "w")
        processes.append((i, tree, subprocess.Popen(argv, cwd=tree, env=env, stdout=stdout, stderr=stderr), time.monotonic(), stdout, stderr))
    rows, ends = [], []
    for i, tree, process, launched, stdout, stderr in processes:
        status = process.wait()
        ends.append(time.monotonic())
        stdout.close()
        stderr.close()
        report = matrix.latest_coordinator_report(tree, 0) or {}
        (out / ("agent-%d.last-run.json" % i)).write_text(json.dumps(report, indent=1, sort_keys=True))
        states = {}
        for row in report.get("actions", []):
            states[row.get("state")] = states.get(row.get("state"), 0) + 1
        rows.append({"agent": i, "exit": status, "success": report.get("success"),
                     "request_seconds": report.get("elapsed_seconds"),
                     "gate_admitted_seconds": report.get("gate_admitted_seconds"),
                     "build_admitted_seconds": report.get("build_admitted_seconds"),
                     "admission_waits": [round(a.get("admission_wait_seconds", 0), 3) for a in report.get("admissions", [])],
                     "harness_seconds_from_launch": round(ends[-1] - launched, 3), "states": states,
                     "executed_actions": sorted(r.get("id") for r in report.get("actions", []) if r.get("state") == "execute"),
                     "fresh_actions": sorted(r.get("id") for r in report.get("actions", []) if r.get("state") == "fresh"),
                     "failed_tests": failures(out, "agent-%d" % i), "test_summaries": test_summaries(out, "agent-%d" % i),
                     "action_keys": {r.get("id"): r.get("action_key") for r in report.get("actions", [])}})
    wall = round(max(ends) - started, 3)
    for tree in trees:
        remove_worktree(target, tree)
    executions = {}
    for row in rows:
        for name in row["executed_actions"] + row["fresh_actions"]:
            executions[name] = executions.get(name, 0) + 1
    always_fresh = sorted(set.intersection(*[set(r["fresh_actions"]) for r in rows])) if rows else []
    cacheable = {name: count for name, count in executions.items() if name not in always_fresh}
    return {"cohort": "C5", "stores": STORES["mode"], "agents": agents, "shared": str(shared), "builds": builds, "requests": rows,
            "wall_seconds_all_requests": wall, "always_fresh": always_fresh,
            "executions_per_cacheable_group": dict(sorted(cacheable.items())),
            "groups_executed_once": sum(1 for c in cacheable.values() if c == 1),
            "groups_executed_more_than_once": {k: c for k, c in cacheable.items() if c > 1},
            "keys_equal_across_agents": [r["action_keys"] == rows[0]["action_keys"] for r in rows],
            "gate_admitted_seconds": median([r["gate_admitted_seconds"] for r in rows])}


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--tree", required=True)
    parser.add_argument("--cohort", required=True, choices=("C1", "C2", "C3", "C4", "C5"))
    parser.add_argument("--samples", type=int, default=5)
    parser.add_argument("--stores", choices=("evidence", "all"), default="evidence",
                        help="C4/C5: share only the coordinator evidence store, or the native stores too")
    parser.add_argument("--shared", help="C4: a shared evidence store warmed by another worktree")
    parser.add_argument("--evidence", default=str(HERE / "evidence-phase2/cohorts"))
    args = parser.parse_args(argv)
    if not os.environ.get("ZIG") or not os.environ.get("MYLANG_SLOT_DIR"):
        print("cohorts: source ~/.config/mylang/dev-env.sh first", file=sys.stderr)
        return 2
    STORES["mode"] = args.stores
    target = Path(args.tree).resolve()
    out = Path(args.evidence) / args.cohort
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    if args.cohort == "C1":
        result = c1(target, out, args.samples)
    elif args.cohort == "C2":
        result = c2(target, out, args.samples)
    elif args.cohort == "C3":
        result = c3(target, out, args.samples)
    elif args.cohort == "C4":
        result = c4(target, out, args.samples, Path(args.shared).resolve())
    else:
        result = c5(target, out, args.samples, Path(args.shared).resolve())
    (out / "result.json").write_text(json.dumps(result, indent=1, sort_keys=True, default=str))
    print(json.dumps({k: v for k, v in result.items() if k not in ("samples", "c2", "warm", "prime", "voided", "requests")},
                     indent=1, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

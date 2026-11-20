#!/usr/bin/env python3
r"""External, unregistered developer-loop profiler (Python standard library only).

Run from a dedicated linked worktree; supply an already built compiler:
  python3 scripts/dev_loop_profile.py --compiler /path/to/selka \
      --output /tmp/dev-loop-profile --repeats 5
  python3 scripts/dev_loop_profile.py --dry-run
  python3 scripts/dev_loop_profile.py --self-test

The default matrix uses examples/testing/main.selka (main returns zero). Use --entry,
--guest-entry, --guest-filter and --zig-filter for another workload. --case is
repeatable; omission runs the entire fixed matrix. Output must be a NEW directory.
Warm samples have one untimed priming invocation, independently for every repeat.
Cold samples have empty application, native-object, tool-identity and Zig caches.
They include first-use runtime compilation and toolchain approval costs.
OS page caches and CPU caches are NOT flushed. --no-cache alone is insufficient:
the compiler still consults its native-object store, which we also isolate.

--stats is opt-in because it changes lowering and can add remark compilations.
Native stage times include nested intervals (native includes linker); never sum
them or divide them by unit counts. Newer cache-report-v1 producers optionally
supply measured native compile intervals and source ownership per unit; legacy
reports retain aggregate counts only. Frontend per-unit costs are never inferred.

Only the stdlib-touch case changes source metadata: it touches one non-fixture
file, restores its atime/mtime in finally, and never writes its contents. ctime
cannot be restored. The Zig unit case temporarily redirects its hardcoded
.selka-cache/unit-tests path and requires that path to be absent before starting.
No gate or corpus is invoked. Timing admission uses the same
bounded measurement window as verification_measurement.py; queue time is excluded.
"""

import argparse
from collections import defaultdict
from contextlib import contextmanager, nullcontext
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import statistics
import subprocess
import sys
import threading
import time


CASES = {
    "check-cold": "empty",
    "check-warm": "primed",
    "run-uncached": "empty; --no-cache",
    "run-cached": "primed",
    "build": "empty",
    "build-run": "empty",
    "guest-uncached": "empty; --no-cache",
    "guest-cached": "primed",
    "zig-test-units": "primed; filtered tests forced to execute",
    "zig-stdlib-touch": "primed; stdlib mtime changed",
}
VERSIONS = {"cache-report-v1", "work-report-v1", "phase-timings-v1",
            "native-tests-v1", "frontend-cache-v1"}
COUNTS = ("units", "reused", "compiled", "verified", "processes")
STATS_PATTERNS = (
    (r"selka-core: inlined (\d+) calls, unswitched (\d+) loops, versioned (\d+) loops, proved (\d+) checks, vectorized (\d+) loops",
     ("inlined_calls", "unswitched_loops", "versioned_loops", "proved_checks", "vector_plans")),
    (r"selka-core: ownership: (\d+) updates in place; (\d+) drops; (\d+) lists on the stack",
     ("updates_in_place", "drops", "stack_lists")),
    (r"selka-core: cost: (\d+) checks kept; (\d+) allocation sites \((\d+) unresolved calls\); (\d+) unknown loops",
     ("checks_kept", "allocation_sites", "unresolved_calls", "unknown_loops")),
)


def distribution(values):
    """Nearest-rank p95, including for a single observation; no interpolation."""
    values = sorted(values)
    if not values:
        return None
    return dict(count=len(values), median=statistics.median(values),
                p95=values[math.ceil(.95 * len(values)) - 1],
                min=values[0], max=values[-1])


def nonnegative(value):
    return type(value) is int and value >= 0


def json_documents(text):
    """Read JSONL and multiline JSON amid diagnostics, without parsing strings."""
    decoder = json.JSONDecoder()
    position = 0
    while position < len(text):
        end = text.find("\n", position)
        end = len(text) if end < 0 else end
        start = position
        while start < end and text[start] in " \t\r":
            start += 1
        if start < end and text[start] == "{":
            try:
                value, used = decoder.raw_decode(text, start)
            except ValueError:
                if any(version in text[start:end] for version in VERSIONS):
                    raise ValueError("malformed compiler report JSON") from None
            else:
                yield value
                position = used
                continue
        position = end + 1


def parse_reports(stdout, stderr, *, guest=False):
    """Preserve producer documents; normalize only observed counts and times."""
    documents = [row for row in json_documents(stderr)
                 if isinstance(row, dict) and row.get("version") in VERSIONS]
    # Program stdout is arbitrary: only a guest-test command owns JSON stdout.
    if guest:
        documents += [row for row in json_documents(stdout)
                      if isinstance(row, dict) and row.get("version") == "native-tests-v1"]
    result = dict(documents=documents, unit_counts=None, work_counts={},
                  phases=[], stats={}, guest_counts=None, reported_sources=[], unit_timings=None)

    def phase(name, duration, inclusive, source):
        if not nonnegative(duration) or type(inclusive) is not bool:
            raise ValueError("invalid phase timing: " + name)
        result["phases"].append(dict(name=name, duration_ns=duration,
                                     inclusive=inclusive, source=source))

    for row in documents:
        version = row["version"]
        if version == "cache-report-v1":
            if result["unit_counts"] is not None:
                raise ValueError("multiple native cache reports in one invocation")
            if not all(nonnegative(row.get(key)) for key in COUNTS):
                raise ValueError("invalid native unit counts")
            result["unit_counts"] = {key: row[key] for key in COUNTS}
            result["program"] = row.get("program")
            if "unit_timings" in row:
                details = row["unit_timings"]
                if not isinstance(details, list):
                    raise ValueError("invalid unit timing list")
                for unit in details:
                    if (not isinstance(unit, dict) or
                        not all(isinstance(unit.get(k), str) for k in ("name", "source_path", "kind", "key", "scope")) or
                        unit.get("action") not in ("reused", "compiled", "verified", "failed") or
                        (unit.get("compile_ns") is not None and not nonnegative(unit["compile_ns"])) or
                        (unit["action"] == "reused" and unit.get("compile_ns") is not None)):
                        raise ValueError("invalid native unit timing")
                result["unit_timings"] = details
            stages = row.get("stages") or {}
            for name, value in stages.get("nanoseconds", {}).items():
                if name == "frontend_phases":
                    for item in value:
                        phase("core.frontend." + item["name"], item["nanoseconds"],
                              item["inclusive"], stages.get("version"))
                else:
                    phase("core." + name, value, name in ("frontend", "native"),
                          stages.get("version"))
            storage = row.get("storage") or {}
            if "flush_nanoseconds" in storage:
                phase("core.storage_flush", storage["flush_nanoseconds"], False, version)
        elif version == "work-report-v1":
            # Session totals and fingerprint equality are not request reuse.
            for name, value in row.get("request", row).items():
                if isinstance(value, dict) and "performed" in value and "reused" in value:
                    if not all(nonnegative(value.get(k)) for k in ("performed", "reused")):
                        raise ValueError("invalid work counts: " + name)
                    result["work_counts"][name] = {k: value[k] for k in ("performed", "reused")}
            if "reused_results" in row:
                if not nonnegative(row["reused_results"]):
                    raise ValueError("invalid whole-result reuse count")
                result["work_counts"]["whole_results"] = {"reused": row["reused_results"]}
        elif version == "phase-timings-v1" and row.get("kind") == "timing":
            phase(row["name"], row["duration_ns"], row["inclusive"], version)
        elif version == "native-tests-v1":
            names = ("passed", "cached", "failed", "skipped", "unsupported")
            if not all(nonnegative(row.get(key)) for key in names):
                raise ValueError("invalid guest-test counts")
            result["guest_counts"] = {key: row[key] for key in names}
            result["reported_sources"].extend(row.get("sources", []))
            # cache.work intervals can overlap. Preserve them in documents;
            # do not treat them as disjoint compiler phases or unit durations.

    for line in stderr.splitlines():
        for pattern, names in STATS_PATTERNS:
            match = re.fullmatch(pattern, line)
            if match:
                result["stats"].update(zip(names, map(int, match.groups())))
        match = re.fullmatch(r"selka-core: LLVM vectorized (\d+|unknown); (\d+) unknown loops; remarks (available|unavailable); (\d+) compiles in (\d+) ns; (\d+) remark queries reused", line)
        if match:
            vectorized, unknown, available, compiles, elapsed, reused = match.groups()
            result["stats"].update(llvm_vectorized=None if vectorized == "unknown" else int(vectorized),
                                   llvm_unknown_loops=int(unknown), remarks=available,
                                   remark_compiles=int(compiles), remark_compile_ns=int(elapsed),
                                   remark_queries_reused=int(reused))
        match = re.fullmatch(r"timings: native_ns=(\d+)", line)
        if match:
            phase("guest_execution", int(match[1]), True, "--timings")
        match = re.fullmatch(r"selka-core: cache: (\d+) units, (\d+) reused, (\d+) compiled, (\d+) verified; program (\w+); (\d+) processes(?:; (\d+) shared mismatches)?", line)
        if match and result["unit_counts"] is None:
            units, reused, compiled, verified, program, processes, mismatches = match.groups()
            result["unit_counts"] = dict(zip(COUNTS, map(int, (units, reused, compiled, verified, processes))))
            result.update(program=program, shared_mismatches=int(mismatches or 0))
        if line == "selka-core: cache: replayed the last identical build" and result["unit_counts"] is None:
            result.update(unit_counts=dict.fromkeys(COUNTS, 0), program="replayed")
    return result


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], stderr=subprocess.PIPE).decode("utf-8", "surrogateescape")


def git_state(root, ref):
    return dict(commit=git(root, "rev-parse", "HEAD").strip(),
                branch=git(root, "branch", "--show-current").strip(),
                diff_ref=ref, diff_commit=git(root, "rev-parse", "--verify", ref + "^{commit}").strip(),
                changed_files=git(root, "diff", "--name-only", "-z", ref, "--").split("\0")[:-1],
                status=git(root, "status", "--porcelain=v1", "-z").split("\0")[:-1])


def host_state():
    def read(path):
        try:
            return Path(path).read_text().strip()
        except OSError:
            return None
    cpuinfo = read("/proc/cpuinfo") or ""
    model = re.search(r"^model name\s*:\s*(.*)$", cpuinfo, re.MULTILINE)
    return dict(platform=platform.platform(), python=platform.python_version(),
                cpu_model=model.group(1) if model else platform.processor(),
                logical_cpus=os.cpu_count(), affinity=sorted(os.sched_getaffinity(0)),
                load_average=list(os.getloadavg()),
                governors={p.parent.parent.name: read(p) for p in
                           Path("/sys/devices/system/cpu").glob("cpu[0-9]*/cpufreq/scaling_governor")},
                page_cache="uncontrolled; never dropped", hardware_caches="uncontrolled")


def private_environment(directory, jobs):
    """Override every store used by these commands without repurposing HOME."""
    paths = {"XDG_CACHE_HOME": "xdg", "ZIG_LOCAL_CACHE_DIR": "zig-local",
             "ZIG_GLOBAL_CACHE_DIR": "zig-global", "TMPDIR": "tmp",
             "SELKA_CORE_RUNTIME_CACHE": "native-objects",
             "SELKA_CORE_TEST_CACHE": "core-tests"}
    overrides = {name: str(directory / child) for name, child in paths.items()}
    for value in overrides.values():
        Path(value).mkdir(parents=True, exist_ok=False)
    overrides.update(SELKA_COMPILER_SHARED_CACHE="", SELKA_TEST_SHARED_CACHE="", SELKA_STAGE_SHARED_CACHE="", SELKA_PROFILE_DIR="",
                     SELKA_JOBS=str(jobs), SELKA_UNIT_JOBS=str(jobs))
    return dict(os.environ, **overrides), overrides


def command_for(case, args, directory):
    if case.startswith("zig-"):
        command = [str(args.zig), "build"]
        if case == "zig-test-units":
            command += ["test-units", "-Dtest-filter=" + args.zig_filter, "-Dtest-rerun=true"]
        return command + ["-j" + str(args.jobs), "--cache-dir", str(directory / "zig-local"),
                          "--prefix", str(directory / "install"), "--summary", "all"]
    cache = ["--cache-dir", str(directory / "compiler-cache")]
    if case.startswith("check-"):
        return [str(args.compiler), "check", args.entry, *cache, "--report", "--timings=json"]
    if case.startswith("guest-"):
        command = [str(args.compiler), "test", args.guest_entry, "--filter", args.guest_filter,
                   "--json", "--jobs", str(args.jobs), "--zig", str(args.zig), *cache]
    else:
        command = [str(args.compiler), "run" if case.startswith("run-") else "build",
                   args.entry, *cache, "--zig", str(args.zig), "--report"]
        if case == "build":
            command += ["-o", str(directory / "program")]
        else:
            command += (["--run"] if case == "build-run" else []) + ["--timings"]
        if args.stats:
            command += ["--stats"]
    if case.endswith("-uncached"):
        command += ["--no-cache"]
    return command


@contextmanager
def touch_stdlib(path):
    """Restore timestamps even after a timeout, failed build or interruption."""
    before = path.stat()
    digest = sha256(path)
    try:
        os.utime(path, ns=(before.st_atime_ns, max(time.time_ns(), before.st_mtime_ns + 1)))
        yield dict(path=str(path), sha256=digest, before_mtime_ns=before.st_mtime_ns,
                   touched_mtime_ns=path.stat().st_mtime_ns, content_changed=False,
                   ctime_restorable=False)
    finally:
        try:
            unchanged = sha256(path) == digest
        finally:
            os.utime(path, ns=(before.st_atime_ns, before.st_mtime_ns))
        if not unchanged:
            raise RuntimeError("stdlib content changed concurrently: " + str(path))


@contextmanager
def unit_cache(root, directory):
    """Redirect the Zig unit harness's hardcoded worktree cache, then remove it.

    There is no CLI/env override for .selka-cache/unit-tests on current main.
    Refuse an existing directory rather than moving or deleting someone's cache.
    """
    target = directory / "unit-tests"
    target.mkdir()
    link = root / ".selka-cache" / "unit-tests"
    link.parent.mkdir(exist_ok=True)
    link.symlink_to(target, target_is_directory=True)
    try:
        yield
    finally:
        if link.is_symlink() and link.readlink() == target:
            link.unlink()
        else:
            raise RuntimeError("private unit cache link changed concurrently: " + str(link))


def source_context(root, changed, case, args, telemetry):
    def relative(path):
        path = Path(path)
        try:
            return str((root / path).resolve().relative_to(root))
        except ValueError:
            return str(path)
    sources = sorted({relative(p) for p in telemetry.get("reported_sources", []) if isinstance(p, str)})
    entries = [] if case.startswith("zig-") else [args.guest_entry if case.startswith("guest-") else args.entry]
    details = telemetry.get("unit_timings")
    mapping = None if details is None else [dict(unit=u["name"], kind=u["kind"], key=u["key"],
        source=relative(u["source_path"]), changed=relative(u["source_path"]) in changed,
        action=u["action"], compile_ns=u.get("compile_ns"), scope=u["scope"]) for u in details]
    return dict(scope="source ownership and changed-file association; not causal attribution or frontend per-unit timing",
                entries=entries, changed_files=changed, reported_sources=sources,
                changed_reported_sources=sorted(set(changed) & set(sources)),
                changed_entries=sorted(set(changed) & {relative(p) for p in entries}),
                touched_source=args.touch_stdlib if case == "zig-stdlib-touch" else None,
                unit_to_source=mapping)


def require_reports(case, telemetry):
    versions = {row["version"] for row in telemetry["documents"]}
    if case.startswith("check-"):
        if not {"work-report-v1", "phase-timings-v1"} <= versions:
            raise ValueError("successful check omitted work/phase reports")
    elif case.startswith("guest-"):
        counts = telemetry["guest_counts"]
        if counts is None or counts["passed"] + counts["cached"] == 0 or counts["failed"]:
            raise ValueError("guest report has no successful selected tests or reports failures")
    elif not case.startswith("zig-") and telemetry["unit_counts"] is None:
        raise ValueError("successful native command omitted cache report")


def execute(command, *, root, environment, directory, label, timeout, case, records):
    stdout_path, stderr_path = directory / (label + ".stdout"), directory / (label + ".stderr")
    record = dict(command=command, role=label, stdout=str(stdout_path), stderr=str(stderr_path),
                  status="running", returncode=None, telemetry=None)
    records.append(record)
    child = None
    started = time.perf_counter_ns()
    try:
        with stdout_path.open("wb") as stdout, stderr_path.open("wb") as stderr:
            started = time.perf_counter_ns()
            child = subprocess.Popen(command, cwd=root, env=environment, stdin=subprocess.DEVNULL,
                                     stdout=stdout, stderr=stderr, start_new_session=True)
            expired = threading.Event()
            def stop_child():
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            def deadline():
                if child.poll() is None:
                    expired.set()
                    stop_child()
            timer = threading.Timer(timeout, deadline)
            timer.daemon = True
            timer.start()
            try:
                # wait(timeout=...) polls on POSIX and overstates fast loops by
                # up to 50 ms. A watchdog lets the measurement use blocking waitpid.
                record["returncode"] = child.wait()
                record["wall_ns"] = time.perf_counter_ns() - started
                if expired.is_set():
                    raise subprocess.TimeoutExpired(command, timeout)
            except BaseException:
                # Kill descendants too: an orphan zig cc would distort later runs.
                stop_child()
                child.wait()
                raise
            finally:
                timer.cancel()
                timer.join()
        record["telemetry"] = parse_reports(stdout_path.read_text(errors="replace"),
                                             stderr_path.read_text(errors="replace"),
                                             guest=case.startswith("guest-"))
        if record["returncode"] != 0:
            raise RuntimeError(f"{case} {label} exited {record['returncode']}; see {stderr_path}")
        require_reports(case, record["telemetry"])
        record["status"] = "ok"
    except BaseException as error:
        record.update(status="failed", error=type(error).__name__ + ": " + str(error))
        raise
    finally:
        record.setdefault("wall_ns", time.perf_counter_ns() - started)
        if child is not None:
            record["returncode"] = child.returncode
    return record


def summarize(samples):
    good = [s for s in samples if s["measured"] and s["measured"]["status"] == "ok"]
    units, work, phases, stats, guest, native_units = (defaultdict(list) for _ in range(6))
    for sample in good:
        data = sample["measured"]["telemetry"]
        for key, value in (data["unit_counts"] or {}).items():
            units[key].append(value)
        for name, counts in data["work_counts"].items():
            for key, value in counts.items():
                work[name + "." + key].append(value)
        # Same-named emitted intervals are grouped within an invocation first.
        per_sample = defaultdict(int)
        for phase in data["phases"]:
            per_sample[(phase["name"], phase["inclusive"])] += phase["duration_ns"]
        for key, value in per_sample.items():
            phases[key].append(value)
        for unit in data.get("unit_timings") or []:
            if unit.get("compile_ns") is not None:
                native_units[tuple(unit[k] for k in ("source_path", "kind", "name", "action", "scope"))].append(unit["compile_ns"])
        for key, value in data["stats"].items():
            if nonnegative(value):
                stats[key].append(value)
        for key, value in (data["guest_counts"] or {}).items():
            guest[key].append(value)
    return dict(successful_repeats=len(good), attempted_repeats=len(samples),
                wall_ns=distribution([s["measured"]["wall_ns"] for s in good]),
                unit_counts={k: distribution(v) for k, v in units.items()},
                native_unit_compiles=[dict(source_path=k[0], kind=k[1], name=k[2], action=k[3], scope=k[4],
                                           compile_ns=distribution(v)) for k, v in native_units.items()],
                work_counts={k: distribution(v) for k, v in work.items()},
                phases=[dict(name=k[0], inclusive=k[1], duration_ns=distribution(v)) for k, v in phases.items()],
                stats={k: distribution(v) for k, v in stats.items()},
                guest_counts={k: distribution(v) for k, v in guest.items()})


def markdown(report):
    lines = ["# Developer loop profile", "", f"Status: **{report['status']}**. Commit: `{report['git']['commit']}`.",
             f"Compiler SHA-256: `{report['compiler']['sha256']}`.", "",
             "Wall times include process startup and report output; priming and admission wait are excluded.",
             "p95 uses nearest rank. Only successful measurements enter the distributions.", "",
             "| Case | Cache state | n | Median ms | p95 ms | Min–max ms | Units / reused / compiled / verified / processes |",
             "|---|---|---:|---:|---:|---:|---|"]
    details = []
    for case in report["cases"]:
        summary = case["summary"]
        wall = summary["wall_ns"]
        timing = [f"{wall[k] / 1e6:.3f}" for k in ("median", "p95", "min", "max")] if wall else ["—"] * 4
        counts = summary["unit_counts"]
        units = " / ".join(f"{counts[k]['median']:g}" if k in counts else "—" for k in COUNTS)
        lines.append(f"| {case['name']} | {case['cache_state']} | {summary['successful_repeats']} | {timing[0]} | {timing[1]} | {timing[2]}–{timing[3]} | {units} |")
        if summary["phases"]:
            largest = sorted(summary["phases"], key=lambda p: p["duration_ns"]["median"], reverse=True)[:4]
            phases = ", ".join(f"{p['name']} {p['duration_ns']['median'] / 1e6:.3f} ms" + (" (inclusive)" if p["inclusive"] else "") for p in largest)
            details.append(f"- **{case['name']}** phase medians: {phases}.")
        if summary["native_unit_compiles"]:
            largest = sorted(summary["native_unit_compiles"], key=lambda u: u["compile_ns"]["median"], reverse=True)[:4]
            details.append(f"- **{case['name']}** native unit compile medians: " + ", ".join(
                f"{u['name']} {u['compile_ns']['median'] / 1e6:.3f} ms ({u['action']})" for u in largest) + ".")
        if summary["work_counts"]:
            nonzero = {k: v for k, v in summary["work_counts"].items() if v["median"]}
            details.append(f"- **{case['name']}** nonzero work medians: " + (", ".join(f"{k}={v['median']:g}" for k, v in nonzero.items()) or "none") + ".")
        if summary["guest_counts"]:
            details.append(f"- **{case['name']}** guest-test medians: " + ", ".join(f"{k}={v['median']:g}" for k, v in summary["guest_counts"].items()) + ".")
    lines += ["", "Counts are per-invocation medians. Missing reports are shown as —, never zero.",
              "Largest four phase medians shown; JSON retains every phase and counter. "
              "Inclusive intervals overlap their children (core.native includes core.linker); do not add them.", "", *details,
              "", "Changed files from `git diff --name-only`:", ""]
    lines += ["- `" + p.replace("`", "\\`").replace("\n", "\\n") + "`" for p in report["git"]["changed_files"]] or ["- None."]
    lines += ["", "JSON associates changed files with each command and any reported source inventory. "
              "Native unit intervals and source ownership are retained when supplied by the compiler; "
              "legacy per-unit durations are unavailable. Reused units have no compile interval; "
              "parallel intervals overlap. Frontend per-unit durations are never estimated.",
              "Each case/repeat has private caches. Page/CPU caches are uncontrolled. "
              "Raw output, priming runs, commands, CPU state and distributions are retained in JSON/logs."]
    if report["options"]["stats"]:
        lines += ["", "Stats collection was enabled: it changes lowering and can add remark compilations. "
                  "Printed static stats and remark durations can themselves be replayed; they are not current-run phase costs."]
    if report.get("error"):
        lines += ["", "Failure: " + report["error"].replace("\n", " ")]
    return "\n".join(lines) + "\n"


def write_report(output, report):
    for case in report["cases"]:
        case["summary"] = summarize(case["samples"])
    for name, text in (("profile.json", json.dumps(report, indent=2) + "\n"),
                       ("summary.md", markdown(report))):
        temporary = output / (name + ".tmp")
        temporary.write_text(text)
        temporary.replace(output / name)


def run_matrix(args, report, output, window):
    for case in args.case or CASES:
        row = dict(name=case, cache_state=CASES[case], requested_repeats=args.repeats, samples=[])
        report["cases"].append(row)
        for repeat in range(args.repeats):
            window.check()
            directory = output / "cases" / case / f"{repeat + 1:03d}"
            environment, overrides = private_environment(directory, args.jobs)
            command = command_for(case, args, directory)
            sample = dict(repeat=repeat + 1, cache_directory=str(directory),
                          environment_overrides=overrides, cpu_before=host_state(),
                          priming=[], measured=None, commands=[])
            row["samples"].append(sample)
            print(f"{case} {repeat + 1}/{args.repeats}: {CASES[case]}", file=sys.stderr, flush=True)

            def invoke(label):
                return execute(command, root=args.repo, environment=environment, directory=directory,
                               label=label, timeout=args.timeout, case=case, records=sample["commands"])

            try:
                with unit_cache(args.repo, directory) if case == "zig-test-units" else nullcontext():
                    if CASES[case].startswith("primed"):
                        sample["priming"].append(invoke("prime"))
                    window.check()
                    if case == "zig-stdlib-touch":
                        with touch_stdlib(args.repo / args.touch_stdlib) as touched:
                            sample["touch"] = touched
                            sample["measured"] = invoke("measured")
                    else:
                        sample["measured"] = invoke("measured")
            finally:
                # Retain failed or interrupted commands even when invoke raises.
                sample["measured"] = next((r for r in sample["commands"] if r["role"] == "measured"), None)
                sample["cpu_after"] = host_state()
                telemetry = (sample["measured"] or {}).get("telemetry") or {}
                sample["source_context"] = source_context(args.repo, report["git"]["changed_files"], case, args, telemetry)
                write_report(output, report)


def positive_int(value):
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("must be positive")
    return number


def positive_seconds(value):
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError("must be finite and positive")
    return number


def arguments(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--compiler", type=Path, default=Path("zig-out/bin/selka"))
    parser.add_argument("--zig", default=os.environ.get("ZIG") or os.environ.get("SELKA_ZIG") or "zig")
    parser.add_argument("--entry", default="examples/testing/main.selka")
    parser.add_argument("--guest-entry", default="examples/testing/main.selka")
    parser.add_argument("--guest-filter", default="test_square")
    parser.add_argument("--zig-filter", default="build_identity: digests are deterministic and the two identities differ")
    parser.add_argument("--touch-stdlib", default="src/stdlib/math.selka")
    parser.add_argument("--diff-ref", default="HEAD", help="diff this commit against index + working tree")
    parser.add_argument("--output", type=Path, help="new directory for JSON, Markdown, logs and private caches")
    parser.add_argument("--repeats", type=positive_int, default=5)
    parser.add_argument("--jobs", type=positive_int, default=2)
    parser.add_argument("--timeout", type=positive_seconds, default=600, help="seconds per command, including priming")
    parser.add_argument("--window-seconds", type=positive_seconds, default=3600, help="total admitted execution bound")
    parser.add_argument("--case", action="append", choices=CASES)
    parser.add_argument("--stats", action="store_true", help="enable native --stats; changes lowering and adds remark work")
    parser.add_argument("--dry-run", action="store_true", help="print matrix only; no admission, compiler or touch")
    parser.add_argument("--self-test", action="store_true", help="run embedded parser/runner tests without builds or admission")
    args = parser.parse_args(argv)
    if args.self_test:
        return args
    args.repo = args.repo.resolve(strict=True)
    if not (args.repo / ".git").is_file():
        parser.error("use a dedicated linked worktree (git worktree add ... main)")
    if args.case and len(set(args.case)) != len(args.case):
        parser.error("each --case may be selected only once")
    for name in ("guest_filter", "zig_filter"):
        if not getattr(args, name).strip():
            parser.error("filters must be non-empty")
    for name in ("entry", "guest_entry", "touch_stdlib"):
        path = args.repo / getattr(args, name)
        resolved = path.resolve(strict=True)
        if not resolved.is_relative_to(args.repo) or not resolved.is_file():
            parser.error(name + " must be a file inside the worktree")
        setattr(args, name, str(resolved.relative_to(args.repo)))
    touch = Path(args.touch_stdlib)
    if not touch.is_relative_to("src/stdlib") or touch.is_relative_to("src/stdlib/fixtures"):
        parser.error("--touch-stdlib must name a non-fixture file under src/stdlib")
    args.compiler = (args.repo / args.compiler).resolve()
    args.zig = Path(shutil.which(args.zig) or args.zig).absolute()
    if not args.dry_run:
        if args.output is None:
            parser.error("--output is required")
        for path in (args.compiler, args.zig):
            if not path.is_file() or not os.access(path, os.X_OK):
                parser.error("prebuilt executable required: " + str(path))
        if "zig-test-units" in (args.case or CASES) and os.path.lexists(args.repo / ".selka-cache/unit-tests"):
            parser.error("use a dedicated worktree without an existing .selka-cache/unit-tests directory")
    return args


def main(argv=None):
    args = arguments(argv)
    if args.self_test:
        return self_test()
    if args.dry_run:
        output = (args.output or Path("/tmp/dev-loop-profile-NEW")).resolve()
        print(json.dumps([dict(case=case, cache_state=CASES[case], priming_runs=int(CASES[case].startswith("primed")),
                               command=command_for(case, args, output / "cases" / case / "001"))
                          for case in args.case or CASES], indent=2))
        return 0
    # Import lazily: dry runs and self-tests neither acquire admission nor launch tools.
    import verification_measurement as measurement
    output = args.output.resolve()
    state = git_state(args.repo, args.diff_ref)
    output.mkdir(parents=True, exist_ok=False)
    report = dict(version="dev-loop-profile-v1", status="running", captured_utc=datetime.now(timezone.utc).isoformat(),
                  repo=str(args.repo), git=state, compiler=dict(path=str(args.compiler), sha256=sha256(args.compiler)),
                  zig=dict(path=str(args.zig), sha256=sha256(args.zig.resolve())), host=host_state(),
                  options={k: str(v) if isinstance(v, Path) else v for k, v in vars(args).items()},
                  percentile_method="nearest-rank", cases=[])
    status = 0
    previous = signal.getsignal(signal.SIGTERM)
    def terminated(_number, _frame):
        raise KeyboardInterrupt("SIGTERM")
    signal.signal(signal.SIGTERM, terminated)
    try:
        print("Waiting for bounded timing admission; queue time is excluded.", file=sys.stderr, flush=True)
        with measurement.timing_window(args.window_seconds) as window:
            try:
                report["admitted_host"] = host_state()
                run_matrix(args, report, output, window)
                if sha256(args.compiler) != report["compiler"]["sha256"]:
                    raise RuntimeError("compiler binary changed during measurements")
                if git(args.repo, "rev-parse", "HEAD").strip() != state["commit"]:
                    raise RuntimeError("git commit changed during measurements")
                report["status"] = "complete"
            finally:
                report["admission"] = window.report()
    except (Exception, measurement.WindowExpired, KeyboardInterrupt) as error:
        report.update(status="failed", error=type(error).__name__ + ": " + str(error))
        status = (130 if isinstance(error, KeyboardInterrupt) else
                  124 if isinstance(error, (measurement.WindowExpired, subprocess.TimeoutExpired)) else 1)
    finally:
        signal.signal(signal.SIGTERM, previous)
        write_report(output, report)
    print(output / "profile.json")
    print(output / "summary.md")
    if status:
        print(report["error"], file=sys.stderr)
    return status


def self_test():
    """Small fixtures and real subprocesses; no compiler, gate or shared cache."""
    from contextlib import redirect_stderr
    import io
    import tempfile
    import unittest

    class Tests(unittest.TestCase):
        def test_percentiles(self):
            self.assertIsNone(distribution([]))
            self.assertEqual(distribution([9]), dict(count=1, median=9, p95=9, min=9, max=9))
            self.assertEqual(distribution(range(1, 21))["p95"], 19)

        def test_reports_and_nested_phases(self):
            cache = dict(version="cache-report-v1", program="linked", units=3, reused=2,
                         compiled=1, verified=0, processes=2,
                         stages=dict(version="stage-report-v3", nanoseconds=dict(frontend=42, native=180, linker=30,
                                     frontend_phases=[dict(name="syntax_parse", nanoseconds=10, inclusive=False)])))
            work = dict(version="work-report-v1", fingerprint_unchanged=True,
                        parsed_modules=dict(performed=1, reused=2), session=dict(parsed_modules=dict(performed=99, reused=99)))
            phase = dict(version="phase-timings-v1", kind="timing", name="total", duration_ns=300, inclusive=True)
            stats = "selka-core: inlined 3 calls, unswitched 1 loops, versioned 2 loops, proved 4 checks, vectorized 5 loops\n"
            data = parse_reports(json.dumps(cache), "warning: hello\n" + "\n".join(map(json.dumps, (cache, work, phase))) + "\n" + stats)
            self.assertEqual(data["unit_counts"]["compiled"], 1)
            self.assertEqual(data["work_counts"], {"parsed_modules": {"performed": 1, "reused": 2}})
            self.assertEqual(data["stats"]["vector_plans"], 5)
            self.assertTrue(next(p for p in data["phases"] if p["name"] == "core.native")["inclusive"])
            self.assertEqual(len(data["phases"]), 5)
            self.assertIsNone(parse_reports(json.dumps(cache), "")["unit_counts"])

        def test_native_unit_intervals_and_source_ownership(self):
            unit = dict(name="module-a", source_path="src/a.selka", kind="module", key="a" * 64,
                        action="compiled", compile_ns=42, scope="native-compile-process")
            row = dict(version="cache-report-v1", program="linked", units=2, reused=1,
                       compiled=1, verified=0, processes=2,
                       unit_timings=[unit, dict(unit, name="module-b", source_path="src/b.selka",
                                               action="reused", compile_ns=None)])
            data = parse_reports("", json.dumps(row))
            sample = dict(measured=dict(status="ok", wall_ns=100, telemetry=data))
            summary = summarize([sample, sample])
            self.assertEqual(len(summary["native_unit_compiles"]), 1)
            self.assertEqual(summary["native_unit_compiles"][0]["compile_ns"]["count"], 2)
            args = argparse.Namespace(entry="main.selka", touch_stdlib="stdlib.selka")
            context = source_context(Path("/repo"), ["src/a.selka"], "build", args, data)
            self.assertTrue(context["unit_to_source"][0]["changed"])
            self.assertIsNone(context["unit_to_source"][1]["compile_ns"])
            row["unit_timings"][1]["compile_ns"] = 0
            with self.assertRaises(ValueError):
                parse_reports("", json.dumps(row))

        def test_guest_and_text_reports(self):
            guest = dict(version="native-tests-v1", tests=[], passed=0, cached=2, failed=0, skipped=0, unsupported=0, sources=["a.selka"])
            data = parse_reports(json.dumps(guest, indent=2), "", guest=True)
            self.assertEqual(data["guest_counts"]["cached"], 2)
            self.assertIsNone(data["unit_counts"])
            text = "selka-core: cache: 3 units, 2 reused, 1 compiled, 0 verified; program reused; 2 processes; 1 shared mismatches\n"
            self.assertEqual(parse_reports("", text)["unit_counts"]["units"], 3)
            self.assertEqual(parse_reports("", "selka-core: cache: replayed the last identical build")["unit_counts"]["units"], 0)

        def test_malformed_and_absent(self):
            with self.assertRaises(ValueError):
                parse_reports("", '{"version":"cache-report-v1",broken}')
            with self.assertRaises(ValueError):
                parse_reports("", '{"version":"phase-timings-v1","kind":"timing","name":"bad","duration_ns":-1,"inclusive":false}')
            with self.assertRaises(ValueError):
                require_reports("run-cached", parse_reports("", ""))

        def test_subprocess_failure_and_timeout(self):
            with tempfile.TemporaryDirectory() as name:
                directory = Path(name)
                for code, timeout in (("raise SystemExit(7)", 5), ("import time; time.sleep(30)", .05)):
                    rows = []
                    with self.assertRaises((RuntimeError, subprocess.TimeoutExpired)):
                        execute([sys.executable, "-c", code], root=directory, environment=os.environ,
                                directory=directory, label="measured", timeout=timeout, case="zig-test-units", records=rows)
                    self.assertEqual(rows[0]["status"], "failed")
                    self.assertGreater(rows[0]["wall_ns"], 0)
                    self.assertIsNone(summarize([dict(measured=rows[0])])["wall_ns"])

        def test_private_stores_and_touch_rollback(self):
            with tempfile.TemporaryDirectory() as name:
                directory = Path(name)
                env, overrides = private_environment(directory / "one", 2)
                _, other = private_environment(directory / "two", 2)
                self.assertEqual(env["HOME"], os.environ["HOME"])
                self.assertEqual(env["SELKA_COMPILER_SHARED_CACHE"], "")
                self.assertNotEqual(overrides["ZIG_GLOBAL_CACHE_DIR"], other["ZIG_GLOBAL_CACHE_DIR"])
                source = directory / "math.selka"
                source.write_text("func main() -> int:\n    return 0\n")
                before = source.stat()
                with self.assertRaises(RuntimeError):
                    with touch_stdlib(source):
                        self.assertNotEqual(source.stat().st_mtime_ns, before.st_mtime_ns)
                        raise RuntimeError("build failed")
                self.assertEqual(source.stat().st_mtime_ns, before.st_mtime_ns)
                self.assertEqual(source.stat().st_atime_ns, before.st_atime_ns)
                self.assertEqual(source.read_text(), "func main() -> int:\n    return 0\n")

        def test_unit_cache_is_private_and_restored(self):
            with tempfile.TemporaryDirectory() as name:
                root = Path(name)
                directory = root / "case"
                directory.mkdir()
                link = root / ".selka-cache" / "unit-tests"
                with self.assertRaises(RuntimeError):
                    with unit_cache(root, directory):
                        self.assertEqual(link.resolve(), directory / "unit-tests")
                        (link / "marker").write_text("private")
                        raise RuntimeError("failed")
                self.assertFalse(link.exists())
                self.assertEqual((directory / "unit-tests/marker").read_text(), "private")
                link.mkdir()
                second = root / "second"
                second.mkdir()
                with self.assertRaises(FileExistsError):
                    with unit_cache(root, second):
                        self.fail("must not reuse an existing worktree cache")
                self.assertTrue(link.is_dir())

        def test_complete_matrix_with_fake_tools(self):
            # This exercises command construction, isolation, warm-up and report
            # publication together. It deliberately does not enter admission.
            fake = r'''
import json, os, pathlib, sys
args = sys.argv[1:]
cache = pathlib.Path(args[args.index('--cache-dir') + 1])
cache.mkdir(parents=True, exist_ok=True)
marker = cache / 'primed'
warm = marker.exists()
assert os.environ['SELKA_COMPILER_SHARED_CACHE'] == ''
assert os.environ['SELKA_TEST_SHARED_CACHE'] == ''
assert pathlib.Path(os.environ['ZIG_GLOBAL_CACHE_DIR']).parent == cache.parent
assert pathlib.Path(os.environ['SELKA_CORE_RUNTIME_CACHE']).parent == cache.parent
if '--no-cache' not in args:
    marker.touch()
if pathlib.Path(__file__).name == 'zig':
    assert args[0] == 'build'
    assert 'test' not in args
    assert '--prefix' in args and '--global-cache-dir' not in args
    if 'test-units' in args:
        assert any(a.startswith('-Dtest-filter=') for a in args)
        assert '-Dtest-rerun=true' in args
        assert pathlib.Path('.selka-cache/unit-tests').resolve() == cache.parent / 'unit-tests'
elif args[0] == 'check':
    print(json.dumps(dict(version='work-report-v1', parsed_modules=dict(performed=int(not warm), reused=int(warm)))), file=sys.stderr)
    print(json.dumps(dict(version='phase-timings-v1', kind='timing', name='total', duration_ns=40, inclusive=True)), file=sys.stderr)
elif args[0] == 'test':
    assert '--report' not in args and '--timings=json' not in args
    assert args[args.index('--filter') + 1] == 'test_square'
    print(json.dumps(dict(version='native-tests-v1', tests=[], passed=int(not warm), cached=int(warm), failed=0, skipped=0, unsupported=0, sources=['entry.selka'])))
else:
    assert '--timings=json' not in args and '--report' in args
    assert ('--run' in args) or ('-o' in args) or args[0] == 'run'
    print(json.dumps(dict(version='cache-report-v1', program='replayed' if warm else 'linked', units=0 if warm else 3, reused=0, compiled=0 if warm else 3, verified=0, processes=0 if warm else 4)), file=sys.stderr)
'''
            with tempfile.TemporaryDirectory() as name:
                root = Path(name)
                for tool in ("selka", "zig"):
                    path = root / tool
                    path.write_text("#!" + sys.executable + "\n" + fake)
                    path.chmod(0o700)
                source = root / "src/stdlib/math.selka"
                source.parent.mkdir(parents=True)
                source.write_text("func main() -> int:\n    return 0\n")
                before = source.stat().st_mtime_ns
                args = argparse.Namespace(repo=root, compiler=root / "selka", zig=root / "zig", entry="entry.selka",
                                          guest_entry="entry.selka", guest_filter="test_square", zig_filter="specific test",
                                          touch_stdlib="src/stdlib/math.selka", jobs=1, repeats=2, stats=False, timeout=5, case=None)
                report = dict(status="running", git=dict(commit="fixture", changed_files=["entry.selka", "src/project.zig"]),
                              compiler=dict(sha256="fixture"), options=dict(stats=False), cases=[])
                class Window:
                    def check(self):
                        pass
                output = root / "output"
                output.mkdir()
                with redirect_stderr(io.StringIO()):
                    run_matrix(args, report, output, Window())
                self.assertEqual(len(report["cases"]), 10)
                directories = set()
                for case in report["cases"]:
                    self.assertEqual(case["summary"]["successful_repeats"], 2)
                    for sample in case["samples"]:
                        self.assertNotIn(sample["cache_directory"], directories)
                        directories.add(sample["cache_directory"])
                        self.assertEqual(len(sample["priming"]), int(CASES[case["name"]].startswith("primed")))
                        self.assertIsNone(sample["source_context"]["unit_to_source"])
                by_name = {case["name"]: case for case in report["cases"]}
                self.assertEqual(by_name["run-uncached"]["summary"]["unit_counts"]["compiled"]["median"], 3)
                self.assertEqual(by_name["run-cached"]["summary"]["unit_counts"]["compiled"]["median"], 0)
                self.assertEqual(by_name["guest-cached"]["summary"]["guest_counts"]["cached"]["median"], 1)
                self.assertEqual(source.stat().st_mtime_ns, before)
                self.assertEqual(source.read_text(), "func main() -> int:\n    return 0\n")
                self.assertFalse((root / ".selka-cache/unit-tests").exists())
                self.assertEqual(json.loads((output / "profile.json").read_text())["cases"][0]["summary"]["successful_repeats"], 2)
                self.assertIn("per-unit durations are unavailable", (output / "summary.md").read_text())

    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Tests))
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print("dev-loop-profile: " + str(error), file=sys.stderr)
        sys.exit(2)

#!/usr/bin/env python3
"""Fresh same-host timing of prepared binaries; never writes historical evidence.

Build owns admission unless --admission=held names an enclosing build lease.
Run must be invoked inside one timing admission.
Manifests describe exact sources, outputs, worker counts and semantic changes.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import signal
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
UNSET = ("MYLANG_COUNTERS", "MYLANG_OPTIONS", "MYLANG_CORE_SANITIZE", "MYL_CORE_LEAKCHECK")


def digest(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def source_inputs(source):
    pending, seen = [source], {}
    while pending:
        path = pending.pop()
        if path.name in seen:
            continue
        seen[path.name] = digest(path)
        for module in re.findall(r"^import ([A-Za-z_]\w*)", path.read_text(), re.M):
            dependency = path.parent / (module + ".my")
            if dependency.exists():
                pending.append(dependency)
    return seen


def save(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    pending = path.with_suffix(path.suffix + ".tmp")
    pending.write_text(json.dumps(value, indent=2) + "\n")
    pending.replace(path)


def clean_env(extra=None):
    env = dict(os.environ)
    for key in UNSET:
        env.pop(key, None)
    env.update(extra or {})
    if any(key in env for key in ("MYLANG_COUNTERS", "MYLANG_CORE_SANITIZE", "MYL_CORE_LEAKCHECK")):
        raise ValueError("timing instrumentation requested")
    return env


def host():
    cpus = sorted(os.sched_getaffinity(0))
    cgroup = Path("/proc/self/cgroup").read_text()
    return {"platform": platform.platform(), "allowed_cpus": cpus,
            "cpuinfo": Path("/proc/cpuinfo").read_text(),
            "cgroup": cgroup, "boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
            "loadavg": Path("/proc/loadavg").read_text().strip()}


def run_once(argv, cwd, env, cpus, expected, timeout):
    # Files prevent pipe deadlocks. wait4 synchronizes this child, but its RSS
    # can include the Python launcher's pre-exec high-water mark: discard it.
    with tempfile.TemporaryFile() as stdout, tempfile.TemporaryFile() as stderr:
        start = time.perf_counter_ns()
        child = subprocess.Popen(["taskset", "-c", ",".join(map(str, cpus)), *argv],
                                 cwd=cwd, env=env, stdout=stdout, stderr=stderr,
                                 start_new_session=True)
        def expired(signum, frame):
            raise TimeoutError(argv)
        previous_handler = signal.signal(signal.SIGALRM, expired)
        signal.setitimer(signal.ITIMER_REAL, timeout)
        try:
            _, status, _ = os.wait4(child.pid, 0)
        except BaseException:
            os.killpg(child.pid, signal.SIGKILL)
            _, status, _ = os.wait4(child.pid, 0)
            child.returncode = os.waitstatus_to_exitcode(status)
            raise
        finally:
            signal.setitimer(signal.ITIMER_REAL, 0)
            signal.signal(signal.SIGALRM, previous_handler)
        elapsed = time.perf_counter_ns() - start
        child.returncode = os.waitstatus_to_exitcode(status)
        stdout.seek(0)
        stderr.seek(0)
        out, err = stdout.read(), stderr.read()
        row = {"wall_ns": elapsed,
               "status": child.returncode, "stdout_sha256": hashlib.sha256(out).hexdigest(),
               "stderr": err.decode(errors="replace")}
        if child.returncode or out != expected.encode() or err:
            raise RuntimeError({"argv": argv, "record": row, "stdout": out.decode(errors="replace")})
        return row


def run_rss_once(argv, cwd, env, cpus, expected, timeout):
    # GNU time execs with a fresh address space, then forks the measured guest.
    # Read its child's rusage, never the outer time/taskset process's wait4 RSS.
    with tempfile.TemporaryDirectory(prefix="mylang-guest-rss-") as directory:
        usage = Path(directory) / "usage.json"
        row = run_once(["/usr/bin/time", "-f", '{"maxrss_kib":%M}',
                        "-o", str(usage), "--", *argv], cwd, env, cpus,
                       expected, timeout)
        row.pop("wall_ns")  # This separate memory run is not runtime evidence.
        memory = json.loads(usage.read_text())
        if not isinstance(memory.get("maxrss_kib"), int) or memory["maxrss_kib"] < 0:
            raise ValueError("invalid GNU time guest RSS")
        return {**row, **memory}


def build(args):
    if args.admission == "held" and os.environ.get("MYLANG_ADMISSION_KIND") != "build":
        raise ValueError("--admission=held requires an enclosing build lease")
    if args.admission == "per-build" and os.environ.get("MYLANG_ADMISSION_KIND"):
        raise ValueError("do not nest admission; use --admission=held inside a build lease")
    manifest = json.loads(args.manifest.read_text())
    if (args.output / "builds.json").exists():
        raise ValueError("refusing to overwrite prepared artifact evidence")
    args.output.mkdir(parents=True, exist_ok=True)
    record = {"source_commit": args.commit, "compiler": str(args.compiler),
              "compiler_sha256": digest(args.compiler), "manifest_sha256": digest(args.manifest),
              "zig": str(args.zig), "zig_sha256": digest(args.zig),
              "ownership_selection": args.ownership, "admission": args.admission, "cases": []}
    prepared = {}
    reusable = []
    if args.reuse_builds:
        previous = json.loads(args.reuse_builds.read_text())
        if previous["compiler_sha256"] != record["compiler_sha256"]:
            raise ValueError("cannot reuse binaries generated by another compiler")
        reusable = previous["cases"]
        record["reuse_builds"] = str(args.reuse_builds)
    for case in manifest["cases"]:
        source = (args.source_root / case["source"]).resolve()
        target = args.output / case["id"]
        target.mkdir(parents=True, exist_ok=True)
        binary = target / "program"
        defaults = ["--experimental-zero-rc", "--release"] if args.ownership == "opt-in" else ["--release"]
        options = case.get("flags", defaults)
        if args.ownership == "default" and any(flag.startswith("--experimental-") for flag in options):
            raise ValueError("normal-default evidence cannot select an experimental ownership mode")
        if "--counters" in options:
            raise ValueError("counted binary cannot be used for timing")
        argv = [str(args.compiler), "build", str(source), *options, "--zig", str(args.zig),
                "--cache-dir", str(args.output / "cache"), "-o", str(binary)]
        key = (str(source), tuple(options))
        reused_build = key in prepared
        for prior in reusable:
            prior_inputs = prior.get("source_inputs_sha256", {Path(prior["source"]).name: prior["source_sha256"]})
            if (not prior.get("build_status", 0) and prior_inputs == source_inputs(source) and
                    prior.get("flags", ["--experimental-zero-rc", "--release"]) == options):
                if digest(prior["binary"]) != prior["binary_sha256"]:
                    raise ValueError("reusable binary changed")
                prepared[key] = Path(prior["binary"]), prior["build_command"], 0, prior.get("build_stderr", "previous build")
                reused_build = True
                break
        if key in prepared:
            binary, argv, status, stderr_path = prepared[key]
        else:
            command = argv if args.admission == "held" else [str(ROOT / "scripts/build-slot.sh"), "build", *argv]
            result = subprocess.run(command,
                                    cwd=ROOT, env=clean_env(), capture_output=True, text=True)
            (target / "build.stdout").write_text(result.stdout)
            (target / "build.stderr").write_text(result.stderr)
            status = result.returncode
            stderr_path = str(target / "build.stderr")
            if not status:
                symbols = subprocess.run(["nm", "-a", str(binary)], capture_output=True, text=True, check=True).stdout
                if "myl_count_current" in symbols or "myl_count_written" in symbols:
                    raise ValueError(f"{case['id']}: counting runtime found in timing binary")
            prepared[key] = binary, argv, status, stderr_path
        row = {**case, "flags": options, "source": str(source), "source_sha256": digest(source),
               "source_inputs_sha256": source_inputs(source),
               "build_command": argv, "build_status": status, "build_stderr": stderr_path,
               "artifact_preparation": "reused" if reused_build else "fresh"}
        if not status:
            row.update(binary=str(binary), binary_sha256=digest(binary),
                       instrumentation="absent; flags and nm checked")
        record["cases"].append(row)
        save(args.output / "builds.json", record)
        print(("reused" if reused_build else "built") if not status else "refused", case["id"], flush=True)
    if any(c["build_status"] for c in record["cases"]):
        raise SystemExit("one or more cases refused; retained in builds.json")


def run(args):
    if os.environ.get("MYLANG_ADMISSION_KIND") != "timing":
        raise ValueError("invoke run inside scripts/build-slot.sh timing")
    records = {arm: json.loads(getattr(args, arm).read_text()) for arm in ("before", "after")}
    cases = {arm: {c["id"]: c for c in data["cases"]} for arm, data in records.items()}
    if cases["before"].keys() != cases["after"].keys():
        raise ValueError("arms must have identical case IDs; keep refusals in separate census")
    for record in records.values():
        if digest(record["compiler"]) != record["compiler_sha256"]:
            raise ValueError("compiler changed since builds")
    memory_only = args.metric == "rss"
    harness_sha256 = digest(__file__)
    result = {"started_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
              "metric": args.metric,
              "method": ("3 alternating pairs; separate GNU time guest RSS runs" if memory_only else
                         "2 warmup pairs; 9 measured pairs; alternating before/after order; process wall time"),
              "wall_resolution_note": "monotonic perf_counter_ns around spawn and blocking wait4; medians below 100ms need a longer workload",
              "rss_note": "Separate RSS-only runs use GNU time's child rusage in KiB, including guest threads. Outer launcher RSS is discarded. Descendant peaks are not simultaneous process-tree RSS; no cgroup claim.",
              "managed_memory_note": "Separate counted executions measure managed traffic and live bytes; these are not RSS.",
              "host": host(), "builds": records, "cases": {}}
    if memory_only:
        result["memory_tool"] = {"path": "/usr/bin/time", "sha256": digest("/usr/bin/time")}
    if args.output.exists():
        previous = json.loads(args.output.read_text())
        if previous["builds"] != records or previous.get("metric") != args.metric:
            raise ValueError("refusing to append samples from different artifacts or measurement methods")
        result["cases"] = previous["cases"]
        result["previous_window_started_utc"] = previous["started_utc"]
    allowed = set(os.sched_getaffinity(0))
    selected = args.cases or list(cases["before"])
    if set(selected) - cases["before"].keys():
        raise ValueError("unknown case selection")
    for name in selected:
        if name in result["cases"]:
            raise ValueError(f"{name}: refusing to overwrite completed samples")
        first, second = cases["before"][name], cases["after"][name]
        if first.get("build_status", 0) or second.get("build_status", 0):
            result["cases"][name] = {"status": "not_comparable", "reason": "one or both compiler arms refused",
                                     "before_status": first.get("build_status", 0),
                                     "after_status": second.get("build_status", 0)}
            save(args.output, result)
            continue
        if first["expected"] != second["expected"]:
            raise ValueError(f"{name}: expected outputs differ")
        for field in ("args", "env"):
            default = [] if field == "args" else {}
            if first.get(field, default) != second.get(field, default):
                raise ValueError(f"{name}: paired {field} differ")
        cpus = first.get("cpus", [min(allowed)])
        other_cpus = second.get("cpus", [min(allowed)])
        if args.cpu is not None and len(cpus) == len(other_cpus) == 1:
            cpus = other_cpus = [args.cpu]
        if cpus != other_cpus or not set(cpus) <= allowed:
            raise ValueError(f"{name}: invalid or mismatched affinity")
        for case in (first, second):
            if digest(case["binary"]) != case["binary_sha256"]:
                raise ValueError(f"{name}: binary changed")
        window_started_utc = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        observations = {"before": [], "after": []}
        sample = run_rss_once if memory_only else run_once
        for pair in range(3 if memory_only else 11):
            for arm in (("before", "after") if pair % 2 == 0 else ("after", "before")):
                case = cases[arm][name]
                row = sample([case["binary"], *case.get("args", [])], case.get("cwd", str(ROOT)),
                             clean_env(case.get("env")), cpus, case["expected"], case.get("timeout_s", 120))
                observations[arm].append({"pair": pair, "warmup": not memory_only and pair < 2, **row})
        window = {"window_started_utc": window_started_utc,
                  "window_finished_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                  "measurement_harness_sha256": harness_sha256}
        summary = {}
        for arm in observations:
            measured = [r for r in observations[arm] if not r["warmup"]]
            for metric in (("maxrss_kib",) if memory_only else ("wall_ns",)):
                values = [r[metric] for r in measured]
                summary[f"{arm}_{metric}"] = {"median": statistics.median(values), "min": min(values), "max": max(values)}
        if memory_only:
            result["cases"][name] = {"cpus": cpus, "samples": observations, "summary": summary, **window}
            save(args.output, result)
            print(name, summary, flush=True)
            continue
        ratio = summary["after_wall_ns"]["median"] / summary["before_wall_ns"]["median"]
        summary["candidate_baseline_wall_ratio"] = ratio
        paired = [a["wall_ns"] / b["wall_ns"] for a, b in
                  zip(observations["after"][2:], observations["before"][2:])]
        summary["paired_candidate_baseline_ratios"] = paired
        summary["paired_ratio_range"] = [min(paired), max(paired)]
        summary["paired_ratio_median"] = statistics.median(paired)
        summary["noisy_ranges"] = any(summary[f"{arm}_wall_ns"]["max"] /
                                      summary[f"{arm}_wall_ns"]["min"] > 1.20 for arm in observations)
        summary["comparison_scope"] = ("same guest source; compiler/runtime/library comparison" if
                                       first.get("source_inputs_sha256", {Path(first["source"]).name: first["source_sha256"]}) ==
                                       second.get("source_inputs_sha256", {Path(second["source"]).name: second["source_sha256"]}) else
                                       "compiler and source migration; not a compiler-only comparison")
        summary["slowdown_review_trigger"] = ratio > 1.05
        summary["tiny_workload"] = min(summary[f"{arm}_wall_ns"]["median"] for arm in observations) < 100_000_000
        result["cases"][name] = {"cpus": cpus, "samples": observations, "summary": summary, **window}
        save(args.output, result)
        print(name, summary, flush=True)
    result["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    save(args.output, result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    b = sub.add_parser("build")
    b.add_argument("--manifest", type=Path, required=True)
    b.add_argument("--source-root", type=lambda p: Path(p).resolve(), default=ROOT)
    b.add_argument("--reuse-builds", type=Path, help="reuse exact compiler/source/option binary identities for revised runtime arguments")
    b.add_argument("--compiler", type=lambda p: Path(p).resolve(), required=True)
    b.add_argument("--zig", type=lambda p: Path(p).resolve(), required=True)
    b.add_argument("--commit", required=True)
    b.add_argument("--ownership", choices=("opt-in", "default"), default="opt-in",
                   help="opt-in for C0/C1; default for actual C2/C3 ordinary commands")
    b.add_argument("--admission", choices=("per-build", "held"), default="per-build",
                   help="held permits bounded preparation under one existing build lease")
    b.add_argument("--output", type=lambda p: Path(p).resolve(), required=True)
    b.set_defaults(handler=build)
    r = sub.add_parser("run")
    r.add_argument("--before", type=Path, required=True)
    r.add_argument("--after", type=Path, required=True)
    r.add_argument("--output", type=Path, required=True)
    r.add_argument("--cases", nargs="+")
    r.add_argument("--metric", choices=("runtime", "rss"), default="runtime")
    r.add_argument("--cpu", type=int, help="override both arms' serial affinity after checking allowed topology")
    r.set_defaults(handler=run)
    args = parser.parse_args()
    args.handler(args)


if __name__ == "__main__":
    main()

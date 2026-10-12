#!/usr/bin/env python3
"""Fresh same-host timing of prepared binaries; never writes historical evidence.

Build owns build admission. Run must be invoked inside one timing admission.
Manifests describe exact sources, outputs, worker counts and semantic changes.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import signal
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
UNSET = ("MYLANG_COUNTERS", "MYLANG_OPTIONS", "MYLANG_CORE_SANITIZE", "MYL_CORE_LEAKCHECK")


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


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
    # Files prevent pipe deadlocks and allow wait4 to return this exact child's
    # usage rather than resource.getrusage's cumulative high-water mark.
    with tempfile.TemporaryFile() as stdout, tempfile.TemporaryFile() as stderr:
        start = time.perf_counter_ns()
        child = subprocess.Popen(["taskset", "-c", ",".join(map(str, cpus)), *argv],
                                 cwd=cwd, env=env, stdout=stdout, stderr=stderr)
        def expired(signum, frame):
            raise TimeoutError(argv)
        previous_handler = signal.signal(signal.SIGALRM, expired)
        signal.setitimer(signal.ITIMER_REAL, timeout)
        try:
            _, status, usage = os.wait4(child.pid, 0)
        except BaseException:
            child.kill()
            _, status, usage = os.wait4(child.pid, 0)
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
        row = {"wall_ns": elapsed, "maxrss_kib": usage.ru_maxrss,
               "user_s": usage.ru_utime, "system_s": usage.ru_stime,
               "status": child.returncode, "stdout_sha256": hashlib.sha256(out).hexdigest(),
               "stderr": err.decode(errors="replace")}
        if child.returncode or out != expected.encode() or err:
            raise RuntimeError({"argv": argv, "record": row, "stdout": out.decode(errors="replace")})
        return row


def build(args):
    manifest = json.loads(args.manifest.read_text())
    args.output.mkdir(parents=True, exist_ok=True)
    record = {"source_commit": args.commit, "compiler": str(args.compiler),
              "compiler_sha256": digest(args.compiler), "manifest_sha256": digest(args.manifest),
              "zig": str(args.zig), "zig_sha256": digest(args.zig), "cases": []}
    prepared = {}
    for case in manifest["cases"]:
        source = (ROOT / case["source"]).resolve()
        target = args.output / case["id"]
        target.mkdir(parents=True, exist_ok=True)
        binary = target / "program"
        options = case.get("flags", ["--experimental-zero-rc", "--release"])
        if "--counters" in options:
            raise ValueError("counted binary cannot be used for timing")
        argv = [str(args.compiler), "build", str(source), *options, "--zig", str(args.zig),
                "--cache-dir", str(args.output / "cache"), "-o", str(binary)]
        key = (str(source), tuple(options))
        if key in prepared:
            binary, argv = prepared[key]
        else:
            result = subprocess.run([str(ROOT / "scripts/build-slot.sh"), "build", *argv],
                                    cwd=ROOT, env=clean_env(), capture_output=True, text=True)
            (target / "build.stdout").write_text(result.stdout)
            (target / "build.stderr").write_text(result.stderr)
            if result.returncode:
                raise RuntimeError(f"{case['id']} failed: {result.stderr}")
            symbols = subprocess.run(["nm", "-a", str(binary)], capture_output=True, text=True, check=True).stdout
            if "myl_count_current" in symbols or "myl_count_written" in symbols:
                raise ValueError(f"{case['id']}: counting runtime found in timing binary")
            prepared[key] = binary, argv
        record["cases"].append({**case, "source": str(source), "source_sha256": digest(source),
                                "binary": str(binary), "binary_sha256": digest(binary),
                                "build_command": argv, "instrumentation": "absent; flags and nm checked"})
        save(args.output / "builds.json", record)
        print("built", case["id"], flush=True)


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
    result = {"started_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
              "method": "2 warmup pairs; 9 measured pairs; alternating before/after order; process wall time",
              "wall_resolution_note": "monotonic perf_counter_ns around spawn and blocking wait4; medians below 100ms need a longer workload",
              "rss_note": "Linux wait4 ru_maxrss KiB for each guest; includes its threads. Child process peaks are not simultaneous process-tree RSS. No process-tree or cgroup RSS claim.",
              "managed_memory_note": "Separate counted executions measure managed traffic and live bytes; these are not RSS.",
              "host": host(), "builds": records, "cases": {}}
    if args.output.exists():
        previous = json.loads(args.output.read_text())
        if previous["builds"] != records:
            raise ValueError("refusing to append samples from different artifacts")
        result["cases"] = previous["cases"]
        result["previous_window_started_utc"] = previous["started_utc"]
    allowed = set(os.sched_getaffinity(0))
    selected = args.cases or list(cases["before"])
    if set(selected) - cases["before"].keys():
        raise ValueError("unknown case selection")
    for name in selected:
        first, second = cases["before"][name], cases["after"][name]
        if first["expected"] != second["expected"]:
            raise ValueError(f"{name}: expected outputs differ")
        cpus = first.get("cpus", [min(allowed)])
        other_cpus = second.get("cpus", [min(allowed)])
        if args.cpu is not None and len(cpus) == len(other_cpus) == 1:
            cpus = other_cpus = [args.cpu]
        if cpus != other_cpus or not set(cpus) <= allowed:
            raise ValueError(f"{name}: invalid or mismatched affinity")
        for case in (first, second):
            if digest(case["binary"]) != case["binary_sha256"]:
                raise ValueError(f"{name}: binary changed")
        observations = {"before": [], "after": []}
        for pair in range(11):
            for arm in (("before", "after") if pair % 2 == 0 else ("after", "before")):
                case = cases[arm][name]
                row = run_once([case["binary"], *case.get("args", [])], case.get("cwd", str(ROOT)),
                               clean_env(case.get("env")), cpus, case["expected"], case.get("timeout_s", 120))
                observations[arm].append({"pair": pair, "warmup": pair < 2, **row})
        summary = {}
        for arm in observations:
            measured = [r for r in observations[arm] if not r["warmup"]]
            for metric in ("wall_ns", "maxrss_kib"):
                values = [r[metric] for r in measured]
                summary[f"{arm}_{metric}"] = {"median": statistics.median(values), "min": min(values), "max": max(values)}
        ratio = summary["after_wall_ns"]["median"] / summary["before_wall_ns"]["median"]
        summary["candidate_baseline_wall_ratio"] = ratio
        paired = [a["wall_ns"] / b["wall_ns"] for a, b in
                  zip(observations["after"][2:], observations["before"][2:])]
        summary["paired_candidate_baseline_ratios"] = paired
        summary["paired_ratio_range"] = [min(paired), max(paired)]
        summary["paired_ratio_median"] = statistics.median(paired)
        summary["noisy_ranges"] = any(summary[f"{arm}_wall_ns"]["max"] /
                                      summary[f"{arm}_wall_ns"]["min"] > 1.20 for arm in observations)
        summary["comparison_scope"] = ("same-source compiler comparison" if
                                       first["source_sha256"] == second["source_sha256"] else
                                       "compiler and source migration; not a compiler-only comparison")
        summary["slowdown_review_trigger"] = ratio > 1.05
        summary["tiny_workload"] = min(summary[f"{arm}_wall_ns"]["median"] for arm in observations) < 100_000_000
        result["cases"][name] = {"cpus": cpus, "samples": observations, "summary": summary}
        save(args.output, result)
        print(name, summary, flush=True)
    result["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    save(args.output, result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    b = sub.add_parser("build")
    b.add_argument("--manifest", type=Path, required=True)
    b.add_argument("--compiler", type=lambda p: Path(p).resolve(), required=True)
    b.add_argument("--zig", type=lambda p: Path(p).resolve(), required=True)
    b.add_argument("--commit", required=True)
    b.add_argument("--output", type=lambda p: Path(p).resolve(), required=True)
    b.set_defaults(handler=build)
    r = sub.add_parser("run")
    r.add_argument("--before", type=Path, required=True)
    r.add_argument("--after", type=Path, required=True)
    r.add_argument("--output", type=Path, required=True)
    r.add_argument("--cases", nargs="+")
    r.add_argument("--cpu", type=int, help="override both arms' serial affinity after checking allowed topology")
    r.set_defaults(handler=run)
    args = parser.parse_args()
    args.handler(args)


if __name__ == "__main__":
    main()

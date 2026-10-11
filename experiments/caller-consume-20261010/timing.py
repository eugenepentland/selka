#!/usr/bin/env python3
"""Short interleaved ordinary-binary timings, separate from memory counters."""
import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import time


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def cpu_ticks(cpus):
    result = {}
    for line in Path("/proc/stat").read_text().splitlines():
        fields = line.split()
        if fields and fields[0] in {f"cpu{cpu}" for cpu in cpus}:
            values = list(map(int, fields[1:]))
            result[fields[0]] = (sum(values[:8]), values[3] + values[4])
    return result


def cpu_activity(cpu):
    siblings = Path(f"/sys/devices/system/cpu/cpu{cpu}/topology/thread_siblings_list").read_text().strip()
    cpus = []
    for part in siblings.split(","):
        first, _, last = part.partition("-")
        cpus.extend(range(int(first), int(last or first) + 1))
    before = cpu_ticks(cpus)
    time.sleep(1)
    after = cpu_ticks(cpus)
    busy = {}
    for name, (total, idle) in before.items():
        elapsed = after[name][0] - total
        busy[name] = 1 - (after[name][1] - idle) / elapsed if elapsed else 0
    return busy


def run(binary, case, cpu, env):
    argv = ["taskset", "-c", str(cpu), binary] + case["argv"]
    started = time.perf_counter_ns()
    completed = subprocess.run(argv, env=env, capture_output=True, timeout=120)
    elapsed = time.perf_counter_ns() - started
    if completed.returncode or completed.stdout.decode() != case["stdout"] or completed.stderr:
        raise ValueError(f"timing output mismatch: {argv}: {completed}")
    return {"elapsed_ns": elapsed, "stdout": completed.stdout.decode(), "status": completed.returncode,
            "argv": argv}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cpu", type=int, default=10)
    parser.add_argument("--pairs", type=int, default=9)
    args = parser.parse_args()
    if args.pairs < 3 or args.cpu not in os.sched_getaffinity(0):
        raise ValueError("need at least three pairs and an allowed CPU")
    arms = {"baseline": json.loads(args.baseline.read_text()),
            "candidate": json.loads(args.candidate.read_text())}
    for arm in arms.values():
        if arm["failures"] or arm.get("qualified_executions") != 230:
            raise ValueError("correctness capture must finish before timing")
    lock_path = Path.home() / ".cache/mylang/runtime-parity-timing.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env.pop("MYLANG_COUNTERS", None)
    env.pop("MYL_CORE_LEAKCHECK", None)
    result = {"kind": "exploratory ordinary-process timings", "cpu": args.cpu, "pairs": args.pairs,
              "warmups_per_arm": 2, "started_utc": datetime.now(timezone.utc).isoformat(),
              "script_sha256": sha(__file__), "capture_sha256": {
                  "baseline": sha(args.baseline), "candidate": sha(args.candidate)},
              "limitations": ["Process launch and startup are included.",
                  "Shared host activity may affect frequency, cache and memory bandwidth.",
                  "These two targeted workloads do not establish a broad application speedup."],
              "cases": {}}
    with lock_path.open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("Timing lock is occupied; no timings collected.")
            return 2
        result["load_average_before"] = os.getloadavg()
        for target, rounds in (("constructor", 1000000), ("replacement", 8000)):
            for mode in ("replace", "snapshot"):
                name = f"{target}/{mode}-{rounds}"
                cases = {label: next(case for case in arm["targets"][target]["cases"]
                                    if case["id"] == f"{mode}-{rounds}") for label, arm in arms.items()}
                if cases["baseline"] != cases["candidate"]:
                    raise ValueError("timing input/oracle mismatch")
                binaries = {label: arm["targets"][target]["binaries"]["plain"] for label, arm in arms.items()}
                for binary in binaries.values():
                    if sha(binary["path"]) != binary["sha256"]:
                        raise ValueError("ordinary binary changed")
                record = {"binaries": binaries, "input": cases["baseline"],
                          "cpu_busy_before": cpu_activity(args.cpu), "warmups": [], "samples": []}
                for warmup in range(2):
                    for label in ("baseline", "candidate"):
                        record["warmups"].append(dict(run(binaries[label]["path"], cases[label], args.cpu, env),
                                                      arm=label, round=warmup))
                for pair in range(args.pairs):
                    order = ("baseline", "candidate") if pair % 2 == 0 else ("candidate", "baseline")
                    for label in order:
                        record["samples"].append(dict(run(binaries[label]["path"], cases[label], args.cpu, env),
                                                      arm=label, pair=pair))
                record["summary"] = {}
                for label in arms:
                    values = [sample["elapsed_ns"] for sample in record["samples"] if sample["arm"] == label]
                    median = statistics.median(values)
                    record["summary"][label] = {"median_ms": median / 1e6,
                        "median_absolute_deviation_pct": statistics.median(abs(v - median) for v in values) / median * 100,
                        "min_ms": min(values) / 1e6, "max_ms": max(values) / 1e6}
                result["cases"][name] = record
                args.output.write_text(json.dumps(result, indent=2) + "\n")
                print(f"Timed {name}", flush=True)
        result["load_average_after"] = os.getloadavg()
        result["finished_utc"] = datetime.now(timezone.utc).isoformat()
        result["complete"] = True
        args.output.write_text(json.dumps(result, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Interleaved wall-clock and hardware-counter comparison of the backend arms.

    measure.py --work DIR [--rounds N] [--input DIR] [--json OUT] [--arms ...]

Builds every arm of the benchmark — QBE, LLVM at each optimization level, and the
frozen Zig ReleaseFast reference — then times them against each other in one
randomly ordered batch per round, with the parent and children pinned to one
logical CPU.  Nothing is compared across batches: each reported ratio comes from
the same round set as the numbers beside it.

Reported per arm and workload: median wall time, the interquartile range, and a
bootstrap interval for the ratio against the QBE arm that resamples *rounds*
rather than individual samples, so the batch structure survives.

Outputs are verified on every captured run. With --sink=null, verification runs
before and after the timed batch; timed executions still check status/stderr.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import random
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
MYLANG = REPO / "zig-out" / "bin" / "mylang"
ADAPTER = HERE / "qbe_llvm.py"
PORT = REPO / "experiments" / "sexpr-port" / "main.my"
ZIG_BENCH = Path("/tmp/zb-out/bin/zig-bench")

#: workload -> (input file name, guest arguments, Zig reference arguments).
WORKLOADS = {
    "census": ("input.sexp", [], []),
    "render": ("input.sexp", ["--render"], ["--render"]),
    "census-7.4MB": ("input8.sexp", [], []),
    "render-7.4MB": ("input8.sexp", ["--render"], ["--render"]),
}

#: arm -> (compiler tool, optimization level passed to that tool, cache suffix).
ARMS = {
    "qbe": (None, None, "qbe"),
    "llvm-o2": (str(ADAPTER), "-O2", "llvm-o2"),
    "llvm-o3": (str(ADAPTER), "-O3", "llvm-o3"),
}

#: The counter set one matched round samples.  Instruction and cycle counts are
#: user-space and INCLUDE the runtime and C libraries. `task-clock` includes both
#: user and kernel CPU time. Neither counter set includes the Python parent's work.
#: Event name -> the label used in the report.  `perf` rewrites `x:u` to `x/u`
#: when it prints a hybrid CPU's per-core event, so both spellings are matched.
COUNTERS = {"task-clock": "task-clock", "instructions:u": "instructions",
            "cycles:u": "cycles", "branches:u": "branches",
            "branch-misses:u": "branch-misses"}

#: The `perf stat -e` argument list, built from the keys above.
EVENTS = tuple(COUNTERS)

#: Wall time and counters are sampled in *separate* matched batches.  `perf stat`
#: perturbs a short run badly enough to double it (measured: the 927 KB census at
#: 9.7 ms free and 23.5 ms under `perf stat`), so a wall-clock ratio taken from a
#: counter batch would be wrong by however much that wrapper costs.


def sha256(path):
    """The digest of one file."""
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def build_arm(name, tool, level, work, input_dir):
    """Build one arm of the port, returning its path or None on failure."""
    output = work / f"{name}"
    # The native driver's executable stamp does not include imported Python files
    # or environment flags. Include the whole adapter recipe in this cache path.
    fingerprint = hashlib.sha256((level or "qbe").encode())
    if tool is not None:
        for path in sorted(HERE.glob("*.py")):
            fingerprint.update(path.name.encode())
            fingerprint.update(path.read_bytes())
    cache = work / f"cache-{name}-{fingerprint.hexdigest()[:16]}"
    command = [str(MYLANG), "build", str(PORT), "-o", str(output),
               f"--cache-dir={cache}", "--mode=ReleaseFast", "--keep-symbols"]
    if tool is not None:
        command.append(f"--qbe={tool}")
    environment = dict(os.environ)
    if level is not None:
        environment["MYLANG_QBE_LLVM_OPT"] = level
    done = subprocess.run(command, capture_output=True, text=True, env=environment)
    if done.returncode != 0:
        print(f"{name}: BUILD FAILED\n{done.stderr[-1500:]}")
        return None
    return output


def build_zig():
    """Build the frozen Zig ReleaseFast reference if it is not already present."""
    if ZIG_BENCH.exists():
        return ZIG_BENCH
    source = REPO / "experiments" / "sexpr-port" / "zig-bench"
    environment = dict(os.environ)
    environment["ZIG_LOCAL_CACHE_DIR"] = "/tmp/zb-cache"
    environment["ZIG_GLOBAL_CACHE_DIR"] = "/tmp/zb-global"
    done = subprocess.run(["zig", "build", "-Doptimize=ReleaseFast", "-p", "/tmp/zb-out"],
                          cwd=source, capture_output=True, text=True, env=environment)
    if done.returncode != 0:
        print(f"zig-bench: BUILD FAILED\n{done.stderr[-1000:]}")
        return None
    return ZIG_BENCH if ZIG_BENCH.exists() else None


def command_for(arm, workload, binaries, input_dir, zig):
    """The full command line for one arm and workload."""
    fixture, guest_arguments, zig_arguments = WORKLOADS[workload]
    path = input_dir / fixture
    if arm == "zig":
        # zig-bench takes the fixture first and its mode afterwards:
        # `zig-bench <input.sexp> --render`.
        return [str(zig), str(path), *zig_arguments]
    return [str(binaries[arm]), str(path), *guest_arguments]


def counters_from(stderr):
    """The counter values in one `perf stat -x,` report."""
    found = {}
    for line in stderr.splitlines():
        fields = line.split(",")
        if len(fields) < 3:
            continue
        value = fields[0].strip()
        if not value or not value.replace(".", "", 1).isdigit():
            continue
        # `perf stat -x,` puts the event name in the third field.  A hybrid CPU
        # reports each event once per core type (`cpu_atom/instructions/u` and
        # `cpu_core/instructions/u`), and a process pinned to one physical core
        # only ever runs on one of them, so the larger of the two is that core's
        # count and the other is a zero sample.
        event = fields[2].strip()
        for key, label in COUNTERS.items():
            head, _, tail = key.partition(":")
            # `instructions:u` is printed as `cpu_core/instructions/u`: the colon
            # becomes a slash and the core type is prefixed.  Compare the tail.
            if event == key or event == f"{head}/{tail}" or \
                    event.endswith(f"/{head}/{tail}"):
                found[label] = max(found.get(label, 0.0), float(value))
    return found


def median(values):
    """The median of a sample list."""
    return statistics.median(values) if values else float("nan")


def spread(values):
    """The interquartile range of a sample list."""
    if len(values) < 4:
        return float("nan")
    ordered = sorted(values)
    low = statistics.quantiles(ordered, n=4)[0]
    high = statistics.quantiles(ordered, n=4)[2]
    return high - low


def bootstrap_ratio(numerator, denominator, rounds=2000, seed=7):
    """A resampled interval for median(numerator)/median(denominator).

    Rounds are resampled as units, so the pairing inside one interleaved batch is
    preserved instead of being shuffled away.
    """
    if len(numerator) != len(denominator) or len(numerator) < 3:
        return (float("nan"), float("nan"))
    rng = random.Random(seed)
    count = len(numerator)
    ratios = []
    for _ in range(rounds):
        picks = [rng.randrange(count) for _ in range(count)]
        top = median([numerator[index] for index in picks])
        bottom = median([denominator[index] for index in picks])
        if bottom:
            ratios.append(top / bottom)
    if not ratios:
        return (float("nan"), float("nan"))
    ratios.sort()
    return (ratios[int(0.025 * len(ratios))], ratios[int(0.975 * len(ratios))])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", default="/tmp/llvm-backend-measure")
    parser.add_argument("--input", default="/tmp/rt2x")
    parser.add_argument("--rounds", type=int, default=31)
    parser.add_argument("--cpu", type=int, default=6)
    parser.add_argument("--json", dest="out")
    parser.add_argument("--no-counters", action="store_true")
    parser.add_argument("--skip-zig", action="store_true")
    parser.add_argument("--arms", help="comma-separated arm subset to build and time")
    parser.add_argument("--binary", action="append", default=[], metavar="NAME=PATH",
                        help="use a prebuilt arm (repeatable); with no --arms, time only these")
    parser.add_argument("--reference", default="qbe", help="numerator for ratios")
    parser.add_argument("--sink", choices=("capture", "null"), default="capture",
                        help="capture bytes, or redirect timed stdout to /dev/null")
    parser.add_argument("--warmups", type=int, default=2)
    options = parser.parse_args()
    if options.rounds < 3 or options.warmups < 0:
        parser.error("--rounds must be at least 3 and --warmups nonnegative")
    prebuilt = {}
    for item in options.binary:
        name, separator, path = item.partition("=")
        if not separator or not name or name in prebuilt or not Path(path).is_file():
            parser.error(f"invalid or duplicate --binary {item!r}")
        prebuilt[name] = Path(path).resolve()

    input_dir = Path(options.input)
    for name in ("input.sexp", "input8.sexp"):
        if not (input_dir / name).exists():
            fallback = REPO / ".tmp" / "runtime-audit-20260919" / name
            if fallback.exists():
                input_dir = fallback.parent
                break
            raise SystemExit(f"missing fixture {name} in {input_dir}")
    work = Path(options.work)
    work.mkdir(parents=True, exist_ok=True)

    report = {"work": str(work), "cpu": options.cpu, "rounds": options.rounds,
              "input_dir": str(input_dir), "arms": {}, "workloads": {},
              "inputs": {}, "counters": list(EVENTS), "sink": options.sink,
              "reference": options.reference, "warmups": options.warmups,
              "wall_round_order": [], "counter_round_order": [],
              "toolchain": {"compiler_sha256": sha256(MYLANG),
                            "adapter_sources": {p.name: sha256(p) for p in sorted(HERE.glob('*.py'))},
                            "zig": subprocess.check_output(['zig', 'version'], text=True).strip()},
              "timing_scope": "process launch through completion; stdout bytes captured" if options.sink == "capture"
                              else "process launch through completion; timed stdout redirected to /dev/null"}
    for name in ("input.sexp", "input8.sexp"):
        report["inputs"][name] = {"bytes": (input_dir / name).stat().st_size,
                                  "sha256": sha256(input_dir / name)}

    wanted = set(options.arms.split(",")) if options.arms else (set(prebuilt) if prebuilt else None)
    if wanted is not None and wanted - set(ARMS) - set(prebuilt) - {"zig"}:
        parser.error("--arms contains an unknown arm")
    binaries = {name: path for name, path in prebuilt.items() if wanted is None or name in wanted}
    for arm, (tool, level, _suffix) in ARMS.items():
        if arm in binaries or (wanted is not None and arm not in wanted):
            continue
        built = build_arm(arm, tool, level, work, input_dir)
        if built is None:
            raise SystemExit(f"arm {arm} did not build")
        binaries[arm] = built
    zig = binaries.get("zig")
    if zig is None and not options.skip_zig and (wanted is None or "zig" in wanted):
        zig = build_zig()
    if zig is not None:
        binaries["zig"] = zig
    report["arms"] = {arm: {"path": str(path), "sha256": sha256(path)}
                      for arm, path in binaries.items()}
    if options.reference not in binaries:
        parser.error(f"reference arm {options.reference!r} is absent")
    for arm, path in binaries.items():
        receipt = Path(str(path) + '.qbe-manifest.json')
        if receipt.exists():
            data = json.loads(receipt.read_text())
            runtime = Path(data['runtime_object'])
            report['arms'][arm]['runtime'] = {'path': str(runtime), 'sha256': sha256(runtime)}

    if options.cpu is not None:
        os.sched_setaffinity(0, {options.cpu})

    # Verify every arm's output once, before any timing: a workload whose stdout
    # differs between arms is a hard error, not a data point.
    expected = {}
    for workload in WORKLOADS:
        reference = None
        for arm in binaries:
            command = command_for(arm, workload, binaries, input_dir, zig)
            run = subprocess.run(command, capture_output=True)
            if run.returncode != 0 or run.stderr:
                raise SystemExit(f"{arm} failed on {workload}: status={run.returncode}, {run.stderr[-200:]!r}")
            if reference is None:
                reference = run.stdout
            elif run.stdout != reference:
                raise SystemExit(f"{arm} disagrees with the first arm on {workload}")
            for _ in range(options.warmups):
                warm = subprocess.run(command, capture_output=True)
                if warm.returncode != 0 or warm.stderr or warm.stdout != reference:
                    raise SystemExit(f"warmup differs: {command}")
        expected[workload] = reference
        report["workloads"][workload] = {
            "stdout_bytes": len(reference),
            "stdout_sha256": hashlib.sha256(reference).hexdigest()}

    samples = {(workload, arm): {"wall": [], "counters": {}, "perf_raw": []}
               for workload in WORKLOADS for arm in binaries}
    rng = random.Random(20260919)
    for round_index in range(options.rounds):
        order = [(workload, arm) for workload in WORKLOADS for arm in binaries]
        rng.shuffle(order)
        report['wall_round_order'].append(order)
        for workload, arm in order:
            command = command_for(arm, workload, binaries, input_dir, zig)
            start = time.perf_counter_ns()
            run = subprocess.run(command, stdout=subprocess.PIPE if options.sink == "capture" else subprocess.DEVNULL,
                                 stderr=subprocess.PIPE)
            wall = (time.perf_counter_ns() - start) / 1e6
            if run.returncode != 0 or run.stderr or (options.sink == 'capture' and run.stdout != expected[workload]):
                raise SystemExit(f"status/stderr/output changed: {command}: {run.returncode}, {run.stderr[-200:]!r}")
            samples[(workload, arm)]["wall"].append(wall)
        if (round_index + 1) % 5 == 0:
            print(f"  wall {round_index + 1}/{options.rounds}", flush=True)

    if not options.no_counters:
        for round_index in range(max(3, options.rounds // 3)):
            order = [(workload, arm) for workload in WORKLOADS for arm in binaries]
            rng.shuffle(order)
            report['counter_round_order'].append(order)
            for workload, arm in order:
                command = command_for(arm, workload, binaries, input_dir, zig)
                run = subprocess.run(["perf", "stat", "-x,", "-e", ",".join(EVENTS),
                                      "--", *command], capture_output=True)
                if run.returncode != 0 or run.stdout != expected[workload]:
                    raise SystemExit(f"output changed: {command}")
                stderr = run.stderr.decode('utf8', 'replace')
                values = counters_from(stderr)
                if not {'instructions', 'cycles'}.issubset(values):
                    raise SystemExit(f"no counters for {command}: {run.stderr[-300:]}")
                samples[(workload, arm)]['perf_raw'].append(stderr)
                for name, value in values.items():
                    samples[(workload, arm)]["counters"].setdefault(name, []).append(value)
            if (round_index + 1) % 3 == 0:
                print(f"  counters {round_index + 1}/"
                      f"{max(3, options.rounds // 3)}", flush=True)

    # Especially important for --sink=null, whose timed stdout is not captured.
    for workload in WORKLOADS:
        for arm in binaries:
            command = command_for(arm, workload, binaries, input_dir, zig)
            run = subprocess.run(command, capture_output=True)
            if run.returncode != 0 or run.stderr or run.stdout != expected[workload]:
                raise SystemExit(f"post-batch verification failed: {command}")

    for workload in WORKLOADS:
        entry = {"arms": {}, "ratios": {}}
        for arm in binaries:
            bucket = samples[(workload, arm)]
            entry["arms"][arm] = {
                "wall_ms_median": median(bucket["wall"]),
                "wall_ms_iqr": spread(bucket["wall"]),
                "wall_ms_min": min(bucket["wall"]),
                "wall_samples": len(bucket["wall"]),
                "wall_ms": bucket['wall'],
                "counter_samples": bucket['counters'],
                "perf_raw": bucket['perf_raw'],
            }
            for name, values in bucket["counters"].items():
                entry["arms"][arm][f"{name}_median"] = median(values)
        for arm in binaries:
            if arm == options.reference:
                continue
            ratio = median(samples[(workload, options.reference)]["wall"]) / \
                median(samples[(workload, arm)]["wall"])
            # Use the same orientation as the point estimate: reference over this arm.
            interval = bootstrap_ratio(samples[(workload, options.reference)]["wall"],
                                       samples[(workload, arm)]["wall"])
            entry["ratios"][f"{options.reference}/{arm}"] = {
                "median": ratio, "low": interval[0], "high": interval[1],
                "formula": f"median({options.reference} wall) / median(arm wall)"}
        report["workloads"][workload].update(entry)

    if options.out:
        Path(options.out).write_text(json.dumps(report, indent=1) + "\n")

    print()
    header = f"{'workload':16s} " + " ".join(f"{arm:>12s}" for arm in binaries)
    print(header)
    for workload in WORKLOADS:
        row = f"{workload:16s} "
        for arm in binaries:
            value = report["workloads"][workload]["arms"][arm]["wall_ms_median"]
            row += f"{value:12.2f} "
        print(row)
    print()
    for workload in WORKLOADS:
        for key, value in report["workloads"][workload]["ratios"].items():
            print(f"{workload:16s} {key:16s} {value['median']:.3f}x "
                  f"[{value['low']:.3f}, {value['high']:.3f}]")
    return 0


if __name__ == "__main__":
    sys.exit(main())

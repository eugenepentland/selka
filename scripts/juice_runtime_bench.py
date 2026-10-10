#!/usr/bin/env python3
"""Validate native Juice runtime estimates on prebuilt, checksum-identified pairs.

Developer/nightly driver, not an installed Juice dependency. A suite contains
cases with name, family, base/candidate {binary, sha256}, args, expected_stdout,
and optionally stdout_regex, units. Binaries must need no external input files.
All capture, timing and derived evidence is retained in a new output directory.
"""
from __future__ import annotations

import argparse
import copy
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import statistics
import subprocess
import time


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def write(path, value):
    Path(path).write_text(json.dumps(value, indent=2, allow_nan=False) + "\n")


def scheduling_policy(cpu):
    policy = {}
    directory = Path(f"/sys/devices/system/cpu/cpu{cpu}/cpufreq")
    for name in ("scaling_driver", "scaling_governor", "scaling_min_freq", "scaling_max_freq"):
        path = directory / name
        policy[name] = path.read_text().strip() if path.exists() else None
    for line in Path("/proc/self/sched").read_text().splitlines():
        if ":" in line:
            name, value = (part.strip() for part in line.split(":", 1))
            if name in ("policy", "prio", "uclamp.min", "uclamp.max", "effective uclamp.min", "effective uclamp.max"):
                policy[name] = value
    return policy


def stats(values):
    median = statistics.median(values)
    return dict(median=median, min=min(values), max=max(values),
                spread=(max(values) - min(values)) / median, samples=values)


def command(argv, prefix, *, cwd=None, env=None, timeout=120):
    """Retain raw output and use communicate, avoiding wait's polling-time bias."""
    start = time.perf_counter_ns()
    process = subprocess.Popen(list(map(str, argv)), cwd=cwd, env=env,
                               stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, start_new_session=True)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except BaseException:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise
    elapsed = (time.perf_counter_ns() - start) / 1e9
    Path(str(prefix) + ".stdout").write_bytes(stdout)
    Path(str(prefix) + ".stderr").write_bytes(stderr)
    return dict(command=list(map(str, argv)), seconds=elapsed, exit_code=process.returncode,
                stdout_sha256=hashlib.sha256(stdout).hexdigest(),
                stderr_sha256=hashlib.sha256(stderr).hexdigest()), stdout, stderr


def native(compiler, args, prefix, codes=(0,)):
    row, out, err = command([compiler, "juice", *args], prefix)
    if row["exit_code"] not in codes:
        raise RuntimeError(f"native Juice failed: {err.decode(errors='replace')}")
    return out.decode().strip()


def combine(paths, destination, policy=None, pairing=None):
    """Concatenate complete native captures, retaining and hashing their raw evidence."""
    destination.mkdir()
    records = [read(path) for path in paths]
    result = copy.deepcopy(records[0])
    result["name"] = destination.name
    result["evidence"] = {}
    result["derived_from"] = []
    for index, (path, record) in enumerate(zip(paths, records)):
        if record["status"] != "complete":
            raise ValueError("cannot aggregate incomplete capture")
        for key in ("contract", "context", "sources", "build_config", "collector"):
            if record[key] != records[0][key]:
                raise ValueError(f"interleaved capture changed {key}")
        if record["build"]["artifacts"] != records[0]["build"]["artifacts"]:
            raise ValueError("interleaved capture changed executable")
        for name, expected in record["evidence"].items():
            source = path.parent / name
            if digest(source) != expected:
                raise ValueError("capture raw evidence was modified")
            target = f"round-{index}-{name}"
            shutil.copy2(source, destination / target)
            result["evidence"][target] = expected
        provenance = f"round-{index}-record.json"
        shutil.copy2(path, destination / provenance)
        result["evidence"][provenance] = digest(path)
        result["derived_from"].append(provenance)
    for name, cell in result["workloads"].items():
        originals = [record["workloads"][name] for record in records]
        if any(row["correctness"] != cell["correctness"] for row in originals):
            raise ValueError("interleaved outputs differ")
        samples = [sample for row in originals for sample in row["samples"]]
        if not 2 <= len(samples) <= 30:
            raise ValueError("aggregate requires 2..30 samples")
        cell["samples"] = samples
        cell["metrics"] = {key: stats([sample["metrics"][key] for sample in samples])
                           for key in cell["metrics"]}
        if pairing is not None:
            if any(len(row["samples"]) != pairing["samples_per_pair"] for row in originals):
                raise ValueError("unequal capture-pair sizes")
            cell["pairing"] = pairing
    if policy is not None:
        result["context"]["benchmark_policy"] = policy
    path = destination / "record.json"
    write(path, result)
    return path


def manifest(case, project):
    work = dict(name="work", family=case["family"], args=case["args"],
                expected_stdout=case["expected_stdout"], units=case.get("units", 1),
                unit="completed-item", timeout_seconds=60)
    if "stdout_regex" in case:
        work["stdout_regex"] = case["stdout_regex"]
    value = dict(version=1, name=case["name"], adapter="native", sources=["program"],
                 build=dict(compiler="cp", command=["{compiler}", "{root}/program", "{binary}"]),
                 workloads=[work])
    path = project / "juice.json"
    write(path, value)
    return path


def check_output(case, row, stdout, stderr):
    if row["exit_code"] or stderr:
        raise ValueError("timed application failed; see raw output")
    value = stdout.decode()
    if "stdout_regex" in case:
        match = re.fullmatch(case["stdout_regex"], value)
        if match is None or len(match.groups()) != 1:
            raise ValueError("timed stdout does not match oracle pattern")
        value = match.group(1)
    if value != case["expected_stdout"]:
        raise ValueError("timed output disagrees with oracle")


def elapsed_pairs(case, root, binaries, run, cpu, pairs):
    # Match native capture's argv, path, cwd and controlled environment. Timing
    # includes process launch/loader/exit. Collector wall_seconds is never a label.
    environment = dict(PATH=os.defpath, LC_ALL="C", LANG="C", TZ="UTC",
                       HOME=str(run / "home"), TMPDIR=str(run / "tmp"), PWD=str(run))
    observations, raw = [], []
    for index in range(pairs + 1):
        values = {}
        order = ("base", "candidate") if index % 2 == 0 else ("candidate", "base")
        for arm in order:
            shutil.rmtree(run)
            (run / "home").mkdir(parents=True)
            (run / "tmp").mkdir()
            shutil.copy2(binaries[arm], run / "program")
            prefix = root / f"timing-{index}-{arm}"
            row, out, err = command(["taskset", "-c", str(cpu), run / "program", *case["args"]],
                                    prefix, cwd=run, env=environment, timeout=60)
            check_output(case, row, out, err)
            row.update(arm=arm, round=index, warmup=index == 0)
            raw.append(row)
            values[arm] = row["seconds"]
        if index:
            observations.append([values["base"], values["candidate"]])
    write(root / "timing-runs.json", raw)
    return observations


def run_case(case, options):
    root = options.output / case["name"]
    root.mkdir()
    project = root / "project"
    project.mkdir()
    binary_copies = {}
    for arm in ("base", "candidate"):
        identity = case[arm]
        source = Path(identity["binary"])
        if digest(source) != identity["sha256"]:
            raise ValueError(f"{case['name']}: {arm} binary identity changed")
        target = root / arm
        shutil.copy2(source, target)
        if digest(target) != identity["sha256"]:
            raise ValueError("binary changed while copying")
        binary_copies[arm] = target
    contract = manifest(case, project)
    records = dict(base=[], candidate=[])
    policy = scheduling_policy(options.cpu)
    # Warm both arms, retaining these captures but exclude them from aggregation.
    for index in range(options.counter_pairs + 1):
        order = ("base", "candidate") if index % 2 == 0 else ("candidate", "base")
        for arm in order:
            shutil.copy2(binary_copies[arm], project / "program")
            label = f"{arm}-{index}"
            output = native(options.compiler, ["record", contract, "--name", label,
                "--profile", "runtime", "--cpu", str(options.cpu), "--repeats", "2",
                "--cache-dir", root / "cache"], root / label)
            if scheduling_policy(options.cpu) != policy:
                raise ValueError("scheduling/frequency policy changed during capture")
            if index:
                records[arm].append(Path(output))
    pairing = dict(method="alternating-captures-v1", samples_per_pair=2,
                   id=hashlib.sha256(str(root).encode()).hexdigest())
    joined = {arm: combine(paths, root / f"{arm}-aggregate", policy, pairing) for arm, paths in records.items()}
    comparison = root / "comparison.json"
    native(options.compiler, ["compare", joined["base"], joined["candidate"], "--output", comparison], root / "compare")
    report = read(comparison)
    run = Path(read(joined["base"])["context"]["execution_path"])
    evidence = {key: report[key] for key in ("base_id", "candidate_id", "context_id")}
    evidence.update(version="juice-timing-evidence-v1", workload="work",
        method="independent whole-process monotonic elapsed time, same CPU/path/environment; alternating AB/BA; first pair warmup; no perf instrumentation",
        pairs=elapsed_pairs(case, root, binary_copies, run, options.cpu, options.timing_pairs))
    if scheduling_policy(options.cpu) != policy:
        raise ValueError("scheduling/frequency policy changed during timing")
    timing = root / "timing.json"
    write(timing, evidence)
    validation = root / "validation.json"
    native(options.compiler, ["validate-runtime", comparison, timing, "--output", validation], root / "validate", codes=(0, 1))
    result = read(validation)
    result.update(name=case["name"], family=case["family"],
                  counter_proxy=report["workloads"]["work"]["runtime_proxy"],
                  instruction_ratio=report["workloads"]["work"]["instruction_ratio"])
    print(f"{case['name']}: {result['status']}; error={result['relative_error']}", flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("suite", type=Path)
    parser.add_argument("--compiler", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--cpu", type=int, required=True)
    parser.add_argument("--counter-pairs", type=int, default=5, choices=range(5, 16))
    parser.add_argument("--timing-pairs", type=int, default=9, choices=range(5, 31))
    options = parser.parse_args()
    options.compiler = options.compiler.resolve()
    options.output = options.output.resolve()
    cases = read(options.suite)["cases"]
    names = [case["name"] for case in cases]
    if not cases or len(set(names)) != len(names) or any(re.fullmatch(r"[a-zA-Z0-9_-]+", name) is None for name in names):
        parser.error("nonempty suite requires unique simple case names")
    options.output.mkdir(parents=True, exist_ok=False)
    compiler_identity = digest(options.compiler)
    copied = options.output / "mylang"
    shutil.copy2(options.compiler, copied)
    if digest(copied) != compiler_identity:
        raise ValueError("Juice executable changed while copying")
    options.compiler = copied
    write(options.output / "suite.json", read(options.suite))
    write(options.output / "method.json", dict(compiler_sha256=compiler_identity, cpu=options.cpu,
          counter_pairs=options.counter_pairs, timing_pairs=options.timing_pairs,
          scheduling_policy=scheduling_policy(options.cpu)))
    # One bounded, nonblocking lease: never silently queue behind a long run.
    lock_path = Path.home() / ".cache/mylang/runtime-parity-timing.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        results = []
        for case in cases:
            print(f"Measuring {case['name']}", flush=True)
            results.append(run_case(case, options))
            write(options.output / "results.json", dict(complete=False, cases=results))
    summary = dict(complete=True, cases=results, target_relative_error=0.05,
                   passed=sum(row["passed"] for row in results), total=len(results),
                   uncertain=sum(row["status"] == "uncertain" for row in results),
                   scope="prospective case validation; no fitted model or universal accuracy claim")
    write(options.output / "results.json", summary)
    print(f"Within target: {summary['passed']}/{summary['total']}; uncertain: {summary['uncertain']}")
    return 0 if summary["passed"] == summary["total"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

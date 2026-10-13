#!/usr/bin/env python3
"""Measurements for the Lox ports (see ../SPEC.md). Correctness lives in lox_bench.py.

  runtime  build each port's profile, then time every script x engine at its timed tier,
           interleaving ports round by round on one pinned CPU. Checks stdout every run.
  compile  cold builds (empty cache each time), cold builds after priming the toolchain
           (harness/prime/), a warm no-op rebuild, then the edit ladder from bench.json
           (apply, time the rebuild, revert, rebuild untimed).
  tests    unit-test command: cold, cold after priming, cached rerun, forced rerun, and
           after the hub_body edit.
  sysinfo  toolchain versions and machine facts, recorded alongside every result.

Every command writes JSON under benchmarks/lox/results/<UTC stamp>-<command>/ and
prints a table. Medians are reported; each sample is kept in the JSON.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import platform
import shutil
import statistics
import subprocess
import sys
import tempfile
import threading
import time
from contextlib import contextmanager
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lox_bench as lb  # noqa: E402

RESULTS = lb.BENCH_ROOT / "results"


# --------------------------------------------------------------------------- process timing

def timed(command: list[str], cwd: Path | None = None, env: dict | None = None,
          cpu: int | None = None, timeout: float = 3600) -> dict:
    """Run a command, returning wall seconds, max RSS (KiB), exit status and output."""
    if cpu is not None:
        command = ["taskset", "-c", str(cpu), *command]
    start = time.perf_counter()
    proc = subprocess.Popen(command, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    expired = watchdog(proc, timeout)
    out, err = proc.communicate()  # no timeout: blocking reads and waitpid, so no polling granularity
    wall = time.perf_counter() - start
    expired.cancel()
    if expired.fired:
        return {"wall": None, "status": "timeout", "stdout": out, "stderr": err, "maxrss_kib": None}
    return {"wall": wall, "status": proc.returncode, "stdout": out, "stderr": err, "maxrss_kib": None}


class watchdog:
    """Kill `proc` after `timeout` seconds. Popen.wait(timeout=...) polls with a delay
    that grows to 50 ms, which quantized every sub-second wall time; a blocking wait
    plus this timer measures exactly."""

    def __init__(self, proc: subprocess.Popen, timeout: float):
        self.fired = False
        self._timer = threading.Timer(timeout, self._kill, args=(proc,))
        self._timer.daemon = True
        self._timer.start()

    def _kill(self, proc: subprocess.Popen) -> None:
        self.fired = True
        proc.kill()

    def cancel(self) -> None:
        self._timer.cancel()


def timed_rss(command: list[str], cpu: int | None, timeout: float) -> dict:
    """Like timed(), plus the target's own peak RSS and CPU time via /usr/bin/time.

    ru_maxrss from wait4 is useless here: exec keeps the forking Python's high-water
    mark, so every small program would report the harness's RSS. GNU time forks a tiny
    process instead and reports the real child's figures.
    """
    scratch = lb.lox_bench_dir() / "tmp"
    scratch.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryFile(dir=scratch) as out, tempfile.TemporaryFile(dir=scratch) as err, \
            tempfile.NamedTemporaryFile("r", dir=scratch, suffix=".time") as report:
        command = ["/usr/bin/time", "-o", report.name, "-f", "%M %U %S", *command]
        if cpu is not None:
            command = ["taskset", "-c", str(cpu), *command]
        start = time.perf_counter()
        proc = subprocess.Popen(command, stdout=out, stderr=err)
        expired = watchdog(proc, timeout)
        status = proc.wait()
        wall = time.perf_counter() - start
        expired.cancel()
        if expired.fired:
            return {"wall": None, "status": "timeout", "maxrss_kib": None, "cpu_s": None, "stdout": b"", "stderr": b""}
        out.seek(0)
        err.seek(0)
        fields = report.read().split()[-3:]
        maxrss, user, system = (int(fields[0]), float(fields[1]), float(fields[2])) if len(fields) == 3 else (None, 0.0, 0.0)
        return {"wall": wall, "status": status, "maxrss_kib": maxrss, "cpu_s": user + system,
                "stdout": out.read(), "stderr": err.read()}


# --------------------------------------------------------------------------- quiet gate

QUIET_THRESHOLD = 25.0   # percent busy, per CPU for runtime, mean over the set for builds
WAITS: list[dict] = []   # every wait, recorded into the result JSON


def cpu_times() -> dict[int, tuple[int, int]]:
    times = {}
    for line in Path("/proc/stat").read_text().splitlines():
        if line.startswith("cpu") and line[3].isdigit():
            fields = line.split()
            values = list(map(int, fields[1:]))
            times[int(fields[0][3:])] = (sum(values), values[3] + values[4])
    return times


def busy(cpus: list[int], seconds: float = 3.0) -> dict[int, float]:
    a = cpu_times()
    time.sleep(seconds)
    b = cpu_times()
    return {c: 100.0 * (1 - (b[c][1] - a[c][1]) / max(1, b[c][0] - a[c][0])) for c in cpus}


def parse_cpus(spec: str) -> list[int]:
    cpus = []
    for part in spec.split(","):
        lo, _, hi = part.partition("-")
        cpus.extend(range(int(lo), int(hi or lo) + 1))
    return cpus


def smt_siblings(cpu: int) -> list[int]:
    path = Path(f"/sys/devices/system/cpu/cpu{cpu}/topology/thread_siblings_list")
    return parse_cpus(path.read_text().strip()) if path.exists() else [cpu]


def wait_quiet(cpus: list[int], label: str, mode: str) -> None:
    """Block until `cpus` are quiet: every CPU under the threshold (mode "each") or their
    mean under it (mode "mean"). Other sessions share this machine; samples taken while
    they saturate it would measure contention, not the ports."""
    started = time.time()
    while True:
        load = busy(cpus)
        level = max(load.values()) if mode == "each" else sum(load.values()) / len(load)
        if level < QUIET_THRESHOLD:
            if time.time() - started > 5:
                WAITS.append({"label": label, "waited_s": round(time.time() - started), "at": time.time()})
            return
        print(f"waiting for quiet CPUs before {label}: {level:.0f}% busy", file=sys.stderr, flush=True)
        time.sleep(30)


def median(xs: list[float]) -> float | None:
    xs = [x for x in xs if x is not None]
    return statistics.median(xs) if xs else None


def wanted_profiles(tokens: list[str], port: str, config: dict) -> list[str]:
    """`release` applies to every port that has it; `mylang:release-qbe` only to mylang."""
    chosen = []
    for token in tokens:
        owner, _, profile = token.rpartition(":")
        if (not owner or owner == port) and profile in config["profiles"] and profile not in chosen:
            chosen.append(profile)
    return chosen


def result_dir(command: str) -> Path:
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    path = RESULTS / f"{stamp}-{command}"
    path.mkdir(parents=True, exist_ok=True)
    return path


def write_json(path: Path, data) -> None:
    path.write_text(json.dumps(data, indent=2, default=lambda b: b.decode(errors="replace") if isinstance(b, bytes) else str(b)) + "\n")


# --------------------------------------------------------------------------- sysinfo

def sysinfo(ports: list[str]) -> dict:
    info = {
        "utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "kernel": platform.release(),
        "cpu": next((l.split(":", 1)[1].strip() for l in Path("/proc/cpuinfo").read_text().splitlines()
                     if l.startswith("model name")), None),
        "toolchains": lb.toolchains(),
        "git_head": subprocess.run(["git", "rev-parse", "HEAD"], cwd=lb.BENCH_ROOT, capture_output=True,
                                   text=True).stdout.strip(),
        "versions": {},
    }
    for port in ports:
        port_dir, config = lb.load_port(port)
        command = [lb.substitute(p, Path("/nonexistent"), port_dir) for p in config.get("version", [])]
        if command:
            r = subprocess.run(command, cwd=port_dir, capture_output=True, text=True,
                               env=lb.port_env(config, Path(tempfile.gettempdir()), port_dir))
            info["versions"][port] = (r.stdout or r.stderr).strip()
    return info


# --------------------------------------------------------------------------- runtime

def runtime(ports: list[str], profiles: list[str], rounds: int, cpu: int, filt: str | None,
            engines: list[str]) -> None:
    out_dir = result_dir("runtime")
    binaries: dict[str, list[str]] = {}
    for port in ports:
        port_dir, config = lb.load_port(port)
        for profile in wanted_profiles(profiles, port, config):
            cache = (lb.lox_bench_dir() / "cache" / f"{port}-{profile}").resolve()
            binary = lb.build_port(port, profile, cache)
            # `exec` (optional) is the command prefix to time instead of `binary`, for a port
            # whose `binary` is a launcher script (mylang's lox.sh adds a leading `--`).
            exec_prefix = config["profiles"][profile].get("exec")
            binaries[f"{port}:{profile}"] = ([lb.substitute(p, cache, port_dir) for p in exec_prefix]
                                             if exec_prefix else [str(binary)])
    work = Path(tempfile.mkdtemp(prefix="lox-runtime-"))
    runs = []
    for name, tiers in lb.sizes().items():
        if filt and filt not in name:
            continue
        for engine in engines:
            runs.append((name, engine, lb.sized_script(name, tiers[engine], work), lb.expected_path(name, engine).read_bytes()))

    samples: dict[str, dict[str, list]] = {}
    failures = []
    loads = [os.getloadavg()]
    timing_cpus = sorted(set(smt_siblings(cpu)) | {cpu})
    for r in range(rounds):
        for name, engine, script, want in runs:
            wait_quiet(timing_cpus, f"round {r + 1} {name}/{engine}", "each")
            order = list(binaries.items())
            order = order[r % len(order):] + order[:r % len(order)]  # rotate who goes first
            for label, binary in order:
                res = timed_rss([*binary, f"--engine={engine}", str(script)], cpu, timeout=1800)
                key = f"{name}/{engine}"
                if res["status"] != 0 or res["stdout"] != want:
                    failures.append({"run": key, "binary": label, "status": res["status"],
                                     "stderr": res["stderr"][-400:]})
                    res["wall"] = None
                samples.setdefault(key, {}).setdefault(label, []).append(
                    {"wall": res["wall"], "cpu_s": res.get("cpu_s"), "maxrss_kib": res["maxrss_kib"]})
        loads.append(os.getloadavg())
        print(f"round {r + 1}/{rounds} done, load {loads[-1]}", file=sys.stderr, flush=True)
        # Save after every round: other sessions on this machine have killed long passes.
        write_json(out_dir / "runtime.json", {"cpu": cpu, "rounds_done": r + 1, "rounds": rounds,
                                              "commands": binaries, "samples": samples, "failures": failures,
                                              "loadavg_per_round": loads, "quiet_waits": WAITS, "partial": True})

    table = {key: {label: {"median_s": median([s["wall"] for s in xs]),
                           "min_s": min((s["wall"] for s in xs if s["wall"] is not None), default=None),
                           "median_cpu_s": median([s["cpu_s"] for s in xs]),
                           "maxrss_kib": max((s["maxrss_kib"] or 0) for s in xs)}
                   for label, xs in per.items()}
             for key, per in samples.items()}
    write_json(out_dir / "runtime.json", {"sysinfo": sysinfo(ports), "cpu": cpu, "rounds": rounds,
                                          "commands": binaries,
                                          "samples": samples, "summary": table, "failures": failures,
                                          "loadavg_per_round": loads, "quiet_waits": WAITS,
                                          "quiet_threshold_pct": QUIET_THRESHOLD, "timing_cpus": timing_cpus})
    labels = list(binaries)
    lines = ["| script/engine | " + " | ".join(labels) + " |", "|---" * (len(labels) + 1) + "|"]
    for key, per in table.items():
        best = min((v["median_s"] for v in per.values() if v["median_s"]), default=None)
        cells = []
        for label in labels:
            m = per.get(label, {}).get("median_s")
            cells.append("FAIL" if m is None else f"{m * 1000:.0f} ms ({m / best:.2f}x)")
        lines.append(f"| {key} | " + " | ".join(cells) + " |")
    (out_dir / "runtime.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    print(f"\n{len(failures)} failed runs; results in {out_dir}")


# --------------------------------------------------------------------------- compile + tests

@contextmanager
def applied_edit(port_dir: Path, edit: dict):
    path = port_dir / edit["file"]
    original = path.read_text()
    count = original.count(edit["find"])
    if count != 1:
        raise SystemExit(f"edit find text occurs {count} times in {path}")
    path.write_text(original.replace(edit["find"], edit["replace"]))
    try:
        yield
    finally:
        path.write_text(original)


PRIME = Path(__file__).resolve().parent / "prime"


def prime(port: str, key: str, cache: Path, cpus: str) -> bool:
    """Build the language's hello-world into `cache` so its shared toolchain artifacts exist."""
    config_path = PRIME / port / "prime.json"
    if not config_path.exists():
        return False
    commands = json.loads(config_path.read_text())
    if key not in commands:
        return False
    port_dir, config = lb.load_port(port)
    command = [lb.substitute(p, cache, port_dir) for p in commands[key]]
    res = timed(["taskset", "-c", cpus, *command], cwd=PRIME / port, env=lb.port_env(config, cache, port_dir))
    if res["status"] != 0:
        raise BuildFailed(f"{port} prime ({key}) status {res['status']}: {res['stderr'][-500:].decode(errors='replace')}")
    return True


def build_command(port: str, profile: str, cache: Path) -> tuple[list[str], Path, dict]:
    port_dir, config = lb.load_port(port)
    command = [lb.substitute(p, cache, port_dir) for p in config["profiles"][profile]["build"]]
    return command, port_dir, lb.port_env(config, cache, port_dir)


class BuildFailed(Exception):
    pass


def run_build(port: str, profile: str, cache: Path, cpus: str) -> float:
    """Time one build. A failure (for example a stray signal) is retried once; a second
    failure raises BuildFailed, which the caller records instead of aborting the pass."""
    command, port_dir, env = build_command(port, profile, cache)
    for attempt in (1, 2):
        wait_quiet(parse_cpus(cpus), f"{port} {profile} build", "mean")
        res = timed(["taskset", "-c", cpus, *command], cwd=port_dir, env=env)
        if res["status"] == 0:
            return res["wall"]
        print(f"{port} {profile} build failed (attempt {attempt}, status {res['status']}):\n"
              f"{res['stderr'][-1500:].decode(errors='replace')}", file=sys.stderr, flush=True)
    raise BuildFailed(f"{port} {profile} status {res['status']}")


def compile_ladder(ports: list[str], profiles: list[str], rounds: int, cpus: str) -> None:
    out_dir = result_dir("compile")
    info = sysinfo(ports)
    results: dict[str, dict] = {}
    for port in ports:
        port_dir, config = lb.load_port(port)
        for profile in wanted_profiles(profiles, port, config):
            key = f"{port}:{profile}"
            try:
                results[key] = ladder_for(port, profile, config, port_dir, rounds, cpus)
            except BuildFailed as failure:
                results[key] = {"failed": str(failure)}
                print(f"{key}: FAILED {failure}", file=sys.stderr, flush=True)
                continue
            print(f"{key}: " + ", ".join(f"{s}={v['median_s']:.2f}s" for s, v in results[key].items()
                                         if isinstance(v, dict)), file=sys.stderr, flush=True)
            write_json(out_dir / "compile.json", {"sysinfo": info, "cpus": cpus, "rounds": rounds,
                                                  "results": results, "partial": True})
    write_json(out_dir / "compile.json", {"sysinfo": info, "cpus": cpus, "rounds": rounds, "results": results,
                                          "loadavg_end": os.getloadavg(), "quiet_waits": WAITS,
                                          "quiet_threshold_pct": QUIET_THRESHOLD})
    steps = ["cold", "cold_primed", "noop", "hub_comment", "leaf_body", "hub_body", "hub_interface"]
    lines = ["| port:profile | " + " | ".join(steps) + " |", "|---" * (len(steps) + 1) + "|"]
    for key, row in results.items():
        if "failed" in row:
            lines.append(f"| {key} | FAILED: {row['failed']} |")
            continue
        lines.append(f"| {key} | " + " | ".join(
            f"{row[s]['median_s']:.2f} s" if s in row and row[s]["median_s"] is not None else "-" for s in steps) + " |")
    (out_dir / "compile.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    print(f"\nresults in {out_dir}")


def ladder_for(port: str, profile: str, config: dict, port_dir: Path, rounds: int, cpus: str) -> dict:
    """Cold, primed-cold, no-op and edit-ladder build times for one port profile."""
    row: dict[str, list] = {"cold": [], "cold_primed": [], "noop": [], **{name: [] for name in config["edits"]}}
    for _ in range(rounds):
        with tempfile.TemporaryDirectory(prefix=f"lox-cold-{port}-", dir=lb.lox_bench_dir()) as cold:
            row["cold"].append(run_build(port, profile, Path(cold), cpus))
        with tempfile.TemporaryDirectory(prefix=f"lox-primed-{port}-", dir=lb.lox_bench_dir()) as cold:
            primed = prime(port, profile, Path(cold), cpus)
            row["cold_primed"].append(run_build(port, profile, Path(cold), cpus) if primed else row["cold"][-1])
    cache = Path(tempfile.mkdtemp(prefix=f"lox-warm-{port}-", dir=lb.lox_bench_dir()))
    try:
        run_build(port, profile, cache, cpus)
        for _ in range(rounds):
            row["noop"].append(run_build(port, profile, cache, cpus))
            for name, edit in config["edits"].items():
                with applied_edit(port_dir, edit):
                    row[name].append(run_build(port, profile, cache, cpus))
                run_build(port, profile, cache, cpus)  # back to the unedited state, untimed
    finally:
        shutil.rmtree(cache, ignore_errors=True)
    result: dict = {step: {"median_s": median(xs), "samples": xs} for step, xs in row.items()}
    result["primed"] = (PRIME / port / "prime.json").exists()
    return result


def tests(ports: list[str], rounds: int, cpus: str) -> None:
    out_dir = result_dir("tests")
    results = {}
    for port in ports:
        port_dir, config = lb.load_port(port)
        spec = config["test"]

        def run(which: str, cache: Path) -> float:
            command = [lb.substitute(p, cache, port_dir) for p in spec[which]]
            for attempt in (1, 2):
                wait_quiet(parse_cpus(cpus), f"{port} tests", "mean")
                res = timed(["taskset", "-c", cpus, *command], cwd=port_dir, env=lb.port_env(config, cache, port_dir))
                if res["status"] == 0:
                    return res["wall"]
                print(f"{port} tests failed (attempt {attempt}, status {res['status']}):\n"
                      f"{res['stderr'][-1500:].decode(errors='replace')}", file=sys.stderr, flush=True)
            raise BuildFailed(f"{port} tests status {res['status']}")

        try:
            row = {"cold": [], "cold_primed": [], "cached": [], "forced": [], "after_hub_body": []}
            for _ in range(rounds):
                with tempfile.TemporaryDirectory(prefix=f"lox-tcold-{port}-", dir=lb.lox_bench_dir()) as cold:
                    row["cold"].append(run("run", Path(cold)))
                with tempfile.TemporaryDirectory(prefix=f"lox-tprimed-{port}-", dir=lb.lox_bench_dir()) as cold:
                    primed = prime(port, "test", Path(cold), cpus)
                    row["cold_primed"].append(run("run", Path(cold)) if primed else row["cold"][-1])
            cache = Path(tempfile.mkdtemp(prefix=f"lox-twarm-{port}-", dir=lb.lox_bench_dir()))
            try:
                run("run", cache)
                for _ in range(rounds):
                    row["cached"].append(run("run", cache))
                    if spec.get("force"):
                        row["forced"].append(run("force", cache))
                    with applied_edit(port_dir, config["edits"]["hub_body"]):
                        row["after_hub_body"].append(run("run", cache))
                    run("run", cache)
            finally:
                shutil.rmtree(cache, ignore_errors=True)
        except BuildFailed as failure:
            results[port] = {"failed": str(failure)}
            print(f"{port}: FAILED {failure}", file=sys.stderr, flush=True)
            continue
        results[port] = {step: {"median_s": median(xs), "samples": xs} for step, xs in row.items()}
    write_json(out_dir / "tests.json", {"sysinfo": sysinfo(ports), "cpus": cpus, "rounds": rounds, "results": results,
                                        "loadavg_end": os.getloadavg(), "quiet_waits": WAITS,
                                        "quiet_threshold_pct": QUIET_THRESHOLD})
    steps = ["cold", "cold_primed", "cached", "forced", "after_hub_body"]
    lines = ["| port | " + " | ".join(steps) + " |", "|---" * (len(steps) + 1) + "|"]
    for port, row in results.items():
        if "failed" in row:
            lines.append(f"| {port} | FAILED: {row['failed']} |")
            continue
        lines.append(f"| {port} | " + " | ".join(
            f"{row[s]['median_s']:.2f} s" if row[s]["median_s"] is not None else "-" for s in steps) + " |")
    (out_dir / "tests.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    print(f"\nresults in {out_dir}")


# --------------------------------------------------------------------------- CLI

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    all_ports = ["mylang", "zig", "rust", "go"]

    p = sub.add_parser("runtime")
    p.add_argument("--ports", default=",".join(all_ports))
    p.add_argument("--profiles", default="release",
                   help="comma list; `release` applies to every port, `mylang:release-qbe` to one")
    p.add_argument("--rounds", type=int, default=5)
    p.add_argument("--cpu", type=int, default=6, help="the one CPU every timed run is pinned to")
    p.add_argument("--engines", default="vm,tree")
    p.add_argument("--filter")

    p = sub.add_parser("compile")
    p.add_argument("--ports", default=",".join(all_ports))
    p.add_argument("--profiles", default="release,debug")
    p.add_argument("--rounds", type=int, default=3)
    p.add_argument("--cpus", default="0-5", help="CPU list for the compilers (they may use several)")

    p = sub.add_parser("tests")
    p.add_argument("--ports", default=",".join(all_ports))
    p.add_argument("--rounds", type=int, default=3)
    p.add_argument("--cpus", default="0-5")

    p = sub.add_parser("sysinfo")
    p.add_argument("--ports", default=",".join(all_ports))

    args = parser.parse_args()
    ports = [p for p in args.ports.split(",") if p]
    if args.cmd == "runtime":
        runtime(ports, args.profiles.split(","), args.rounds, args.cpu, args.filter, args.engines.split(","))
    elif args.cmd == "compile":
        compile_ladder(ports, args.profiles.split(","), args.rounds, args.cpus)
    elif args.cmd == "tests":
        tests(ports, args.rounds, args.cpus)
    elif args.cmd == "sysinfo":
        print(json.dumps(sysinfo(ports), indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""S4-X synthetic dev-loop receipts. Launch through build-slot.sh build.

CPU-10 commands acquire the shared timing lock one at a time. Parallel cold
release compilation keeps the build wrapper's affinity and is a separate row.
Every source edit has a fresh, retained digest, so a prior whole-project verdict
cannot turn an edited request into an unchanged request. Both compiler hosts
must be built in the explicit --host-mode, normally ReleaseFast.

Each command has its own log. Unchanged requests get an additional process trace
to prove the absence of zig cc. A distinct fresh release edit is traced to capture
the actual unit compile commands; the edited module's -O3 command is replayed
with a fresh local Zig cache. A report identifying source_path and llvm_path is
needed if more than one unit compiles. No unit is selected by its measured cost.
"""
import argparse
import ast
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
GENERATOR = ROOT / "experiments/new-core-s4-20261006/gen_program.py"
LOCK = Path("/run/user/1000/mylang-slots/cpu10.lock")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def process_trace(path):
    """Successful zig cc execs, their arguments, and lifetime through child exit."""
    processes = {}
    for line in path.read_text().splitlines():
        match = re.match(r"(\d+)\s+(\d+\.\d+)\s+(.*)", line)
        if not match:
            continue
        pid, stamp, call = match.groups()
        stamp = float(stamp)
        if call.startswith("execve(") and call.endswith(" = 0"):
            command = re.match(r'execve\(("(?:[^"\\]|\\.)*"), (\[.*?\]), ', call)
            if not command:
                continue
            argv = ast.literal_eval(command.group(2))
            if len(argv) > 1 and Path(argv[0]).name == "zig" and argv[1] == "cc":
                processes[pid] = {"pid": int(pid), "argv": argv, "start": stamp,
                                  "llvm_inputs": [arg for arg in argv if arg.endswith(".ll")],
                                  "compilation": "-c" in argv}
        elif call.startswith("+++ exited with") and pid in processes:
            processes[pid]["seconds"] = stamp - processes[pid]["start"]
            processes[pid]["exit"] = int(re.search(r"exited with (\d+)", call).group(1))
    return list(processes.values())


def json_lines(output):
    receipts = []
    for line in output.splitlines():
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            receipts.append(value)
    return receipts


class Runner:
    def __init__(self, evidence, timeout):
        self.evidence, self.timeout, self.ordinal = evidence, timeout, 0

    def run(self, label, command, environment=None, cpu10=False, trace=False):
        self.ordinal += 1
        stem = self.evidence / f"command-{self.ordinal:04d}-{label}"
        argv = list(map(str, command))
        trace_path = stem.with_suffix(".trace")
        if trace:
            argv = ["strace", "-f", "-ttt", "-s", "65535", "-e", "trace=process",
                    "-o", str(trace_path), *argv]
        if cpu10:
            argv = ["taskset", "-c", "10", *argv]
        with LOCK.open("a") as timing_lock:
            if cpu10:
                fcntl.flock(timing_lock, fcntl.LOCK_EX)
            started = time.perf_counter()
            result = subprocess.run(argv, capture_output=True, text=True,
                                    env=environment, timeout=self.timeout, cwd=ROOT)
            seconds = time.perf_counter() - started
        log = stem.with_suffix(".log")
        with log.open("x") as stream:
            stream.write("$ " + shlex.join(argv) + "\n")
            stream.write("affinity=" + ("10" if cpu10 else str(sorted(os.sched_getaffinity(0)))) + "\n")
            if environment:
                for name in ("MYLANG_JOBS", "MYL_CORE_BUILD_REPORT", "ZIG_LOCAL_CACHE_DIR"):
                    stream.write(f"{name}={environment.get(name, '')}\n")
            stream.write(result.stdout + result.stderr)
            stream.write(f"\nexit={result.returncode} elapsed_seconds={seconds:.9f}\n")
        receipt = {"seconds": seconds, "exit": result.returncode,
                   "log": str(log.relative_to(ROOT)), "cpu10": cpu10,
                   "records": json_lines(result.stderr)}
        if trace:
            receipt.update(trace=str(trace_path.relative_to(ROOT)),
                           zig_cc=process_trace(trace_path), trace_includes_overhead=True)
        if result.returncode:
            raise RuntimeError(f"{label} failed; retained {log}")
        return receipt


class Project:
    def __init__(self, runner, work, modules):
        self.runner, self.modules, self.serial = runner, modules, 0
        self.path = work / f"synthetic-{modules}"
        runner.run("generate", [sys.executable, GENERATOR, modules, self.path])
        self.entry = self.path / "main.my"
        self.edited_module = self.path / f"p{modules // 2 // 100}.my"
        self.seen = {digest(self.edited_module)}

    def edit(self):
        self.serial += 1
        number = self.modules // 2
        self.runner.run("edit-one-function", [sys.executable, GENERATOR, self.modules,
                                             self.path, "--edit", number])
        original = 7 + number % 13 + 1000
        multiplier = 7 + number % 13 + 1000 * self.serial
        source = self.edited_module.read_text()
        needle = f"out.append((j * {original}) % 101)"
        assert source.count(needle) == 1
        self.edited_module.write_text(source.replace(needle, f"out.append((j * {multiplier}) % 101)"))
        identity = digest(self.edited_module)
        assert identity not in self.seen, "a previous source version was replayed"
        self.seen.add(identity)
        return {"function": f"m{number}_build", "source": str(self.edited_module),
                "multiplier": multiplier, "sha256": identity}


def edited_unit(trace, source):
    candidates = [item for item in trace["zig_cc"]
                  if item["compilation"] and "-O3" in item["argv"] and item["llvm_inputs"]]
    if len(candidates) == 1:
        return candidates[0]
    # C's machine report may be a record itself or contain units in one record.
    units = []
    for report in trace["records"]:
        units.extend(report.get("units", []))
        if "source_path" in report:
            units.append(report)
    paths = {str(Path(unit["llvm_path"]).resolve()) for unit in units
             if "llvm_path" in unit and Path(unit.get("source_path", "")).name == source.name}
    matching = [item for item in candidates
                if any(str(Path(path).resolve()) in paths for path in item["llvm_inputs"])]
    return matching[0] if len(matching) == 1 else None


def build_command(compiler, role, project, output, cache, mode, extras):
    command = [compiler, "build", project.entry, "-o", output, "--cache-dir", cache]
    if mode == "release":
        command.append("--release")
    command.extend(extras if role == "core" else ["--timings=json"])
    return command


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core", type=Path, required=True)
    parser.add_argument("--old", type=Path, required=True)
    parser.add_argument("--host-mode", choices=["ReleaseFast", "ReleaseSafe", "Debug"], required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--sizes", type=int, nargs="+", default=[120, 1200, 2400, 4800])
    parser.add_argument("--roles", nargs="+", choices=["old", "core"], default=["old", "core"])
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--parallel-size", type=int, default=4800)
    parser.add_argument("--parallel-workers", type=int, default=16)
    parser.add_argument("--core-extra", action="append", default=[])
    parser.add_argument("--timeout", type=float, default=1200)
    args = parser.parse_args()
    if set(os.sched_getaffinity(0)) & {2, 3, 10, 11}:
        parser.error("launch through scripts/build-slot.sh build")
    if args.rounds < 1:
        parser.error("at least one fresh edit is required")
    args.evidence, args.work = args.evidence.resolve(), args.work.resolve()
    args.evidence.mkdir(parents=True, exist_ok=False)
    args.work.mkdir(parents=True, exist_ok=False)
    compilers = {role: getattr(args, role).resolve() for role in ("old", "core")}
    runner = Runner(args.evidence, args.timeout)
    summary = {"schema": "s4-devloop-v1", "host_mode": args.host_mode,
               "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
               "compilers": {role: {"path": str(path), "sha256": digest(path)} for role, path in compilers.items()},
               "rows": [], "parallel": [], "gates": []}

    def publish():
        (args.evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")

    environment = dict(os.environ, MYLANG_JOBS="1", MYL_CORE_BUILD_REPORT="1")
    for size in args.sizes:
        project = Project(runner, args.work, size)
        row = {"modules": size, "lines": sum(len(p.read_text().splitlines()) for p in project.path.glob("*.my")),
               "roles": {}}
        commands = {}
        for role in args.roles:
            row["roles"][role] = {}
            for mode in ("debug", "release"):
                cache = args.work / f"cache-{size}-{role}-{mode}"
                output = args.work / f"out-{size}-{role}-{mode}"
                command = build_command(compilers[role], role, project, output, cache, mode, args.core_extra)
                commands[role, mode] = command
                data = row["roles"][role][mode] = {"edits": []}
                data["cold"] = runner.run(f"{size}-{role}-{mode}-cold", command, environment, True)
                data["unchanged"] = runner.run(f"{size}-{role}-{mode}-unchanged", command, environment, True)
                data["unchanged_trace"] = runner.run(f"{size}-{role}-{mode}-unchanged-trace", command, environment, True, True)
                if role == "core":
                    summary["gates"].append({"target": "unchanged has zero zig cc", "size": size, "mode": mode,
                                             "passed": not data["unchanged_trace"]["zig_cc"]})
        for _ in range(args.rounds):
            edit = project.edit()
            for (role, mode), command in commands.items():
                receipt = runner.run(f"{size}-{role}-{mode}-edit", command, environment, True)
                receipt["edit"] = edit
                row["roles"][role][mode]["edits"].append(receipt)
        for role, modes in row["roles"].items():
            for mode, data in modes.items():
                data["edit_seconds"] = statistics.median(item["seconds"] for item in data["edits"])
                if role == "core" and size == 1200 and mode == "debug":
                    summary["gates"].append({"target": "48k debug edit <=2s", "passed": data["edit_seconds"] <= 2})
        if "core" in args.roles:
            edit = project.edit()
            trace = runner.run(f"{size}-core-release-edit-trace", commands["core", "release"], environment, True, True)
            trace["edit"] = edit
            unit = edited_unit(trace, project.edited_module)
            row["edited_unit_trace"] = trace
            if unit:
                replay = unit["argv"][:]
                output_index = replay.index("-o") + 1
                replay[output_index] = str(args.work / f"unit-{size}-O3.o")
                isolated = dict(environment, ZIG_LOCAL_CACHE_DIR=str(args.work / f"unit-{size}-fresh-zig"))
                unit_receipt = runner.run(f"{size}-edited-unit-O3", replay, isolated, True)
                row["edited_unit_O3"] = unit_receipt
                seconds = row["roles"]["core"]["release"]["edit_seconds"]
                summary["gates"].append({"target": "release edit <=1.5*unitO3+1s", "size": size,
                                         "limit": 1.5 * unit_receipt["seconds"] + 1,
                                         "passed": seconds <= 1.5 * unit_receipt["seconds"] + 1})
            else:
                summary["gates"].append({"target": "release edit identifies edited unit", "size": size,
                                         "passed": False, "reason": "no unique source-to-unit mapping in process trace/report"})
        summary["rows"].append(row)
        publish()
        print(json.dumps({"size": size, "lines": row["lines"], "roles": {role: {mode: data["edit_seconds"] for mode, data in modes.items()} for role, modes in row["roles"].items()}}), flush=True)
    if args.parallel_size:
        project = Project(runner, args.work / "parallel", args.parallel_size)
        parallel = dict(environment, MYLANG_JOBS=str(args.parallel_workers))
        command = build_command(compilers["core"], "core", project, args.work / "parallel-out",
                                args.work / "parallel-cache", "release", args.core_extra)
        receipt = runner.run("192k-core-release-cold-parallel", command, parallel)
        receipt.update(modules=args.parallel_size, workers=args.parallel_workers,
                       affinity=sorted(os.sched_getaffinity(0)))
        summary["parallel"].append(receipt)
        if args.parallel_size == 4800 and args.parallel_workers == 16:
            summary["gates"].append({"target": "192k cold release 16 workers <=60s", "passed": receipt["seconds"] <= 60})
    summary["qualified"] = all(item["passed"] for item in summary["gates"])
    publish()
    return 0 if summary["qualified"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Capture static and dynamic evidence; time only already-built ordinary binaries."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import resource
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
METRICS = (
    "allocs", "alloc_bytes", "frees", "free_bytes", "peak_live_bytes",
    "live_bytes_at_exit", "list_grows", "list_grow_bytes", "reallocs",
    "realloc_added_bytes", "realloc_moves", "realloc_moved_bytes",
    "list_copies", "list_copy_bytes", "runtime_retains", "runtime_releases",
    "shared_retains", "shared_releases", "share_marks", "share_bytes",
)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + "\n")


def invoke(argv, prefix, env=None, status=0, expected=None, error=None):
    usage_before = resource.getrusage(resource.RUSAGE_CHILDREN)
    started = time.monotonic()
    result = subprocess.run(list(map(str, argv)), cwd=ROOT, env=env,
                            capture_output=True, timeout=300)
    elapsed = time.monotonic() - started
    usage_after = resource.getrusage(resource.RUSAGE_CHILDREN)
    Path(str(prefix) + ".stdout").write_bytes(result.stdout)
    Path(str(prefix) + ".stderr").write_bytes(result.stderr)
    write(str(prefix) + ".command.json", {"argv": list(map(str, argv)),
          "status": result.returncode, "wall_seconds": elapsed,
          "user_seconds": usage_after.ru_utime - usage_before.ru_utime,
          "system_seconds": usage_after.ru_stime - usage_before.ru_stime,
          "involuntary_context_switches": usage_after.ru_nivcsw - usage_before.ru_nivcsw,
          "minor_faults": usage_after.ru_minflt - usage_before.ru_minflt})
    if result.returncode != status or (expected is not None and result.stdout != expected):
        raise RuntimeError(f"unexpected result: {prefix}: {result.returncode}, {result.stdout!r}")
    if error is not None and error not in result.stderr:
        raise RuntimeError(f"missing expected trap: {prefix}")
    if status == 0 and expected is not None and result.stderr:
        raise RuntimeError(f"unexpected stderr (including leak report): {prefix}")
    return result, elapsed


def oracle(rounds, seed, size):
    # Independent periodic sum of the mathematical workload, without a list allocation.
    period = [sum((j + 1) * ((seed + batch + j * 13) % 1009)
                  for j in range(size)) for batch in range(1009)]
    full, tail = divmod(rounds, len(period))
    return f"{(full * sum(period) + sum(period[:tail])) % 1000000007}\n".encode()


def programs(rounds):
    cases = [
        (mode, [mode, str(rounds), "7", "16"], oracle(rounds, 7, 16), 0, None)
        for mode in ("bounded", "local", "unbounded")
    ]
    return {
        "workload": (HERE / "workload.my", cases),
        "v_loops": (ROOT / "test/core/v_loops.my", [
            ("search", [], b"2 -1 -1\n45 0 30 0\n61 0\n", 0, None)]),
        "f1_overflow": (ROOT / "test/core/f1_overflow.my", [
            ("sum", ["unbounded"], b"6\n", 0, None),
            ("trap", ["huge"], b"", 1, b"R_OVERFLOW")]),
        "rc_stack": (ROOT / "test/core/rc_stack.my", [
            ("existing", ["a", "b", "c", "d"], b"475 16 3\n", 0, None)]),
        "alloc_churn": (ROOT / "bench/parity/micro/alloc_churn.my", [
            ("existing", [], (ROOT / "bench/parity/micro/alloc_churn.expected").read_bytes(), 0, None)]),
    }


def counts_summary(document):
    return {
        "totals": {k: document["totals"].get(k, 0) for k in METRICS},
        "kinds": {k: document["kinds"].get(k, {}) for k in (
            "retain", "release", "release_unique", "unique_test", "list_copy", "record_copy")},
        "functions": [{k: row.get(k, 0) for k in ("name", "calls") + METRICS
                       if k not in ("peak_live_bytes", "live_bytes_at_exit")}
                      for row in document["functions"]],
    }


def capture(args):
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    compiler = args.compiler.resolve()
    compiler_tree = args.compiler_source_tree.resolve()
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=compiler_tree, text=True).strip()
    compiler_files = [p for folder in ("src", "docs") for p in (compiler_tree / folder).rglob("*") if p.is_file()]
    compiler_files += [compiler_tree / name for name in ("build.zig", "build.zig.zon")]
    sources = {str(path.relative_to(compiler_tree)): sha(path) for path in sorted(compiler_files)}
    write(out / "compiler-sources.json", sources)
    env = dict(os.environ, ZIG=str(args.zig.resolve()), MYLANG_ZIG=str(args.zig.resolve()))
    result = {"version": "borrow-stack-capture-v1", "compiler": str(compiler),
              "compiler_sha256": sha(compiler), "zig": str(args.zig.resolve()),
              "compiler_source_tree": str(compiler_tree), "compiler_source_revision": revision,
              "compiler_source_manifest_sha256": sha(out / "compiler-sources.json"),
              "zig_sha256": sha(args.zig), "rounds": args.rounds, "programs": {}}
    write(out / "capture.json", result)
    for name, (source, cases) in programs(args.rounds).items():
        raw = out / name
        raw.mkdir()
        common = [compiler, "build", source, "--zig", args.zig, "--cache-dir", out / "cache"]
        # The static report is after Core inlining/facts/ownership; LLVM remarks are separate.
        cost, _ = invoke([compiler, "cost", source, "--json"], raw / "cost", env)
        static = json.loads(cost.stdout)
        record = {"source": str(source.relative_to(ROOT)), "source_sha256": sha(source),
                  "static_totals": static["totals"], "static_functions": static["functions"],
                  "binaries": {}, "runs": {}}
        for mode, flags in (("plain", []), ("counted", ["--counters"]), ("verify", ["--verify-facts"])):
            binary = raw / mode
            extra = ["--emit-llvm", raw / "plain.ll"] if mode == "plain" else []
            invoke(common + ["--release", "-o", binary] + flags + extra, raw / f"build-{mode}", env)
            record["binaries"][mode] = {"path": str(binary), "sha256": sha(binary)}
            for case, argv, expected, status, error in cases:
                prefix = raw / f"{mode}-{case}"
                running = dict(env, MYL_CORE_LEAKCHECK="1", MYLANG_COUNTERS=str(prefix) + ".json")
                ran, _ = invoke([binary] + argv, prefix, running, status, expected, error)
                entry = record["runs"].setdefault(case, {"args": argv, "stdout": expected.decode(), "status": status})
                entry[mode] = {"stdout_sha256": hashlib.sha256(ran.stdout).hexdigest(),
                               "stderr": ran.stderr.decode(errors="replace")}
                if mode == "counted":
                    entry[mode]["counters"] = counts_summary(json.loads(Path(str(prefix) + ".json").read_text()))
        result["programs"][name] = record
        write(out / "capture.json", result)
        print(f"captured {name}", flush=True)


def timing(args):
    base = json.loads(args.baseline.read_text())
    candidate = json.loads(args.candidate.read_text())
    if base["rounds"] != candidate["rounds"]:
        raise RuntimeError("mismatched workload sizes")
    for name in base["programs"]:
        if base["programs"][name]["source_sha256"] != candidate["programs"][name]["source_sha256"]:
            raise RuntimeError("mismatched source")
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ)
    for name in ("MYLANG_COUNTERS", "MYL_CORE_LEAKCHECK"):
        env.pop(name, None)
    result = {"version": "borrow-stack-timing-v1", "cpu": args.cpu,
              "repeats": args.repeats, "clock": "whole-process wall time; fresh process per sample",
              "rounds": args.rounds,
              "load_average": os.getloadavg(),
              "controller_affinity": sorted(os.sched_getaffinity(0)),
              "smt_siblings": Path(f"/sys/devices/system/cpu/cpu{args.cpu}/topology/thread_siblings_list").read_text().strip(),
              "baseline_compiler_sha256": base["compiler_sha256"],
              "candidate_compiler_sha256": candidate["compiler_sha256"], "cases": {}}
    for case in ("bounded", "local", "unbounded"):
        samples = {"baseline": [], "candidate": []}
        for turn in range(args.repeats + 1):
            order = (("baseline", base), ("candidate", candidate))
            if turn % 2:
                order = tuple(reversed(order))
            for label, arm in order:
                program = arm["programs"]["workload"]
                binary = program["binaries"]["plain"]
                if sha(binary["path"]) != binary["sha256"]:
                    raise RuntimeError("binary changed")
                argv = [case, str(args.rounds), "7", "16"]
                _, elapsed = invoke(["taskset", "-c", str(args.cpu), binary["path"]] + argv,
                                    out / f"{case}-{turn}-{label}", env=env,
                                    expected=oracle(args.rounds, 7, 16))
                if turn:
                    samples[label].append(elapsed)
        ratios = [c / b for b, c in zip(samples["baseline"], samples["candidate"])]
        result["cases"][case] = {"samples_seconds": samples,
            "paired_ratios": ratios, "median_candidate_over_baseline": statistics.median(ratios),
            "paired_ratio_range": [min(ratios), max(ratios)]}
        write(out / "timing.json", result)
        print(f"timed {case}", flush=True)


def census(args):
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    compiler = args.compiler.resolve()
    env = dict(os.environ, ZIG=str(args.zig.resolve()), MYLANG_ZIG=str(args.zig.resolve()))
    result = {"version": "borrow-stack-census-v1", "compiler_sha256": sha(compiler), "programs": {}}
    for name in ("micro/records", "micro/list_append_sum", "micro/dict_count",
                 "suite/binary_trees_recursive", "suite/text_ops", "suite/nbody"):
        source = ROOT / "bench/parity" / (name + ".my")
        cost, _ = invoke([compiler, "cost", source, "--json"], out / name.replace("/", "-"), env)
        static = json.loads(cost.stdout)
        result["programs"][name] = {"source_sha256": sha(source), "totals": static["totals"],
                                     "functions": static["functions"]}
        write(out / "census.json", result)
        print(f"censused {name}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    take = commands.add_parser("capture")
    take.add_argument("--compiler", type=Path, required=True)
    take.add_argument("--compiler-source-tree", type=Path, required=True)
    take.add_argument("--zig", type=Path, required=True)
    take.add_argument("--output", type=Path, required=True)
    take.add_argument("--rounds", type=int, default=1000000)
    timed = commands.add_parser("timing")
    timed.add_argument("--baseline", type=Path, required=True)
    timed.add_argument("--candidate", type=Path, required=True)
    timed.add_argument("--output", type=Path, required=True)
    timed.add_argument("--cpu", type=int, required=True)
    timed.add_argument("--repeats", type=int, default=7)
    timed.add_argument("--rounds", type=int, default=5000000)
    scan = commands.add_parser("census")
    scan.add_argument("--compiler", type=Path, required=True)
    scan.add_argument("--zig", type=Path, required=True)
    scan.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "capture":
        capture(args)
    elif args.command == "census":
        census(args)
    else:
        lock_path = Path.home() / ".cache/mylang/runtime-parity-timing.lock"
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        with lock_path.open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            timing(args)


if __name__ == "__main__":
    main()

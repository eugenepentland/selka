#!/usr/bin/env python3
"""Qualify unchanged fuzz harnesses against the frozen Wave A compiler.

Run through scripts/build-slot.sh build. Each job owns its temp/frontend/Zig
caches. Harness comparisons stay authoritative; this wrapper independently
rejects crashes, timeouts, leaks, fact failures and incomplete qualification.
"""
import argparse
from contextlib import redirect_stdout
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[4]
HARNESSES = {
    "s0": "experiments/new-core-s0-20261005/fuzz.py",
    "s1": "experiments/new-core-s1-20261005/fuzz.py",
    "rc": "experiments/new-core-s1-20261005/lane-o/rc_fuzz.py",
    "rebinding": "experiments/new-core-s2-20261005/wave-a/fuzz_rebinding.py",
    "iteration": "experiments/new-core-s2-20261005/wave-b/fuzz_iteration.py",
    "dict": "experiments/new-core-s2-20261005/wave-b/s2-d/fuzz_dict.py",
}


class QualificationFailure(Exception):
    pass


class Tee(io.StringIO):
    def __init__(self, stream):
        super().__init__()
        self.stream = stream

    def write(self, text):
        self.stream.write(text)
        self.stream.flush()
        return super().write(text)


class Monitor:
    def __init__(self, args, original_run):
        self.args = args
        self.original_run = original_run
        self.executables = {}
        self.cases = {}
        self.failures = []
        self.native_runs = 0
        self.started = time.monotonic()

    def retain(self, source, detail):
        retained = None
        if source is not None and source.is_file():
            directory = self.args.evidence / "failures"
            directory.mkdir(parents=True, exist_ok=True)
            digest = hashlib.sha256(source.read_bytes()).hexdigest()[:12]
            retained = directory / f"{source.stem}-{digest}.my"
            shutil.copyfile(source, retained)
            detail["retained_source"] = str(retained)
        self.failures.append(detail)
        return retained

    def fail(self, source, kind, argv, **details):
        retained = self.retain(source, {"kind": kind, "command": argv, **details})
        raise QualificationFailure(f"{kind}: {argv!r}; retained source: {retained}")

    def run(self, argv, *arguments, **options):
        argv = list(map(str, argv))
        building = len(argv) > 2 and argv[1] == "build"
        source = Path(argv[2]) if building else self.executables.get(argv[0])
        if building:
            if source not in self.cases:
                self.cases[source] = {"old": False, "core": set()}
                if len(self.cases) % 25 == 0:
                    print(f"qualification progress: {self.args.kind}: seen={len(self.cases)} elapsed={time.monotonic() - self.started:.2f}s", flush=True)
            if "-o" in argv:
                self.executables[argv[argv.index("-o") + 1]] = source
            # RC's old build omitted --cache-dir; every job still needs a private one.
            if "--cache-dir" not in argv:
                tool = "old" if Path(argv[0]).name == "mylang" else "core"
                argv += ["--cache-dir", str(self.args.cache_root / f"frontend-{tool}")]
        timeout = 60 if building else 30
        options["timeout"] = min(options.get("timeout") or timeout, timeout)
        try:
            result = self.original_run(argv, *arguments, **options)
        except subprocess.TimeoutExpired as error:
            self.fail(source, "compile_timeout" if building else "native_timeout", argv, timeout=options["timeout"], stderr=str(error.stderr or ""))
        except OSError as error:
            self.fail(source, "child_launch_failed", argv, reason=str(error))
        if result.returncode < 0:
            self.fail(source, "compiler_crash" if building else "native_crash", argv, returncode=result.returncode, stderr=result.stderr)
        if building:
            old = Path(argv[0]).name == "mylang"
            if result.returncode:
                kind = "old_rejected" if old else "core_refused" if "E_CORE_UNSUPPORTED" in result.stderr else "core_build_failed"
                self.retain(source, {"kind": kind, "command": argv, "returncode": result.returncode, "stderr": result.stderr})
            elif old:
                self.cases[source]["old"] = True
            else:
                mode = "verify" if "--verify-facts" in argv else "release" if "--release" in argv else "debug"
                self.cases[source]["core"].add(mode)
        else:
            self.native_runs += 1
            if "leakcheck" in result.stderr or re.search(r"leak: \d+ blocks live", result.stderr):
                self.fail(source, "leak", argv, returncode=result.returncode, stderr=result.stderr)
            if "R_CORE_FACT" in result.stderr:
                self.fail(source, "fact_failure", argv, returncode=result.returncode, stderr=result.stderr)
            # These generators' main returns are 0..6; language traps exit 1.
            if result.returncode > 6:
                self.fail(source, "unexpected_native_exit", argv, returncode=result.returncode, stderr=result.stderr)
        return result


def summary_of(output):
    summaries = []
    for line in output.splitlines():
        values = {key: int(value) for key, value in re.findall(r"\b(\w+)=(\d+)\b", line)}
        if "cases" in values and "compared" in values and "mismatch" in values:
            summaries.append(values)
    return summaries


def qualify(args, monitor, status, output, error):
    summaries = summary_of(output)
    accepted = sum(case["old"] and case["core"] == {"debug", "release", "verify"} for case in monitor.cases.values())
    stats = summaries[0] if len(summaries) == 1 else {}
    expected = args.cases * (9 if args.kind == "rc" else 15)
    counts = {key: sum(failure["kind"] == key for failure in monitor.failures)
              for key in ("old_rejected", "core_refused", "core_build_failed")}
    complete = len(monitor.cases) == args.cases and accepted == args.cases and stats.get("cases") == args.cases and stats.get("compared") == expected
    clean = not monitor.failures and not stats.get("mismatch") and not stats.get("fact") and not stats.get("old_rejected", stats.get("rejected", 0)) and not stats.get("new_refused", stats.get("refused", 0))
    return {
        "kind": args.kind, "cases_requested": args.cases, "seed": args.seed,
        "cases_seen": len(monitor.cases), "accepted": accepted, **counts,
        "comparisons_expected": expected, "native_runs": monitor.native_runs,
        "harness": stats, "harness_status": status, "complete": complete,
        "qualified": status == 0 and complete and clean and error is None,
        "error": error, "failures": monitor.failures,
        "elapsed_seconds": time.monotonic() - monitor.started,
        "cache_root": str(args.cache_root), "tmpdir": os.environ["TMPDIR"],
        "saved_sources": str(args.cache_root / "sources"),
        "zig_local_cache": os.environ["ZIG_LOCAL_CACHE_DIR"],
        "affinity": sorted(os.sched_getaffinity(0)),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kind", choices=HARNESSES, required=True)
    parser.add_argument("--harness", type=Path, help="Override the generator for this feature kind")
    parser.add_argument("--mylang", type=Path, default=ROOT / "zig-out/bin/mylang")
    parser.add_argument("--core", type=Path, default=ROOT / "zig-out/bin/mylang-core")
    parser.add_argument("--cases", type=int, default=200)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--cache-root", type=Path, required=True)
    args = parser.parse_args()
    args.evidence, args.cache_root = args.evidence.resolve(), args.cache_root.resolve()
    args.evidence.mkdir(parents=True, exist_ok=True)
    for directory in (args.cache_root / "tmp", args.cache_root / "zig", args.cache_root / "sources"):
        directory.mkdir(parents=True, exist_ok=True)
    os.environ.update(TMPDIR=str(args.cache_root / "tmp"),
                      ZIG_LOCAL_CACHE_DIR=str(args.cache_root / "zig"),
                      ZIG_GLOBAL_CACHE_DIR="/home/epentland/ai/canopy/.zig-global-cache",
                      MYL_CORE_LEAKCHECK="1")
    if set(os.sched_getaffinity(0)) & {2, 3, 10, 11}:
        raise SystemExit("launch through scripts/build-slot.sh build; reserved CPUs must be excluded")
    harness_path = args.harness.resolve() if args.harness else ROOT / HARNESSES[args.kind]
    spec = importlib.util.spec_from_file_location("fuzz_harness", harness_path)
    harness = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(harness)
    original_run = subprocess.run
    monitor = Monitor(args, original_run)
    arguments = [str(harness_path), "--cases", str(args.cases), "--seed", str(args.seed),
                 "--keep", str(args.cache_root / "sources"),
                 "--mylang", str(args.mylang), "--core", str(args.core)]
    if args.kind in ("s1", "rebinding", "iteration"):
        arguments += ["--features", "all" if args.kind == "s1" else "mut,records,alias"]
    sys.argv = arguments
    output = Tee(sys.stdout)
    status, error = 1, None
    subprocess.run = monitor.run
    try:
        with redirect_stdout(output):
            status = harness.main()
    except (QualificationFailure, SystemExit) as failure:
        error = str(failure)
        print(f"qualification failed: {error}", file=sys.stderr)
    except Exception as failure:
        error = f"{type(failure).__name__}: {failure}"
        print(f"qualification failed: {error}", file=sys.stderr)
    finally:
        subprocess.run = original_run
    report = qualify(args, monitor, status, output.getvalue(), error)
    (args.evidence / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    (args.evidence / "harness.txt").write_text(output.getvalue())
    print("qualification " + json.dumps({key: report[key] for key in ("kind", "qualified", "accepted", "old_rejected", "core_refused", "core_build_failed", "elapsed_seconds")}))
    return 0 if report["qualified"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

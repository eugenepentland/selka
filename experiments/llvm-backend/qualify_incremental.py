#!/usr/bin/env python3
"""Compile and recompile cost for the QBE and LLVM arms beside the Zig reference.

`bench.py` already defines the series this needs, and it defines it well: for
each arm it deletes the cache and builds (cold), builds again with nothing
changed (warm), rewrites one constant in the printer and builds (tweak), then
deletes only the cache and builds once more (project-cold). The mylang and Zig
tweak anchors are the same constant in each language, so the guest edit is the
same size on every arm and the comparison is not measuring differently sized
edits.

The one thing `bench.py` cannot do is vary the backend: its mylang series always
uses the bundled QBE. This reuses it for the Zig arm verbatim and runs the same
series for each mylang backend, so all arms share one definition of cold, warm
and tweak rather than each carrying its own.

    qualify_incremental.py [--rounds N] [--arms ...] [--json OUT]

Cold is the "compilation time" figure and warm/tweak are the "recompilation
after a change" figures. Every arm builds the same entry, the sexpr-port
benchmark, in ReleaseFast.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import statistics
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(REPO / "experiments" / "sexpr-port" / "bench"))

import bench  # noqa: E402  (the path above is what makes this importable)

ADAPTER = HERE / "qbe_llvm.py"
#: arm -> the tool handed to `--qbe`, or None for the bundled backend.
ARMS = {"qbe": (None, None), "llvm-o2": (str(ADAPTER), "-O2"), "llvm-o3": (str(ADAPTER), "-O3")}


def my_build_arm(mode: str, cache: Path, out: Path, tool: str | None, level: str | None) -> dict:
    """One mylang build, optionally through the LLVM adapter at a chosen level."""
    command = [str(bench.MYLANG), "build", "experiments/sexpr-port/main.my", "-o", str(out),
               "--mode", mode, f"--cache-dir={cache}", "--report"]
    if tool is not None:
        command.append(f"--qbe={tool}")
    # The adapter reads its optimize level from the environment rather than from
    # a command-line flag, which is also how measure.py selects -O2 and -O3.
    previous = os.environ.get("MYLANG_QBE_LLVM_OPT")
    if level is not None:
        os.environ["MYLANG_QBE_LLVM_OPT"] = level
    try:
        seconds, proc = bench.run_timed(command, cwd=bench.REPO)
    finally:
        if previous is None:
            os.environ.pop("MYLANG_QBE_LLVM_OPT", None)
        else:
            os.environ["MYLANG_QBE_LLVM_OPT"] = previous
    if proc.returncode != 0:
        raise SystemExit(f"mylang build failed ({tool or 'qbe'}):\n{proc.stdout}\n{proc.stderr}")
    report = json.loads(proc.stdout.strip().splitlines()[-1]) if proc.stdout.strip() else {}
    return {
        "seconds": seconds,
        "frontend_seconds": report.get("frontend_seconds"),
        "codegen_seconds": report.get("codegen_seconds"),
        "link_seconds": report.get("link_seconds"),
        "compiled_functions": report.get("compiled_functions"),
        "reused_functions": report.get("reused_functions"),
    }


def my_series_arm(mode: str, reps: int, arm: str, work: Path) -> dict:
    """The cold/warm/tweak/project-cold series for one mylang backend."""
    tool, level = ARMS[arm]
    cache = work / f"my-cache-{arm}-{mode}"
    out = work / f"my-{arm}-{mode}"
    printer = bench.PORT / "sexpr" / "printer.my"
    original = printer.read_text()
    assert bench.TWEAK_OLD in original, "mylang tweak anchor missing"
    cold, cold_local, warm, tweak = [], [], [], []
    for _ in range(reps):
        shutil.rmtree(cache, ignore_errors=True)
        shutil.rmtree(out, ignore_errors=True)
        cold.append(my_build_arm(mode, cache, out, tool, level))
        warm.append(my_build_arm(mode, cache, out, tool, level))
        printer.write_text(original.replace(bench.TWEAK_OLD, bench.TWEAK_NEW, 1))
        try:
            tweak.append(my_build_arm(mode, cache, out, tool, level))
        finally:
            printer.write_text(original)
        # Project-cold with the toolchain already warm: mylang shares no guest
        # toolchain cache, so this repeats the cold path by construction.
        shutil.rmtree(cache, ignore_errors=True)
        cold_local.append(my_build_arm(mode, cache, out, tool, level))
    assert printer.read_text() == original, "mylang tweak did not revert"
    return {
        "cold": cold, "cold_local": cold_local, "warm": warm, "tweak": tweak,
        "binary": str(out),
        "source_lines": sum(len(p.read_text().splitlines()) for p in sorted((bench.PORT / "sexpr").glob("*.my"))),
    }


def zig_build(mode: str, cache: Path, global_cache: Path, out: Path) -> dict:
    """One Zig reference build with explicit cache roots."""
    env = dict(os.environ, ZIG_LOCAL_CACHE_DIR=str(cache), ZIG_GLOBAL_CACHE_DIR=str(global_cache))
    seconds, proc = bench.run_timed([bench.ZIG, "build", f"-Doptimize={mode}", "-p", str(out)],
                                    cwd=bench.ZIG_BENCH, env=env)
    if proc.returncode != 0:
        raise SystemExit(f"zig build failed ({mode}):\n{proc.stdout}\n{proc.stderr}")
    return {"seconds": seconds}


def zig_series_arm(mode: str, reps: int, work: Path) -> dict:
    """The same series for the Zig reference.

    `bench.zig_series` reads its cache roots from that module's own `WORK`
    global. Called from here that global no longer names the directories the
    probe removes, so its first build of every round found the prefix already
    installed and reported the *warm* time as the cold one — 0.016 s for a build
    that actually takes 73 s. This spells the paths out instead, so what is
    deleted is what is built.
    """
    cache = work / f"zig-cache-{mode}"
    global_cache = work / f"zig-global-{mode}"
    out = work / f"zig-{mode}"
    printer = bench.ZIG_BENCH / "src" / "sexpr" / "printer.zig"
    original = printer.read_text()
    assert bench.ZIG_TWEAK_OLD in original, "zig tweak anchor missing"
    cold, cold_local, warm, tweak = [], [], [], []
    for _ in range(reps):
        shutil.rmtree(cache, ignore_errors=True)
        shutil.rmtree(global_cache, ignore_errors=True)
        shutil.rmtree(out, ignore_errors=True)
        cold.append(zig_build(mode, cache, global_cache, out))
        warm.append(zig_build(mode, cache, global_cache, out))
        printer.write_text(original.replace(bench.ZIG_TWEAK_OLD, bench.ZIG_TWEAK_NEW, 1))
        try:
            tweak.append(zig_build(mode, cache, global_cache, out))
        finally:
            printer.write_text(original)
        # Project-cold, toolchain warm: drop only the local cache, so std stays
        # in the global one. This is the clean-checkout build a developer sees.
        shutil.rmtree(cache, ignore_errors=True)
        cold_local.append(zig_build(mode, cache, global_cache, out))
    assert printer.read_text() == original, "zig tweak did not revert"
    return {
        "cold": cold, "cold_local": cold_local, "warm": warm, "tweak": tweak,
        "binary": str(out / "bin" / "zig-bench"),
        "source_lines": sum(len(p.read_text().splitlines())
                            for p in sorted((bench.ZIG_BENCH / "src").rglob("*.zig"))),
    }


def medians(series: dict) -> dict:
    """Median seconds for each stage, so the plot does not read one lucky run."""
    return {stage: statistics.median(run["seconds"] for run in series[stage])
            for stage in ("cold", "cold_local", "warm", "tweak")}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rounds", type=int, default=3, help="repetitions per arm")
    parser.add_argument("--mode", default="ReleaseFast", help="guest optimize mode")
    parser.add_argument("--arms", default="qbe,llvm-o2,zig", help="comma-separated arms")
    parser.add_argument("--work", default=str(REPO / ".mylang-cache" / "bench" / "incr"))
    parser.add_argument("--mylang", default=str(bench.MYLANG),
                        help="the compiler under test; default the installed one")
    parser.add_argument("--json", dest="out", default=str(REPO / ".mylang-cache" / "bench" / "incremental.json"))
    options = parser.parse_args()
    wanted = [arm.strip() for arm in options.arms.split(",") if arm.strip()]
    # Absolute, because `zig build` runs with `cwd=zig-bench` and would
    # otherwise resolve a relative cache root against that directory while
    # this process deletes it against the repository root: nothing would be
    # cleared, every build would be a no-op, and the warm time would be
    # reported as the cold one.
    work = Path(options.work).resolve()
    work.mkdir(parents=True, exist_ok=True)
    bench.WORK = work
    bench.MYLANG = Path(options.mylang)

    report = {"mode": options.mode, "rounds": options.rounds, "arms": {}, "medians": {},
              "compiler_sha256": __import__("hashlib").sha256(bench.MYLANG.read_bytes()).hexdigest()}
    for arm in wanted:
        print(f"[{arm}] cold/warm/tweak x{options.rounds} ...", flush=True)
        if arm == "zig":
            series = zig_series_arm(options.mode, options.rounds, work)
        elif arm in ARMS:
            series = my_series_arm(options.mode, options.rounds, arm, work)
        else:
            parser.error(f"unknown arm {arm!r}")
        report["arms"][arm] = series
        report["medians"][arm] = medians(series)
        print(f"[{arm}] " + "  ".join(f"{k}={v:.3f}s" for k, v in report["medians"][arm].items()), flush=True)

    Path(options.out).write_text(json.dumps(report, indent=2) + "\n")
    print(f"\nwrote {options.out}")
    header = f"{'arm':<10}{'cold':>10}{'project-cold':>14}{'warm':>10}{'after tweak':>13}"
    print(header)
    print("-" * len(header))
    for arm in wanted:
        row = report["medians"][arm]
        print(f"{arm:<10}{row['cold']:>9.3f}s{row['cold_local']:>13.3f}s{row['warm']:>9.3f}s{row['tweak']:>12.3f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())

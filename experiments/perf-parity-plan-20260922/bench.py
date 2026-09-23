#!/usr/bin/env python3
"""Build, qualify and time mylang against Zig and Rust on matched programs.

A benchmark is a name with ports in one or more source directories:
`<name>.my`, `<name>.zig`, `<name>.rs`, and variants `<name>_<variant>.<ext>`.
Every port of a benchmark must print byte-identical stdout; the harness refuses
to time a benchmark whose arms disagree. Each timing sample is a fresh process
pinned to one CPU with stdout to /dev/null; arms are shuffled inside every round
and nothing is built while anything is timed. Wall time and the child's own CPU
time (user + system, from wait4) are both recorded.

Arms per source file:
  .my   my (mylang build default: ReleaseFast, LLVM O3 + LTO)
        my-unchecked (+ --unchecked), my-qbe (--backend qbe, opt-in)
  .zig  zig-fast (ReleaseFast), zig-safe (ReleaseSafe)
  .rs   rust (-C opt-level=3 codegen-units=1 target-cpu=native panic=abort)
        rust-checked (+ -C overflow-checks=on)
A variant file `<name>_<v>.<ext>` gets `<lang>-<v>` built with that language's
main flags (and `my-<v>-unchecked` when --variants-unchecked is given).

The compiler defaults to this checkout's Debug `zig-out/bin/mylang`: a Debug
and a ReleaseFast compiler emit byte-identical guest binaries, so timing guest
programs never needs a ReleaseFast compiler build (CLAUDE.md, "Measuring guest
programs"). The timing CPU defaults to the first of MYLANG_TIMING_CPUS, which
`scripts/build-slot.sh` keeps free of builds.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import random
import statistics
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
DEFAULT_MYLANG = ROOT / "zig-out/bin/mylang"
sys.path.insert(0, str(ROOT / "bench" / "parity"))
from bench_parity import (OffTimingCpus, busy_fraction, cpu_times,  # noqa: E402
                          default_timing_cpu, shared_core_warning, siblings)
RUSTC = Path.home() / ".cargo/bin/rustc"
ZIG = "zig"
REFERENCE = "zig-fast"

RUST_FLAGS = ["--edition", "2021", "-C", "opt-level=3", "-C", "codegen-units=1",
              "-C", "target-cpu=native", "-C", "panic=abort"]


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def discover(name: str, dirs: list[Path]) -> list[tuple[str, Path, str]]:
    """Return (lang, path, variant) for every port of `name` across `dirs`."""
    found = []
    for d in dirs:
        for ext, lang in ((".my", "my"), (".zig", "zig"), (".rs", "rust")):
            main = d / f"{name}{ext}"
            if main.exists():
                found.append((lang, main, ""))
            for p in sorted(d.glob(f"{name}_*{ext}")):
                variant = p.stem[len(name) + 1:]
                # a benchmark name may itself be a prefix of another benchmark
                if (d / f"{p.stem}.expected").exists() and variant:
                    continue
                found.append((lang, p, variant))
    return found


def arms_for(ports, opts) -> list[dict]:
    arms = []
    for lang, path, variant in ports:
        tag = f"-{variant}" if variant else ""
        if lang == "my":
            arms.append({"arm": f"my{tag}", "lang": lang, "src": path, "flags": []})
            if not variant or opts.variants_unchecked:
                arms.append({"arm": f"my{tag}-unchecked", "lang": lang, "src": path, "flags": ["--unchecked"]})
            if opts.qbe and not variant:
                arms.append({"arm": "my-qbe", "lang": lang, "src": path, "flags": ["--backend", "qbe"]})
        elif lang == "zig":
            arms.append({"arm": f"zig{tag}" if variant else "zig-fast", "lang": lang, "src": path, "flags": ["-O", "ReleaseFast"]})
            if not variant:
                arms.append({"arm": "zig-safe", "lang": lang, "src": path, "flags": ["-O", "ReleaseSafe"]})
        elif lang == "rust":
            arms.append({"arm": f"rust{tag}", "lang": lang, "src": path, "flags": []})
            if not variant:
                arms.append({"arm": "rust-checked", "lang": lang, "src": path, "flags": ["-C", "overflow-checks=on"]})
    if opts.arms:
        wanted = set(opts.arms)
        arms = [a for a in arms if a["arm"] in wanted or a["arm"] == REFERENCE]
    return arms


def build(arm: dict, out: Path, work: Path, mylang: Path) -> dict:
    src = arm["src"]
    if arm["lang"] == "my":
        cmd = [str(mylang), "build", str(src), "-o", str(out), "--cache-dir", str(work / "mycache"), *arm["flags"]]
        cwd = src.parent
    elif arm["lang"] == "zig":
        cmd = [ZIG, "build-exe", src.name, *arm["flags"], f"-femit-bin={out}",
               "--cache-dir", str(work / "zigcache"), "--global-cache-dir", str(work / "zigcache-global")]
        cwd = src.parent
    else:
        cmd = [str(RUSTC), *RUST_FLAGS, *arm["flags"], "-o", str(out), str(src)]
        cwd = src.parent
    t0 = time.perf_counter()
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    return {"cmd": cmd, "ok": p.returncode == 0 and out.exists(), "seconds": time.perf_counter() - t0,
            "stderr": p.stderr[-4000:]}


def run_once(binary: Path, cpu: int, capture: bool = False):
    """Run one fresh pinned process; return (wall_s, cpu_s, stdout_or_None, status)."""
    argv = ["taskset", "-c", str(cpu), str(binary)]
    t0 = time.perf_counter_ns()
    if capture:
        p = subprocess.run(argv, capture_output=True)
        wall = (time.perf_counter_ns() - t0) / 1e9
        return wall, None, p.stdout, p.returncode
    devnull = os.open(os.devnull, os.O_WRONLY)
    try:
        pid = os.posix_spawnp("taskset", argv, os.environ, file_actions=[(os.POSIX_SPAWN_DUP2, devnull, 1)])
        _, status, ru = os.wait4(pid, 0)
    finally:
        os.close(devnull)
    wall = (time.perf_counter_ns() - t0) / 1e9
    return wall, ru.ru_utime + ru.ru_stime, None, os.waitstatus_to_exitcode(status)


def peak_rss_kb(binary: Path, cpu: int) -> int | None:
    p = subprocess.run(["/usr/bin/time", "-f", "%M", "taskset", "-c", str(cpu), str(binary)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    try:
        return int(p.stderr.strip().splitlines()[-1])
    except (ValueError, IndexError):
        return None


def bootstrap_ratio(arm: list[float], ref: list[float], reps: int = 2000, seed: int = 7):
    """Median of paired per-round ratios with a 95% bootstrap interval."""
    pairs = [a / r for a, r in zip(arm, ref) if r > 0]
    if not pairs:
        return None
    rng = random.Random(seed)
    meds = sorted(statistics.median(rng.choices(pairs, k=len(pairs))) for _ in range(reps))
    return {"median": statistics.median(pairs), "lo": meds[int(0.025 * reps)], "hi": meds[int(0.975 * reps) - 1]}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("names", nargs="+", help="benchmark names")
    ap.add_argument("--src", action="append", type=Path, default=[], help="source directory (repeatable)")
    ap.add_argument("--work", type=Path, default=ROOT / ".mylang-cache/perf-parity-bench")
    ap.add_argument("--mylang", type=Path, default=DEFAULT_MYLANG,
                    help="compiler (default: this checkout's Debug zig-out/bin/mylang; run `zig build` first)")
    ap.add_argument("--cpu", type=int, default=default_timing_cpu(),
                    help="timing CPU (default: the first of MYLANG_TIMING_CPUS, else 2)")
    ap.add_argument("--rounds", type=int, default=11)
    ap.add_argument("--warmups", type=int, default=2)
    ap.add_argument("--arms", nargs="*", help="restrict to these arms (the reference is always kept)")
    ap.add_argument("--qbe", action="store_true", help="also build the my-qbe arm")
    ap.add_argument("--variants-unchecked", action="store_true")
    ap.add_argument("--skip-build", action="store_true")
    ap.add_argument("--cf", action="append", default=[], help="time a prebuilt counterfactual arm <work>/<name>.<ARM> (counterfactual.py)")
    ap.add_argument("--json", type=Path, required=True)
    ap.add_argument("--seed", type=int, default=20260922)
    opts = ap.parse_args()
    if not opts.skip_build and not opts.mylang.exists():
        print(f"bench.py: no compiler at {opts.mylang}; run `zig build` in {ROOT} "
              "(a Debug compiler is enough) or pass --mylang PATH", file=sys.stderr)
        return 2
    if opts.cpu not in os.sched_getaffinity(0):
        print(f"bench.py: CPU {opts.cpu} is not available to this process (run benchmarks directly, not through "
              "scripts/build-slot.sh, which keeps the timing CPUs away from its jobs)", file=sys.stderr)
        return 2
    dirs = [d.resolve() for d in (opts.src or [HERE / "suite"])]
    opts.work = opts.work.resolve()
    opts.work.mkdir(parents=True, exist_ok=True)
    rng = random.Random(opts.seed)
    report = {"mylang": str(opts.mylang), "cpu": opts.cpu, "rounds": opts.rounds, "warmups": opts.warmups,
              "started": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "load_start": os.getloadavg(),
              "benchmarks": {}}
    plan = {}
    # build and qualify off the reserved timing CPUs; timing pins itself below
    with OffTimingCpus():
        for name in opts.names:
            ports = discover(name, dirs)
            arms = arms_for(ports, opts)
            if not any(a["arm"] == REFERENCE for a in arms):
                print(f"{name}: no {REFERENCE} arm, skipped", file=sys.stderr)
                continue
            entry = {"arms": {}}
            my_src = next((a["src"] for a in arms if a["arm"] == "my"), None)
            variants = [(v, p) for lang, p, v in ports if lang == "my" and v]
            for cf in opts.cf:
                if (opts.work / f"{name}.{cf}").exists():
                    arms.append({"arm": cf, "lang": "my", "src": my_src, "flags": [], "prebuilt": True})
                for v, p in variants:
                    if (opts.work / f"{name}_{v}.{cf}").exists():
                        arms.append({"arm": f"{v}:{cf}", "lang": "my", "src": p, "flags": [], "prebuilt": True,
                                     "bin": opts.work / f"{name}_{v}.{cf}"})
            for arm in arms:
                out = arm.get("bin") or opts.work / f"{name}.{arm['arm']}"
                arm["bin"] = out
                if arm.get("prebuilt"):
                    entry["arms"][arm["arm"]] = {"src": str(arm["src"]), "build": {"ok": True, "prebuilt": True}}
                elif not opts.skip_build:
                    b = build(arm, out, opts.work, opts.mylang)
                    entry["arms"][arm["arm"]] = {"src": str(arm["src"]), "build": b}
                    if not b["ok"]:
                        print(f"BUILD FAIL {name} {arm['arm']}\n{b['stderr']}", file=sys.stderr)
                else:
                    entry["arms"][arm["arm"]] = {"src": str(arm["src"]), "build": {"ok": out.exists()}}
            # qualify: identical stdout across arms
            outputs = {}
            for arm in arms:
                if not entry["arms"][arm["arm"]]["build"]["ok"]:
                    continue
                _, _, stdout, status = run_once(arm["bin"], opts.cpu, capture=True)
                outputs[arm["arm"]] = (sha(stdout), status, stdout)
            ref = outputs.get(REFERENCE)
            good = []
            for arm in arms:
                o = outputs.get(arm["arm"])
                if o is None:
                    continue
                same = ref is not None and o[0] == ref[0] and o[1] == 0
                entry["arms"][arm["arm"]].update({"stdout_sha256": o[0], "status": o[1], "matches_reference": same})
                if same:
                    good.append(arm)
                    entry["arms"][arm["arm"]]["binary_sha256"] = sha(arm["bin"].read_bytes())
                    entry["arms"][arm["arm"]]["peak_rss_kb"] = peak_rss_kb(arm["bin"], opts.cpu)
                else:
                    print(f"MISMATCH {name} {arm['arm']} status={o[1]}", file=sys.stderr)
            entry["reference_stdout"] = ref[2].decode(errors="replace") if ref else None
            report["benchmarks"][name] = entry
            plan[name] = good
            print(f"{name}: {len(good)} qualified arms: {' '.join(a['arm'] for a in good)}", file=sys.stderr)
    # time: benchmarks in sequence, arms shuffled inside each round
    crowded = shared_core_warning(opts.cpu)
    if crowded:
        print(f"bench.py: warning: {crowded}", file=sys.stderr)
        report["notices"] = [crowded]
    sibling_cpus = siblings(opts.cpu)
    report["siblings"] = sibling_cpus
    for name, good in plan.items():
        entry = report["benchmarks"][name]
        samples = {a["arm"]: {"wall": [], "cpu": []} for a in good}
        before = cpu_times(sibling_cpus)
        for _ in range(opts.warmups):
            for a in good:
                run_once(a["bin"], opts.cpu)
        for _ in range(opts.rounds):
            order = good[:]
            rng.shuffle(order)
            for a in order:
                wall, cpu, _, status = run_once(a["bin"], opts.cpu)
                if status != 0:
                    print(f"RUN FAIL {name} {a['arm']} status={status}", file=sys.stderr)
                samples[a["arm"]]["wall"].append(wall)
                samples[a["arm"]]["cpu"].append(cpu)
        entry["sibling_busy"] = busy_fraction(before, cpu_times(sibling_cpus))
        if (entry["sibling_busy"] or 0) > 0.25:
            print(f"bench.py: warning: {name}: SMT sibling CPU {', '.join(map(str, sibling_cpus))} of timing CPU "
                  f"{opts.cpu} was {entry['sibling_busy']:.0%} busy; its ratios may be off by tens of percent",
                  file=sys.stderr)
        refw = samples[REFERENCE]["wall"]
        refc = samples[REFERENCE]["cpu"]
        for arm, s in samples.items():
            e = entry["arms"][arm]
            e["wall"] = s["wall"]
            e["cpu"] = s["cpu"]
            e["wall_median"] = statistics.median(s["wall"])
            e["cpu_median"] = statistics.median(s["cpu"])
            e["ratio_wall"] = bootstrap_ratio(s["wall"], refw)
            e["ratio_cpu"] = bootstrap_ratio(s["cpu"], refc)
        line = "  ".join(f"{arm}={entry['arms'][arm]['ratio_wall']['median']:.2f}x" for arm in samples)
        print(f"{name}: ref {statistics.median(refw)*1000:.1f} ms | {line}", file=sys.stderr)
        report["load_end"] = os.getloadavg()
        opts.json.parent.mkdir(parents=True, exist_ok=True)
        opts.json.write_text(json.dumps(report, indent=1, default=str))
    opts.json.write_text(json.dumps(report, indent=1, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""The standing mylang/Zig/Rust parity benchmark (`zig build bench-parity`).

Every benchmark is a stem with an `<name>.expected` file in one of the group
directories (`suite/`, `lib/`, `micro/`) and ports beside it: `<name>.my`,
`<name>.zig`, `<name>.rs`, plus variants `<name>_<variant>.<ext>`. The harness

  1. builds every arm (mylang with the compiler under test, Zig with `--zig`,
     Rust with `rustc` when one is installed) before anything is timed;
  2. qualifies each arm: one pinned run whose stdout must equal the
     `.expected` bytes and whose exit status must be 0;
  3. times fresh processes pinned to one CPU with stdout to /dev/null, the arm
     order shuffled inside every round, wall and child CPU time both recorded;
  4. reports each arm as the median of its per-round ratios to `zig-fast`
     (Zig ReleaseFast) with a 95% bootstrap interval, and checks every mylang
     arm against the ratio threshold in `thresholds.json`.

Only ratios are checked, never absolute times: both arms of a ratio ran in the
same round, so a loaded machine slows both. Exit status: 0 pass, 1 a threshold
was exceeded or a mylang arm failed to build or qualify, 2 usage/environment.

Subcommands:
  run          build, qualify, time, check (what `zig build bench-parity` runs)
  rebaseline   rewrite thresholds.json from result JSONs, pooled (a deliberate update)
  table        print a result JSON as the ratio table
"""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import math
import os
import platform
import random
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
GROUPS = ("suite", "lib", "micro")
REFERENCE = "zig-fast"
SCHEMA_RESULT = "mylang-parity-result-v1"
SCHEMA_THRESHOLDS = "mylang-parity-thresholds-v1"
DEFAULT_TOLERANCE = 0.15
MAX_TOLERANCE = 0.50
RUST_FLAGS = ["--edition", "2021", "-C", "opt-level=3", "-C", "codegen-units=1",
              "-C", "target-cpu=native", "-C", "panic=abort"]
# The plan's parity targets (docs/audits/performance-parity-plan-2026-09-22.md §1),
# reported beside the suite's geometric means; they are goals, not gates.
TARGETS = {"my": 1.2, "my-unchecked": 1.1, "worst my": 1.5}


# ---------------------------------------------------------------- discovery

def discover(filters: list[str]) -> list[dict]:
    """Every benchmark whose `group/name` contains one of `filters` (all if none)."""
    found = []
    for group in GROUPS:
        directory = HERE / group
        for expected in sorted(directory.glob("*.expected")):
            name = expected.stem
            key = f"{group}/{name}"
            if filters and not any(f in key for f in filters):
                continue
            found.append({"group": group, "name": name, "dir": directory,
                          "expected": expected.read_bytes(), "ports": ports_of(directory, name)})
    return found


def ports_of(directory: Path, name: str) -> list[tuple[str, Path, str]]:
    """(lang, path, variant) for `name` and its `<name>_<variant>` files."""
    ports = []
    for ext, lang in ((".my", "my"), (".zig", "zig"), (".rs", "rust")):
        main = directory / f"{name}{ext}"
        if main.exists():
            ports.append((lang, main, ""))
        for path in sorted(directory.glob(f"{name}_*{ext}")):
            # A longer benchmark name sharing this prefix has its own `.expected`.
            if (directory / f"{path.stem}.expected").exists():
                continue
            ports.append((lang, path, path.stem[len(name) + 1:]))
    return ports


def arms_for(ports: list[tuple[str, Path, str]], qbe: bool) -> list[dict]:
    """The arms one benchmark builds, named as in the plan's tables."""
    arms = []
    for lang, path, variant in ports:
        if lang == "my":
            if variant:
                arms.append(arm(f"my-{variant}", lang, path, []))
                continue
            arms.append(arm("my", lang, path, []))
            arms.append(arm("my-unchecked", lang, path, ["--unchecked"]))
            if qbe:
                arms.append(arm("my-qbe", lang, path, ["--backend", "qbe"]))
        elif lang == "zig":
            if variant:
                arms.append(arm(f"zig-{variant}", lang, path, ["-O", "ReleaseFast"]))
                continue
            arms.append(arm("zig-fast", lang, path, ["-O", "ReleaseFast"]))
            arms.append(arm("zig-safe", lang, path, ["-O", "ReleaseSafe"]))
        else:
            if variant:
                arms.append(arm(f"rust-{variant}", lang, path, []))
                continue
            arms.append(arm("rust", lang, path, []))
            arms.append(arm("rust-checked", lang, path, ["-C", "overflow-checks=on"]))
    return arms


def arm(name: str, lang: str, src: Path, flags: list[str]) -> dict:
    return {"arm": name, "lang": lang, "src": src, "flags": flags}


# ---------------------------------------------------------------- tools

def find_rustc(explicit: str | None) -> str | None:
    """A working rustc, or None: a rustup shim with no toolchain counts as missing."""
    candidates = [explicit, os.environ.get("RUSTC"), shutil.which("rustc"),
                  str(Path.home() / ".cargo/bin/rustc")]
    for candidate in candidates:
        if not candidate or not Path(candidate).exists():
            continue
        try:
            probe = subprocess.run([candidate, "--version"], capture_output=True, text=True, timeout=60)
        except (OSError, subprocess.TimeoutExpired):
            continue
        if probe.returncode == 0:
            return candidate
    return None


def version_of(argv: list[str]) -> str | None:
    try:
        probe = subprocess.run(argv, capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return None
    text = (probe.stdout or probe.stderr).strip()
    return text.splitlines()[0] if probe.returncode == 0 and text else None


def perf_available() -> bool:
    """Whether `perf stat` can count user-space instructions for this user.

    Needs `kernel.perf_event_paranoid <= 2` (user-only events; the plan asks
    for <= 1 to also count kernel time). Changing it needs root."""
    if shutil.which("perf") is None:
        return False
    try:
        probe = subprocess.run(["perf", "stat", "-x,", "-e", "instructions:u,cycles:u", "--", "true"],
                               capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return probe.returncode == 0 and parse_perf(probe.stderr).get("instructions") is not None


def parse_perf(text: str) -> dict:
    """Sum `perf stat -x,` counts per event, across hybrid PMUs (cpu_core/cpu_atom)."""
    counts: dict[str, int] = {}
    for line in text.splitlines():
        fields = line.split(",")
        if len(fields) < 3 or not fields[0].strip().isdigit():
            continue
        event = fields[2].split("/")[-2] if "/" in fields[2] else fields[2]
        event = event.split(":")[0]
        counts[event] = counts.get(event, 0) + int(fields[0])
    return counts


def siblings(cpu: int) -> list[int]:
    """The other hardware threads of `cpu`'s core (its SMT siblings)."""
    try:
        text = Path(f"/sys/devices/system/cpu/cpu{cpu}/topology/thread_siblings_list").read_text().strip()
    except OSError:
        return []
    found = set()
    for part in text.split(","):
        low, _, high = part.partition("-")
        found.update(range(int(low), int(high or low) + 1))
    return sorted(found - {cpu})


def cpu_times(cpus: list[int]) -> dict[int, tuple[int, int]]:
    """(busy, total) jiffies per CPU from /proc/stat."""
    times = {}
    try:
        lines = Path("/proc/stat").read_text().splitlines()
    except OSError:
        return times
    for line in lines:
        fields = line.split()
        if not fields or not fields[0].startswith("cpu") or fields[0] == "cpu":
            continue
        index = int(fields[0][3:])
        if index in cpus:
            values = [int(v) for v in fields[1:]]
            idle = values[3] + (values[4] if len(values) > 4 else 0)
            times[index] = (sum(values) - idle, sum(values))
    return times


def busy_fraction(before: dict, after: dict) -> float | None:
    busy = sum(after[c][0] - before[c][0] for c in after if c in before)
    total = sum(after[c][1] - before[c][1] for c in after if c in before)
    return round(busy / total, 3) if total > 0 else None


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


# ---------------------------------------------------------------- build

def build(job: dict, tools: dict, work: Path) -> dict:
    src, out = job["src"], job["bin"]
    if out.exists():
        out.unlink()
    if job["lang"] == "my":
        cmd = [tools["mylang"], "build", str(src), "-o", str(out), "--cache-dir", str(work / "mycache"), *job["flags"]]
    elif job["lang"] == "zig":
        cmd = [tools["zig"], "build-exe", src.name, *job["flags"], f"-femit-bin={out}",
               "--cache-dir", str(work / "zigcache"), "--global-cache-dir", str(work / "zigcache-global")]
    else:
        # rustc names its intermediate objects after the crate, beside the output;
        # a crate name per arm keeps two concurrent builds of one source apart.
        crate = f"{job['bench']}_{job['arm']}".replace("-", "_")
        cmd = [tools["rustc"], *RUST_FLAGS, *job["flags"], "--crate-name", crate, "-o", str(out), str(src)]
    started = time.perf_counter()
    try:
        done = subprocess.run(cmd, cwd=src.parent, capture_output=True, text=True, timeout=1800)
        stderr, status = done.stderr, done.returncode
    except subprocess.TimeoutExpired:
        stderr, status = "timed out after 1800 s", -1
    return {"cmd": cmd, "ok": status == 0 and out.exists(), "seconds": round(time.perf_counter() - started, 3),
            "stderr": stderr[-4000:]}


# ---------------------------------------------------------------- running

def run_timed(binary: Path) -> tuple[float, float, int]:
    """One fresh process with stdout to /dev/null: (wall s, child CPU s, exit status).

    The caller has pinned this process to the benchmark CPU; the child inherits it."""
    devnull = os.open(os.devnull, os.O_WRONLY)
    try:
        started = time.perf_counter_ns()
        pid = os.posix_spawn(str(binary), [str(binary)], os.environ,
                             file_actions=[(os.POSIX_SPAWN_DUP2, devnull, 1)])
        _, status, usage = os.wait4(pid, 0)
        wall = (time.perf_counter_ns() - started) / 1e9
    finally:
        os.close(devnull)
    return wall, usage.ru_utime + usage.ru_stime, os.waitstatus_to_exitcode(status)


def run_captured(binary: Path) -> tuple[bytes, int]:
    done = subprocess.run([str(binary)], capture_output=True, timeout=600)
    return done.stdout, done.returncode


def peak_rss_kb(binary: Path) -> int | None:
    if not Path("/usr/bin/time").exists():
        return None
    done = subprocess.run(["/usr/bin/time", "-f", "%M", str(binary)], stdout=subprocess.DEVNULL,
                          stderr=subprocess.PIPE, text=True, timeout=600)
    try:
        return int(done.stderr.strip().splitlines()[-1])
    except (ValueError, IndexError):
        return None


def counters(binary: Path) -> dict | None:
    done = subprocess.run(["perf", "stat", "-x,", "-e", "instructions:u,cycles:u", "--", str(binary)],
                          stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, timeout=600)
    found = parse_perf(done.stderr)
    return found or None


def bootstrap(pairs: list[float], reps: int = 2000, seed: int = 7) -> dict | None:
    """Median of paired per-round ratios with a 95% bootstrap interval."""
    if not pairs:
        return None
    rng = random.Random(seed)
    medians = sorted(statistics.median(rng.choices(pairs, k=len(pairs))) for _ in range(reps))
    return {"median": statistics.median(pairs), "lo": medians[int(0.025 * reps)], "hi": medians[int(0.975 * reps) - 1]}


def paired(arm_samples: list[float], ref_samples: list[float]) -> dict | None:
    return bootstrap([a / r for a, r in zip(arm_samples, ref_samples) if r > 0])


# ---------------------------------------------------------------- thresholds

def load_thresholds(path: Path) -> dict:
    if not path.exists():
        return {"schema": SCHEMA_THRESHOLDS, "benchmarks": {}}
    data = json.loads(path.read_text())
    if data.get("schema") != SCHEMA_THRESHOLDS:
        raise SystemExit(f"bench-parity: {path} is not a {SCHEMA_THRESHOLDS} file")
    return data


def limit_of(entry: dict) -> float:
    return entry["ratio"] * (1.0 + entry["tolerance"])


def check(result: dict, thresholds: dict) -> list[dict]:
    """One verdict per thresholded arm that this run selected."""
    verdicts = []
    for name, bench in result["benchmarks"].items():
        wanted = thresholds.get("benchmarks", {}).get(name, {})
        for arm_name, entry in sorted(wanted.items()):
            data = bench["arms"].get(arm_name)
            if data is None:
                continue  # not selected by --arms
            ratio = data.get("ratio_wall")
            verdict = {"benchmark": name, "arm": arm_name, "baseline": entry["ratio"],
                       "tolerance": entry["tolerance"], "limit": round(limit_of(entry), 4)}
            if ratio is None:
                verdict.update(verdict="unmeasured", reason=data.get("failure", "not timed"))
            else:
                verdict.update(observed=ratio["median"], lo=ratio["lo"], hi=ratio["hi"])
                confirm = (data.get("confirm") or {}).get("ratio_wall")
                if confirm:
                    verdict.update(confirmed=confirm["median"], confirmed_lo=confirm["lo"], confirmed_hi=confirm["hi"])
                if ratio["median"] > verdict["limit"]:
                    verdict["verdict"] = "unconfirmed" if confirm and confirm["median"] <= verdict["limit"] else "regression"
                elif ratio["hi"] < entry["ratio"] * (1.0 - entry["tolerance"]):
                    verdict["verdict"] = "improved"
                else:
                    verdict["verdict"] = "ok"
            verdicts.append(verdict)
    return verdicts


def rebaseline(results: list[dict], thresholds: dict, label: str, tolerance: float, note: str | None = None) -> dict:
    """Thresholds rewritten from one or more result batches of the same compiler.

    Each timed mylang arm's per-round ratios to `zig-fast` are pooled across
    the batches; the pooled median is the baseline ratio. Its tolerance is the
    largest of `tolerance`, twice the upper half-width of the pooled 95%
    interval, and 1.5 times the excess of the slowest batch's median over the
    pooled one, so an arm that was noisy within or between batches does not
    fail on that noise alone (capped at MAX_TOLERANCE). Benchmarks the results
    did not measure keep their entries."""
    first = results[0]
    batch = f"{first['started'][:10]}-cpu{first['cpu']}-{label}"
    thresholds = dict(thresholds)
    thresholds["schema"] = SCHEMA_THRESHOLDS
    thresholds["metric"] = "wall"
    thresholds["reference"] = REFERENCE
    thresholds["default_tolerance"] = tolerance
    # A new baseline supersedes whatever the old one said about itself.
    thresholds.pop("note", None)
    if note:
        thresholds["note"] = note
    batches = dict(thresholds.get("batches", {}))
    batches[batch] = {"label": label, "compiler": first["tools"]["mylang"],
                      "compiler_sha256": first["tools"]["mylang_sha256"], "commit": first.get("commit"),
                      "runs": [{"started": r["started"], "cpu": r["cpu"], "rounds": r["rounds"],
                                "load": [r.get("load_start"), r.get("load_end")]} for r in results]}
    thresholds["batches"] = batches
    pooled: dict[str, dict[str, list[list[float]]]] = {}
    for result in results:
        for name, bench in result["benchmarks"].items():
            ref = bench["arms"].get(REFERENCE, {}).get("wall")
            for arm_name, data in bench["arms"].items():
                if data.get("lang") != "my" or not data.get("wall") or not ref:
                    continue
                pairs = [a / r for a, r in zip(data["wall"], ref) if r > 0]
                pooled.setdefault(name, {}).setdefault(arm_name, []).append(pairs)
    table = {k: dict(v) for k, v in thresholds.get("benchmarks", {}).items()}
    for name, arms in pooled.items():
        entries = {}
        for arm_name, per_batch in arms.items():
            ratio = bootstrap([p for pairs in per_batch for p in pairs])
            if ratio is None:
                continue
            within = 2.0 * (ratio["hi"] - ratio["median"]) / ratio["median"]
            between = 1.5 * (max(statistics.median(p) for p in per_batch) / ratio["median"] - 1.0)
            widened = min(MAX_TOLERANCE, max(tolerance, math.ceil(max(within, between) * 100) / 100))
            entries[arm_name] = {"ratio": round(ratio["median"], 3), "tolerance": widened, "batch": batch}
        if entries:
            table[name] = entries
    thresholds["benchmarks"] = dict(sorted(table.items()))
    order = ("schema", "note", "metric", "reference", "default_tolerance", "batches", "benchmarks")
    return {**{k: thresholds[k] for k in order if k in thresholds},
            **{k: v for k, v in thresholds.items() if k not in order}}


# ---------------------------------------------------------------- report

def cell(bench: dict, arm_name: str) -> str:
    ratio = bench["arms"].get(arm_name, {}).get("ratio_wall")
    return f"{ratio['median']:.2f}" if ratio else ""


def table(result: dict, verdicts: list[dict]) -> str:
    """The ratio table: one row per benchmark, mylang variants folded into one column."""
    by_key = {(v["benchmark"], v["arm"]): v for v in verdicts}
    lines = ["| group | benchmark | zig ms | zig-safe | rust | rust-checked | my | limit | my-unchecked | variants | check |",
             "|---|---|---:|---:|---:|---:|---:|---:|---:|---|---|"]
    for name, bench in result["benchmarks"].items():
        ref = bench["arms"].get(REFERENCE, {})
        ms = f"{ref['wall_median'] * 1000:.1f}" if "wall_median" in ref else ""
        variants = []
        for arm_name, data in bench["arms"].items():
            if data.get("lang") == "my" and arm_name not in ("my", "my-unchecked") and data.get("ratio_wall"):
                variants.append(f"{arm_name[3:]} {data['ratio_wall']['median']:.2f}")
        limit = by_key.get((name, "my"), {}).get("limit")
        marks = []
        for (bench_name, arm_name), verdict in by_key.items():
            if bench_name != name:
                continue
            if verdict["verdict"] == "regression":
                marks.append(f"FAIL {arm_name}")
            elif verdict["verdict"] == "unmeasured":
                marks.append(f"FAIL {arm_name} unmeasured")
            elif verdict["verdict"] == "improved":
                marks.append(f"{arm_name} improved")
            elif verdict["verdict"] == "unconfirmed":
                marks.append(f"{arm_name} noise")
        status = ", ".join(marks) if marks else ("ok" if any(k[0] == name for k in by_key) else "no threshold")
        if bench.get("failure"):
            status = bench["failure"]
        lines.append(f"| {bench['group']} | {name} | {ms} | {cell(bench, 'zig-safe')} | {cell(bench, 'rust')} | "
                     f"{cell(bench, 'rust-checked')} | {cell(bench, 'my')} | {f'{limit:.2f}' if limit else ''} | "
                     f"{cell(bench, 'my-unchecked')} | {', '.join(variants)} | {status} |")
    return "\n".join(lines)


def geomeans(result: dict) -> list[str]:
    lines = []
    for group in GROUPS:
        benches = [b for b in result["benchmarks"].values() if b["group"] == group]
        for arm_name in ("my", "my-unchecked", "zig-safe", "rust", "rust-checked"):
            ratios = [b["arms"][arm_name]["ratio_wall"]["median"] for b in benches
                      if b["arms"].get(arm_name, {}).get("ratio_wall")]
            if not ratios:
                continue
            geo = math.exp(sum(math.log(r) for r in ratios) / len(ratios))
            target = TARGETS.get(arm_name) if group == "suite" else None
            note = f"  (plan target <= {target})" if target else ""
            lines.append(f"geomean {group:5} {arm_name:13} {geo:6.2f}x over {len(ratios)} benchmark(s){note}")
            if group == "suite" and arm_name == "my":
                worst = max(ratios)
                lines.append(f"worst   {group:5} {arm_name:13} {worst:6.2f}x  (plan target <= {TARGETS['worst my']})")
    return lines


def describe(verdict: dict) -> str:
    where = f"{verdict['benchmark']} {verdict['arm']}"
    if verdict["verdict"] == "unmeasured":
        return f"REGRESSION {where}: not measured ({verdict['reason']}); threshold {verdict['limit']:.2f}x"
    band = f"(95% CI {verdict['lo']:.2f}-{verdict['hi']:.2f})"
    base = f"baseline {verdict['baseline']:.2f}x + {verdict['tolerance'] * 100:.0f}%"
    again = ""
    if "confirmed" in verdict:
        again = (f"; re-measured {verdict['confirmed']:.2f}x "
                 f"(95% CI {verdict['confirmed_lo']:.2f}-{verdict['confirmed_hi']:.2f})")
    if verdict["verdict"] == "regression":
        return (f"REGRESSION {where}: ratio {verdict['observed']:.2f}x to zig-fast {band} exceeds threshold "
                f"{verdict['limit']:.2f}x ({base}){again}")
    if verdict["verdict"] == "unconfirmed":
        return (f"noise      {where}: ratio {verdict['observed']:.2f}x {band} exceeded threshold "
                f"{verdict['limit']:.2f}x ({base}){again}, within it; not a failure")
    return (f"improved   {where}: ratio {verdict['observed']:.2f}x {band} is below its baseline "
            f"{verdict['baseline']:.2f}x by more than the tolerance; rebaseline to lock the gain in")


# ---------------------------------------------------------------- run

def command_run(opts: argparse.Namespace) -> int:
    filters = [f.strip() for f in (opts.filter or "").split(",") if f.strip()]
    if opts.filter is not None and not filters:
        print("bench-parity: --filter needs a non-empty substring", file=sys.stderr)
        return 2
    benches = discover(filters)
    if not benches:
        print(f"bench-parity: --filter {opts.filter!r} names no benchmark "
              f"(benchmarks are GROUP/NAME under {HERE.relative_to(ROOT)}: {', '.join(GROUPS)})", file=sys.stderr)
        return 2
    mylang = Path(opts.mylang).resolve()
    if not mylang.exists():
        print(f"bench-parity: no compiler at {mylang}", file=sys.stderr)
        return 2
    if opts.cpu not in os.sched_getaffinity(0):
        print(f"bench-parity: CPU {opts.cpu} is not available to this process", file=sys.stderr)
        return 2
    notices: list[str] = []
    rustc = find_rustc(opts.rustc)
    if rustc is None:
        notices.append("rustc not found (RUSTC, PATH, ~/.cargo/bin): Rust arms skipped")
    with_perf = perf_available()
    if not with_perf:
        notices.append("hardware counters unavailable (needs `perf` and kernel.perf_event_paranoid <= 2, "
                       f"now {read_paranoid()}): instructions/cycles not recorded")
    tools = {"mylang": str(mylang), "mylang_sha256": sha(mylang.read_bytes()), "zig": opts.zig,
             "zig_version": version_of([opts.zig, "version"]), "rustc": rustc,
             "rustc_version": version_of([rustc, "--version"]) if rustc else None, "perf": with_perf}
    work = Path(opts.work).resolve()
    (work / "bin").mkdir(parents=True, exist_ok=True)
    result = {"schema": SCHEMA_RESULT, "started": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
              "commit": git_head(), "host": host(), "cpu": opts.cpu, "rounds": opts.rounds, "warmups": opts.warmups,
              "filter": filters, "tools": tools, "load_start": os.getloadavg(), "benchmarks": {}, "notices": notices}
    wanted_arms = set(opts.arms or [])
    jobs = []
    for bench in benches:
        entry = {"group": bench["group"], "arms": {}}
        result["benchmarks"][bench["name"]] = entry
        for job in arms_for(bench["ports"], opts.qbe):
            if wanted_arms and job["arm"] not in wanted_arms and job["arm"] != REFERENCE:
                continue
            if job["lang"] == "rust" and rustc is None:
                continue
            job["bench"] = bench["name"]
            job["bin"] = work / "bin" / f"{bench['name']}.{job['arm']}"
            entry["arms"][job["arm"]] = {"lang": job["lang"], "src": str(job["src"].relative_to(ROOT)),
                                         "flags": job["flags"]}
            jobs.append(job)
    tools_for_build = {"mylang": str(mylang), "zig": opts.zig, "rustc": rustc}
    print(f"bench-parity: building {len(jobs)} arms of {len(benches)} benchmark(s) with {opts.jobs} job(s)",
          file=sys.stderr)
    with concurrent.futures.ThreadPoolExecutor(max_workers=opts.jobs) as pool:
        builds = list(pool.map(lambda job: build(job, tools_for_build, work), jobs))
    failures: list[str] = []
    timed: dict[str, list[dict]] = {}
    for job, built in zip(jobs, builds):
        data = result["benchmarks"][job["bench"]]["arms"][job["arm"]]
        data["build"] = built
        if not built["ok"]:
            data["failure"] = "build failed"
            print(f"BUILD FAIL {job['bench']} {job['arm']}\n{built['stderr']}", file=sys.stderr)
            continue
        stdout, status = run_captured(job["bin"])
        data.update(stdout_sha256=sha(stdout), status=status, matches_expected=stdout == expected_of(benches, job))
        if status != 0 or not data["matches_expected"]:
            data["failure"] = f"output differs from .expected (status {status})"
            print(f"MISMATCH {job['bench']} {job['arm']} status={status}", file=sys.stderr)
            continue
        data["binary_sha256"] = sha(job["bin"].read_bytes())
        timed.setdefault(job["bench"], []).append(job)
    for job in jobs:
        data = result["benchmarks"][job["bench"]]["arms"][job["arm"]]
        if "failure" not in data:
            continue
        if job["lang"] == "my":
            failures.append(f"{job['bench']} {job['arm']}: {data['failure']}")
        elif job["arm"] == REFERENCE:
            failures.append(f"{job['bench']} {REFERENCE}: {data['failure']}; no ratio can be formed")
        else:
            notices.append(f"{job['bench']} {job['arm']}: {data['failure']}; arm skipped")
    rng = random.Random(opts.seed)
    with Pinned(opts.cpu):
        for name, arms in timed.items():
            if not any(a["arm"] == REFERENCE for a in arms):
                result["benchmarks"][name]["failure"] = f"no qualified {REFERENCE}"
                continue
            time_benchmark(result["benchmarks"][name], arms, opts, rng, with_perf)
            write_json(opts.json, result)
    thresholds_path = Path(opts.thresholds)
    thresholds = load_thresholds(thresholds_path)
    if opts.write_thresholds:
        updated = rebaseline([result], thresholds, opts.label, opts.tolerance)
        thresholds_path.write_text(json.dumps(updated, indent=1) + "\n")
        notices.append(f"thresholds rewritten from this run: {thresholds_path}")
        thresholds = updated
    verdicts = check(result, thresholds)
    exceeded = sorted({v["benchmark"] for v in verdicts if v["verdict"] == "regression"})
    if exceeded and opts.confirm:
        print(f"bench-parity: re-measuring {len(exceeded)} program(s) that exceeded a threshold: "
              f"{', '.join(exceeded)}", file=sys.stderr)
        with Pinned(opts.cpu):
            for name in exceeded:
                confirm_benchmark(result["benchmarks"][name], timed[name], opts, rng)
        verdicts = check(result, thresholds)
    result["load_end"] = os.getloadavg()
    result["siblings"] = siblings(opts.cpu)
    shared = [n for n, b in result["benchmarks"].items() if (b.get("sibling_busy") or 0) > 0.25]
    if shared:
        notices.append(f"the SMT sibling of CPU {opts.cpu} (CPU {', '.join(map(str, result['siblings']))}) was over "
                       f"25% busy while {len(shared)} program(s) were timed ({', '.join(shared[:6])}"
                       f"{' ...' if len(shared) > 6 else ''}); a busy sibling moves some ratios by tens of "
                       "percent — prefer a core whose sibling is idle")
    unthresholded = [f"{name} {arm_name}" for name, bench in result["benchmarks"].items()
                     for arm_name, data in bench["arms"].items()
                     if data.get("lang") == "my" and data.get("ratio_wall")
                     and arm_name not in thresholds.get("benchmarks", {}).get(name, {})]
    if unthresholded:
        shown = ", ".join(unthresholded[:6]) + (f" and {len(unthresholded) - 6} more" if len(unthresholded) > 6 else "")
        notices.append(f"no threshold for {len(unthresholded)} mylang arm(s), not checked: {shown}; "
                       "rebaseline to add them")
    bad = [v for v in verdicts if v["verdict"] in ("regression", "unmeasured")]
    result["checks"] = verdicts
    result["failures"] = failures + [describe(v) for v in bad]
    result["verdict"] = "fail" if result["failures"] else "pass"
    write_json(opts.json, result)
    print(table(result, verdicts))
    print()
    for line in geomeans(result):
        print(line)
    for notice in notices:
        print(f"notice: {notice}")
    for verdict in verdicts:
        if verdict["verdict"] in ("improved", "unconfirmed"):
            print(describe(verdict))
    for failure in failures:
        print(f"FAILURE {failure}")
    for verdict in bad:
        print(describe(verdict))
    checked = len(verdicts)
    print(f"bench-parity: {result['verdict'].upper()} — {checked} thresholded arm(s) checked, "
          f"{len(result['failures'])} failure(s); result {opts.json}")
    return 1 if result["failures"] else 0


def expected_of(benches: list[dict], job: dict) -> bytes:
    return next(b["expected"] for b in benches if b["name"] == job["bench"])


def time_benchmark(entry: dict, arms: list[dict], opts: argparse.Namespace, rng: random.Random,
                   with_perf: bool) -> None:
    for job in arms:
        data = entry["arms"][job["arm"]]
        data["peak_rss_kb"] = peak_rss_kb(job["bin"])
        if with_perf:
            data["counters"] = counters(job["bin"])
    sibling_cpus = siblings(opts.cpu)
    before = cpu_times(sibling_cpus)
    samples = measure(arms, opts, rng)
    entry["sibling_busy"] = busy_fraction(before, cpu_times(sibling_cpus))
    ref = samples[REFERENCE]
    for arm_name, sample in samples.items():
        data = entry["arms"][arm_name]
        data.update(wall=sample["wall"], cpu=sample["cpu"], wall_median=statistics.median(sample["wall"]),
                    cpu_median=statistics.median(sample["cpu"]), ratio_wall=paired(sample["wall"], ref["wall"]),
                    ratio_cpu=paired(sample["cpu"], ref["cpu"]))
    summary = "  ".join(f"{a}={entry['arms'][a]['ratio_wall']['median']:.2f}x" for a in samples)
    name = arms[0]["bench"]
    print(f"{name}: zig-fast {statistics.median(ref['wall']) * 1000:.1f} ms | {summary}", file=sys.stderr)


def measure(arms: list[dict], opts: argparse.Namespace, rng: random.Random) -> dict:
    """Warm-ups, then `opts.rounds` rounds with the arm order shuffled in each."""
    for _ in range(opts.warmups):
        for job in arms:
            run_timed(job["bin"])
    samples = {job["arm"]: {"wall": [], "cpu": []} for job in arms}
    for _ in range(opts.rounds):
        order = arms[:]
        rng.shuffle(order)
        for job in order:
            wall, cpu, status = run_timed(job["bin"])
            if status != 0:
                print(f"RUN FAIL {job['bench']} {job['arm']} status={status}", file=sys.stderr)
            samples[job["arm"]]["wall"].append(wall)
            samples[job["arm"]]["cpu"].append(cpu)
    return samples


def confirm_benchmark(entry: dict, arms: list[dict], opts: argparse.Namespace, rng: random.Random) -> None:
    """Re-measure a benchmark that exceeded a threshold, as a fresh pass."""
    samples = measure(arms, opts, rng)
    ref = samples[REFERENCE]
    for arm_name, sample in samples.items():
        entry["arms"][arm_name]["confirm"] = {"wall": sample["wall"], "cpu": sample["cpu"],
                                              "ratio_wall": paired(sample["wall"], ref["wall"])}
    summary = "  ".join(f"{a}={entry['arms'][a]['confirm']['ratio_wall']['median']:.2f}x" for a in samples)
    print(f"{arms[0]['bench']} (confirmation): {summary}", file=sys.stderr)


class Pinned:
    """Pin this process, and so every child it spawns, to one CPU for a block."""

    def __init__(self, cpu: int):
        self.cpu = cpu
        self.saved = os.sched_getaffinity(0)

    def __enter__(self):
        os.sched_setaffinity(0, {self.cpu})

    def __exit__(self, *exc):
        os.sched_setaffinity(0, self.saved)


def write_json(path: str, result: dict) -> None:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(result, indent=1, default=str) + "\n")


def git_head() -> str | None:
    try:
        done = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return done.stdout.strip() if done.returncode == 0 else None


def host() -> dict:
    model = None
    try:
        for line in Path("/proc/cpuinfo").read_text().splitlines():
            if line.startswith("model name"):
                model = line.split(":", 1)[1].strip()
                break
    except OSError:
        pass
    return {"machine": platform.machine(), "kernel": platform.release(), "cpu_model": model,
            "perf_event_paranoid": read_paranoid()}


def read_paranoid() -> str | None:
    try:
        return Path("/proc/sys/kernel/perf_event_paranoid").read_text().strip()
    except OSError:
        return None


# ---------------------------------------------------------------- other commands

def command_rebaseline(opts: argparse.Namespace) -> int:
    results = [json.loads(Path(path).read_text()) for path in opts.results]
    for path, result in zip(opts.results, results):
        if result.get("schema") != SCHEMA_RESULT:
            print(f"bench-parity: {path} is not a {SCHEMA_RESULT} file", file=sys.stderr)
            return 2
    if len({r["tools"]["mylang_sha256"] for r in results}) != 1:
        print("bench-parity: pooled batches must time the same compiler", file=sys.stderr)
        return 2
    path = Path(opts.thresholds)
    updated = rebaseline(results, load_thresholds(path), opts.label, opts.tolerance, opts.note)
    path.write_text(json.dumps(updated, indent=1) + "\n")
    names = {n for r in results for n, b in r["benchmarks"].items() if any(a.get("wall") for a in b["arms"].values())}
    print(f"bench-parity: rewrote {len(names)} benchmark(s) in {path} from {len(results)} batch(es)")
    return 0


def command_table(opts: argparse.Namespace) -> int:
    result = json.loads(Path(opts.result).read_text())
    print(table(result, result.get("checks", [])))
    print()
    for line in geomeans(result):
        print(line)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    run = commands.add_parser("run", help="build, qualify, time and check")
    run.add_argument("--mylang", default=str(ROOT / "zig-out/bin/mylang"), help="compiler under test")
    run.add_argument("--zig", default="zig", help="Zig used for the reference arms")
    run.add_argument("--rustc", help="rustc for the Rust arms (default: RUSTC, PATH, ~/.cargo/bin)")
    run.add_argument("--cpu", type=int, default=2, help="the one CPU every timed process is pinned to")
    run.add_argument("--rounds", type=int, default=7)
    run.add_argument("--warmups", type=int, default=2)
    run.add_argument("--filter", help="comma-separated substrings of GROUP/NAME")
    run.add_argument("--arms", nargs="*", help="time only these arms (zig-fast is always kept)")
    run.add_argument("--qbe", action="store_true", help="also build the my-qbe arm (not thresholded by default)")
    run.add_argument("--jobs", type=int, default=4, help="concurrent builds (never while timing)")
    run.add_argument("--work", default=str(ROOT / ".mylang-cache/bench-parity"))
    run.add_argument("--json", default=str(ROOT / ".mylang-cache/bench-parity/result.json"))
    run.add_argument("--thresholds", default=str(HERE / "thresholds.json"))
    run.add_argument("--write-thresholds", action="store_true",
                     help="rewrite the thresholds file from this run instead of keeping it")
    run.add_argument("--label", default="quiet", help="batch label recorded by --write-thresholds")
    run.add_argument("--tolerance", type=float, default=DEFAULT_TOLERANCE)
    run.add_argument("--seed", type=int, default=20260922)
    run.add_argument("--no-confirm", dest="confirm", action="store_false",
                     help="fail on the first pass instead of re-measuring a program that exceeded its threshold")
    again = commands.add_parser("rebaseline", help="rewrite thresholds.json from result JSONs (pooled)")
    again.add_argument("results", nargs="+", help="result JSONs of the same compiler; their rounds are pooled")
    again.add_argument("--thresholds", default=str(HERE / "thresholds.json"))
    again.add_argument("--label", default="quiet", help="how the batch was measured, e.g. quiet or loaded")
    again.add_argument("--tolerance", type=float, default=DEFAULT_TOLERANCE)
    again.add_argument("--note", help="a sentence stored in the file about this baseline (replaces the old one)")
    show = commands.add_parser("table", help="print a result JSON as the ratio table")
    show.add_argument("result")
    opts = parser.parse_args()
    if opts.command == "run":
        if opts.rounds < 3 or opts.warmups < 0 or opts.jobs < 1:
            print("bench-parity: need --rounds >= 3, --warmups >= 0, --jobs >= 1", file=sys.stderr)
            return 2
        return command_run(opts)
    if opts.command == "rebaseline":
        return command_rebaseline(opts)
    return command_table(opts)


if __name__ == "__main__":
    sys.exit(main())

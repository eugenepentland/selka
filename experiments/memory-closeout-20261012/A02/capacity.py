#!/usr/bin/env python3
"""Reproducible native runtime policy probes; timing is an explicit separate phase."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
C0 = "fbfcaa7a923186a8e773c3760f81c10aa345a432"
POLICIES = ("baseline", "start_one", "start_four", "three_halves")
CASES = {"nested": 20000, "nested5": 20000, "append": 20, "reuse": 20, "replacement": 1000000,
         "buffer": 20, "reserved": 20}
CHECKSUM_PER_REPETITION = {"nested": 1770, "nested5": 1770, "append": 999999,
                          "reuse": 999999, "replacement": 2, "buffer": 42, "reserved": 42}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def runtime(root, revision="HEAD"):
    def read(name):
        return subprocess.check_output(["git", "show", revision + ":" + name], cwd=root, text=True)
    driver = read("src/core/driver.zig").split("pub const runtime_source =", 1)[1].split(";", 1)[0]
    names = re.findall(r'@embedFile\("([^"\n]+)"\)', driver)
    return "\n".join(read("src/core/" + name) for name in names)


def counted(root, source, revision=C0):
    # Apply the actual anchored production instrumentation, including fail-closed
    # uniqueness checks; never maintain a second approximate allocation counter.
    def read(name):
        return subprocess.check_output(["git", "show", revision + ":src/core/" + name], cwd=root, text=True)
    text = read("count_runtime.zig").split("const patches =", 1)[1].split("/// Why", 1)[0]
    fields = re.findall(r'\.(anchor|before|after)\s*=\s*("(?:[^"\\]|\\.)*"|header)', text)
    patches = []
    for key, raw in fields:
        if key == "anchor":
            patches.append({})
        patches[-1][key] = read("runtime/core_count.h") if raw == "header" else json.loads(raw)
    for patch in patches:
        anchor = patch["anchor"]
        if source.count(anchor) != 1:
            raise ValueError(f"instrumentation anchor count {source.count(anchor)}: {anchor!r}")
        source = source.replace(anchor, patch.get("before", "") + anchor + patch.get("after", ""))
    return source + "\n" + read("runtime/core_count.c")


def variant(source, policy):
    anchor = "int64_t cap = list->cap < 4 ? 8 : list->cap * 2;"
    changes = {
        "start_one": "int64_t cap = list->cap == 0 ? 1 : list->cap * 2;",
        "start_four": "int64_t cap = list->cap < 4 ? 4 : list->cap * 2;",
        "three_halves": "int64_t cap = list->cap < 4 ? 8 : list->cap + (list->cap + 1) / 2;",
    }
    if policy != "baseline":
        assert source.count(anchor) == 1
        source = source.replace(anchor, changes[policy])
    if policy == "three_halves":
        anchor = "capacity *= 2;"
        at = source.index("static myl_block *core_buffer_regrow")
        end = source.index("static inline myl_block *core_buffer_grow", at)
        assert source[at:end].count(anchor) == 1
        source = source[:at] + source[at:end].replace(anchor, "capacity += (capacity + 1) / 2;", 1) + source[end:]
    return source


def invoke(argv, env, expected=0):
    ran = subprocess.run(list(map(str, argv)), capture_output=True, text=True, env=env, timeout=300)
    if ran.returncode != expected or (expected == 0 and ran.stderr):
        raise RuntimeError({"argv": list(map(str, argv)), "status": ran.returncode,
                            "stdout": ran.stdout, "stderr": ran.stderr})
    return ran


def build(args):
    result = {"source_revision": subprocess.check_output(["git", "rev-parse", args.revision], cwd=args.root, text=True).strip(),
              "harness_sha256": digest(__file__), "fixture_sha256": digest(HERE / "capacity_fixture.c"),
              "zig": str(args.zig), "zig_sha256": digest(args.zig), "policies": {}}
    text = runtime(args.root, args.revision)
    for policy in args.policies:
        records = {}
        for instrumented in (False, True):
            lane = "counted" if instrumented else "plain"
            directory = args.output / policy / lane
            directory.mkdir(parents=True, exist_ok=True)
            source = variant(text, policy)
            source = counted(args.root, source, args.revision) if instrumented else source
            (directory / "runtime.c").write_text("#define MYL_ZERO_RC 1\n" + source)
            (directory / "fixture.c").write_bytes((HERE / "capacity_fixture.c").read_bytes())
            binary = directory / "program"
            argv = [args.zig, "cc", "-O2", "-g", "-std=c11", "-pthread", "-ffunction-sections", "-Wl,--gc-sections",
                    *( ["-DA02_COUNTED=1"] if instrumented else []), directory / "fixture.c", "-o", binary]
            ran = invoke(argv, os.environ)
            symbols = subprocess.check_output(["nm", str(binary)], text=True)
            assert not any(name in symbols for name in ("myl_core_retain", "myl_core_release", "myl_core_share"))
            records[lane] = {"binary": str(binary), "binary_sha256": digest(binary),
                             "runtime_sha256": digest(directory / "runtime.c"), "build_argv": list(map(str, argv)),
                             "build_stderr": ran.stderr}
        result["policies"][policy] = records
    save(args.output / "artifacts.json", result)


def measure(args):
    artifacts = json.loads((args.output / "artifacts.json").read_text())
    result = {"artifacts": artifacts, "cases": {}, "scope": "native runtime operations, not compiler-generated guest timings"}
    for name in args.cases:
        repetitions = CASES[name]
        result["cases"][name] = {}
        for policy in args.policies:
            directory = args.output / policy / "counted"
            counts = directory / (name + ".json")
            ran = invoke([directory / "program", name, repetitions], dict(os.environ, MYLANG_COUNTERS=str(counts)))
            memory = json.loads(counts.read_text())["totals"]
            assert memory["live_bytes_at_exit"] == 0
            assert all(memory.get(key, 0) == 0 for key in ("runtime_retains", "runtime_releases", "shared_retains", "shared_releases", "share_marks"))
            assert json.loads(ran.stdout)["checksum"] == CHECKSUM_PER_REPETITION[name] * repetitions
            result["cases"][name][policy] = {"repetitions": repetitions, "output": json.loads(ran.stdout),
                                            "memory": memory, "raw_counts": str(counts)}
    save(args.output / "allocations.json", result)


def timing(args):
    assert args.cpu in os.sched_getaffinity(0)
    artifacts = json.loads((args.output / "artifacts.json").read_text())
    result = {"artifacts": artifacts, "method": "2 warmup groups, 9 alternating groups; process wall clock; uninstrumented",
              "measurement_harness_sha256": digest(__file__), "started_utc": datetime.now(timezone.utc).isoformat(),
              "cpu": args.cpu, "rss_scope": "single process max RSS via GNU time, excluding compilation", "cases": {}}
    for name in args.cases:
        repetitions = CASES[name]
        rows = {policy: {"ns": [], "rss_kib": [], "warmup_ns": [], "warmup_rss_kib": [],
                         "repetitions": repetitions} for policy in args.policies}
        result["cases"][name] = rows
        for sample in range(11):
            order = args.policies if sample % 2 == 0 else list(reversed(args.policies))
            for policy in order:
                binary = args.output / policy / "plain/program"
                rss = args.output / "rss.txt"
                argv = ["/usr/bin/time", "-f", "%M", "-o", rss, "taskset", "-c", str(args.cpu), binary, name, repetitions]
                start = time.perf_counter_ns()
                ran = invoke(argv, os.environ)
                elapsed = time.perf_counter_ns() - start
                assert json.loads(ran.stdout)["checksum"] == CHECKSUM_PER_REPETITION[name] * repetitions
                if sample >= 2:
                    rows[policy]["ns"].append(elapsed)
                    rows[policy]["rss_kib"].append(int(rss.read_text()))
                    rows[policy]["output"] = json.loads(ran.stdout)
                else:
                    rows[policy]["warmup_ns"].append(elapsed)
                    rows[policy]["warmup_rss_kib"].append(int(rss.read_text()))
                save(args.output / ("timing-" + "-".join(args.cases) + ".partial.json"), result)
        for row in rows.values():
            row["median_ns"] = statistics.median(row["ns"])
            row["range_ns"] = [min(row["ns"]), max(row["ns"])]
        result["cases"][name] = rows
        result["finished_utc"] = datetime.now(timezone.utc).isoformat()
        save(args.output / ("timing-" + "-".join(args.cases) + ".json"), result)
        print("measured", name, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("build", "measure", "timing"))
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--revision", default=C0)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--zig", type=Path, default=os.environ.get("ZIG"))
    parser.add_argument("--cpu", type=int)
    parser.add_argument("--cases", nargs="+", choices=list(CASES), default=list(CASES))
    parser.add_argument("--policies", nargs="+", choices=POLICIES, default=list(POLICIES))
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.root = args.root.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    globals()[args.phase](args)


if __name__ == "__main__":
    main()

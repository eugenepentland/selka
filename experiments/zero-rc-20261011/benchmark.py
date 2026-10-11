#!/usr/bin/env python3
"""Paired, uninstrumented stage 1 timings; shared-host observations, not a speed guarantee."""
import argparse
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import time

sys.dont_write_bytecode = True
from measure import HERE, ROOT, command, digest, save


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--compiler", type=Path, required=True)
    p.add_argument("--before", type=Path, required=True)
    p.add_argument("--zig", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    a = p.parse_args()
    for key in ("compiler", "before", "zig", "output"):
        setattr(a, key, getattr(a, key).resolve())
    a.output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, ZIG=str(a.zig), MYLANG_ZIG=str(a.zig))
    for key in ("MYLANG_COUNTERS", "MYL_CORE_LEAKCHECK"):
        env.pop(key, None)
    result = {"host": platform.platform(), "cpu": next((line.split(':', 1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines() if line.startswith('model name')), ''),
              "method": "9 paired alternating runs after 2 warmups; counters and leak checks disabled; RSS from GNU time; shared host",
              "harness_sha256": digest(__file__), "cases": {},
              "compilers": {key: {"path": str(getattr(a, key)), "sha256": digest(getattr(a, key))} for key in ("before", "compiler")}}
    for name, n in (("15_managed_elements", 1000000), ("24_text_builder", 10000000),
                    ("25_text_snapshot", 10000000), ("27_buffer_builder", 10000000)):
        lanes = {}
        for lane, compiler, flag in (("before", a.before, "--experimental-single-owner"), ("after", a.compiler, "--experimental-zero-rc")):
            directory = a.output / name / lane
            directory.mkdir(parents=True, exist_ok=True)
            source = HERE.parent / "rc-census-20261010/samples" / (name + ".my")
            if lane == "after" and name.startswith("25_"):
                source = HERE / "migrated" / source.name
            text = source.read_text().replace("const n = len(args)", f"const n = (len(args) + 1) * {n}")
            path, binary = directory / "sample.my", directory / "program"
            path.write_text(text)
            base = [compiler, "build", path, "--release", flag, "--zig", a.zig,
                    "--cache-dir", directory / "cache", "-o", binary, "--report"]
            # A fresh language cache, then the same command warm; Zig's global cache is shared.
            for state in ("cold", "warm"):
                command(base, directory / f"build-{state}", env)
                command([compiler, "check", path, flag, "--timings=json", "--cache-dir", directory / "check-cache"], directory / f"check-{state}", env)
            lanes[lane] = {"source_sha256": digest(path), "binary_sha256": digest(binary), "runs": [],
                           "compile": {state: json.loads((directory / f"build-{state}.command.json").read_text())["elapsed_ns"] for state in ("cold", "warm")},
                           "check": {state: json.loads((directory / f"check-{state}.command.json").read_text())["elapsed_ns"] for state in ("cold", "warm")}}
        for i in range(11):
            order = ("before", "after") if i % 2 == 0 else ("after", "before")
            answers = []
            for lane in order:
                directory = a.output / name / lane
                rss = directory / f"rss-{i}.txt"
                start = time.perf_counter_ns()
                ran = subprocess.run(["/usr/bin/time", "-f", "%M", "-o", rss, str(directory / "program")], cwd=ROOT, env=env, capture_output=True, timeout=120)
                elapsed = time.perf_counter_ns() - start
                if ran.returncode or ran.stderr:
                    raise RuntimeError(f"benchmark {name}/{lane}: {ran.returncode} {ran.stderr!r}")
                answers.append(ran.stdout.decode())
                if i >= 2:
                    lanes[lane]["runs"].append({"elapsed_ns": elapsed, "max_rss_kib": int(rss.read_text()), "stdout": answers[-1]})
            assert answers[0] == answers[1], name
        for lane, data in lanes.items():
            values = [run["elapsed_ns"] for run in data["runs"]]
            data["median_ns"], data["min_ns"], data["max_ns"] = statistics.median(values), min(values), max(values)
            data["median_max_rss_kib"] = statistics.median(run["max_rss_kib"] for run in data["runs"])
        result["cases"][name] = {"n": n, "lanes": lanes, "elapsed_ratio": lanes["after"]["median_ns"] / lanes["before"]["median_ns"]}
        save(HERE / "performance.json", result)
        print(name, result["cases"][name]["elapsed_ratio"], flush=True)
    for tool in result["compilers"].values():
        assert digest(tool["path"]) == tool["sha256"]


if __name__ == "__main__":
    main()

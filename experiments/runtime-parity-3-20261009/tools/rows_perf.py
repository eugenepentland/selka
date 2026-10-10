#!/usr/bin/env python3
"""The 46 rows, base against a lane, as perf counts on one non-timing CPU (coordinator, 2026-10-09).

FS-X found its only real regression in the rows (binary_search/4096 at 3.7x), which the
lanes had not measured. This lets a lane check them without CPU 10: it uses the row
binaries `measure_all46.py --build-only --mylang BASE --core LANE --bin DIR` builds
(`row_<name>_old`/`_new`, or `<name>_old`/`_new` for the S0 rows) and runs each at both
sizes with the harness's own iteration counts and seed, interleaved and shuffled, under
`perf stat` on --cpu. Instruction counts are exact; cycles compare only within one run.

usage: rows_perf.py --bin DIR --worktree WT [--cpu 8] [--rounds 5] [--rows a,b] --json OUT
Rows above 1.02x in instructions or 1.03x in cycles are listed at the end.
"""
import argparse, importlib.util, json, random, statistics, subprocess, sys
from pathlib import Path

EVENTS = "cpu_core/instructions/u,cpu_core/cycles/u,cpu_core/branch-misses/u"


def harness(worktree):
    spec = importlib.util.spec_from_file_location("m46", worktree / "experiments/new-core-s4-20261006/integration/measure_all46.py")
    module = importlib.util.module_from_spec(spec)
    argv, sys.argv = sys.argv, ["measure_all46.py"]
    try:
        spec.loader.exec_module(module)
    except SystemExit:
        pass
    finally:
        sys.argv = argv
    return module.rows


def binary(directory, row, kind):
    for name in (f"row_{row}_{kind}", f"{row}_{kind}"):
        if (directory / name).exists():
            return directory / name
    return None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--bin", required=True, type=Path)
    p.add_argument("--worktree", required=True, type=Path)
    p.add_argument("--cpu", type=int, default=8)
    p.add_argument("--rounds", type=int, default=5)
    p.add_argument("--rows", default="")
    p.add_argument("--json", required=True, type=Path)
    a = p.parse_args()
    if a.cpu in (2, 3, 10, 11):
        raise SystemExit("CPUs 2, 3, 10 and 11 are reserved for timing")
    rows = harness(a.worktree.resolve())
    names = [r for r in rows.UNITS if not a.rows or r in a.rows.split(",")]
    rng = random.Random(11)
    result = {}
    for row in names:
        old, new = binary(a.bin, row, "old"), binary(a.bin, row, "new")
        if old is None or new is None:
            raise SystemExit(f"missing old/new row binary: {row}")
        unit = rows.UNITS[row]
        for size, iterations in (("4096", unit[2]), ("64", unit[3])):
            samples = {"old": [], "new": []}
            for _ in range(a.rounds):
                for kind in rng.sample(["old", "new"], 2):
                    exe = old if kind == "old" else new
                    proc = subprocess.run(["taskset", "-c", str(a.cpu), "perf", "stat", "-x,", "-e", EVENTS, str(exe), size, str(iterations), str(rows.SEED)],
                                          capture_output=True, text=True)
                    values = [int(line.split(",")[0]) for line in proc.stderr.splitlines() if "cpu_core/" in line and line.split(",")[0].isdigit()]
                    if proc.returncode == 0 and len(values) == 3:
                        samples[kind].append(values)
            if not samples["old"] or not samples["new"]:
                result[f"{row}/{size}"] = {"error": "no samples"}
                continue
            med = lambda kind, i: statistics.median(s[i] for s in samples[kind])
            result[f"{row}/{size}"] = {"instructions": med("new", 0) / med("old", 0), "cycles": med("new", 1) / med("old", 1),
                                       "branch_misses": [med("old", 2), med("new", 2)]}
            r = result[f"{row}/{size}"]
            print(f"{row}/{size}: instructions {r['instructions']:.4f} cycles {r['cycles']:.3f} branch-misses {r['branch_misses'][0]:.0f} -> {r['branch_misses'][1]:.0f}", flush=True)
    a.json.write_text(json.dumps(result, indent=1))
    flagged = [k for k, v in result.items() if "error" in v or v["instructions"] > 1.02 or v["cycles"] > 1.03]
    print(f"{len(result)} cells; above 1.02x instructions or 1.03x cycles: {flagged}")


if __name__ == "__main__":
    main()

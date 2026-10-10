#!/usr/bin/env python3
"""The 46 rows, final against base only, with measure_all40's own CPU-10 method (coordinator, 2026-10-09).

`measure_all46.py` refuses to run without its Rust/Zig/Go references, and the frozen S1/S3
reference runner (runtime-baseline-20261003/.mylang-cache/runtime-expanded/runner/bin) was
removed by the 2026-10-09 cache prune. For final against base only the two mylang binaries
matter, and those are built (`measure_all46.py --build-only`). This takes the harness's
`sample` (taskset CPU 10, perf cycles), UNITS, SEED and startup subtraction unchanged:
3 one-iteration startup samples, then ROUNDS interleaved shuffled rounds, cycles per unit.
Run under the CPU-10 flock.

usage: rows_mylang.py --bin DIR --json OUT [--rounds 7] [--seed N]
"""
import argparse, importlib.util, json, random, statistics, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def harness():
    spec = importlib.util.spec_from_file_location("m46", ROOT / "experiments/new-core-s4-20261006/integration/measure_all46.py")
    module = importlib.util.module_from_spec(spec)
    argv, sys.argv = sys.argv, ["measure_all46.py"]
    try:
        spec.loader.exec_module(module)
    finally:
        sys.argv = argv
    return module.rows


def binary(directory, row, kind):
    for name in (f"row_{row}_{kind}", f"{row}_{kind}"):
        if (directory / name).exists():
            return directory / name
    raise SystemExit(f"missing {kind} binary for {row} in {directory}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--bin", required=True, type=Path)
    p.add_argument("--json", required=True, type=Path)
    p.add_argument("--rounds", type=int, default=7)
    p.add_argument("--seed", type=int, default=1)
    a = p.parse_args()
    rows = harness()
    rng = random.Random(a.seed)
    result = {"method": "measure_all40 sample/startup subtraction, CPU 10, old/new mylang only", "rounds": a.rounds, "rows": {}}
    for row in rows.UNITS:
        suite, unit, big, small = rows.UNITS[row]
        arms = {"old": binary(a.bin, row, "old"), "new": binary(a.bin, row, "new")}
        result["rows"][row] = {}
        for size, iterations in zip(rows.SIZES, (big, small)):
            startup = {k: [rows.sample([b, size, 1, rows.SEED]) for _ in range(3)] for k, b in arms.items()}
            runs = {k: [] for k in arms}
            for _ in range(a.rounds):
                for k in rng.sample(list(arms), 2):
                    runs[k].append(rows.sample([arms[k], size, iterations, rows.SEED]))
            checks = {run["checksum"] for k in runs for run in runs[k]}
            if len(checks) != 1:
                raise SystemExit(f"{row}/{size}: checksum disagreement {checks}")
            per = size * iterations if unit == "element" else iterations
            value = {k: (statistics.median(r["cycles"] for r in runs[k]) - statistics.median(r["cycles"] for r in startup[k])) / per for k in arms}
            ratio = value["new"] / value["old"]
            result["rows"][row][str(size)] = {"old": value["old"], "new": value["new"], "ratio": ratio}
            print(f"{row}/{size}: new/old {ratio:.3f}", flush=True)
            a.json.write_text(json.dumps(result, indent=1))


if __name__ == "__main__":
    main()

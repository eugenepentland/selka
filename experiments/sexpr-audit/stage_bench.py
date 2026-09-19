#!/usr/bin/env python3
"""Stage-by-stage performance harness for the four QBE levers.

Each *stage* is a snapshot of the candidates built by one compiler revision.
`build` compiles the candidate set with the current `zig-out/bin/mylang` and
freezes the binaries under /tmp/sexpr-stages/<stage>/.  `compare` then measures
every frozen stage in one interleaved batch, so machine drift cancels and the
reported ratio between stages is trustworthy even when absolute times move.

Candidates (all native, ReleaseFast):
  loop      empty while loop over len(bytes)
  index     bytes[i] read + add
  scan      bytes[i] compared twice
  calls     1,000,000 calls to a two-argument adder
  tokens    read + tokenize
  parse     read + tokenize + parse
  census    full port: parse + walk (experiments/sexpr-port/main.my)
  render    full port: parse + render

Every stage must print byte-identical output; `compare` checks it and reports
any mismatch, so a stage that changes behavior cannot pass silently.

Usage:
  python3 experiments/sexpr-audit/stage_bench.py build STAGE
  python3 experiments/sexpr-audit/stage_bench.py compare STAGE [STAGE ...] [--runs N]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import statistics
import subprocess
import time
from pathlib import Path

AUDIT = Path(__file__).resolve().parent
REPO = AUDIT.parents[1]
PORT = REPO / "experiments/sexpr-port"
MYLANG = REPO / "zig-out/bin/mylang"
STAGES = Path("/tmp/sexpr-stages")
DEFAULT_INPUT = Path("/tmp/sexpr-bench/input.sexp")
TASKSET = shutil.which("taskset") or "taskset"

# candidate -> (source, extra args)
CANDIDATES = {
    "loop": (AUDIT / "h_loop.my", []),
    "scan": (AUDIT / "e_scan.my", []),
    "index": (AUDIT / "i_index.my", []),
    "calls": (AUDIT / "f_calls.my", []),
    "tokens": (AUDIT / "b_tokens.my", []),
    "parse": (AUDIT / "c_parse.my", []),
    "census": (PORT / "main.my", []),
    "render": (PORT / "main.my", ["--render"]),
}


def build(stage: str, input_path: Path) -> None:
    target = STAGES / stage
    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True)
    cache = STAGES / f"cache-{stage}"
    for name, (source, _) in CANDIDATES.items():
        binary = target / name
        proc = subprocess.run(
            [str(MYLANG), "build", str(source.relative_to(REPO)), "-o", str(binary),
             "--mode", "ReleaseFast", f"--cache-dir={cache}"],
            cwd=REPO, capture_output=True, text=True)
        if proc.returncode != 0:
            raise SystemExit(f"building {name} failed:\n{proc.stdout}\n{proc.stderr}")
    meta = {"stage": stage, "compiler_mtime": MYLANG.stat().st_mtime,
            "compiler_sha256": hashlib.sha256(MYLANG.read_bytes()).hexdigest(),
            "input": str(input_path)}
    (target / "stage.json").write_text(json.dumps(meta, indent=2) + "\n")
    print(f"built stage {stage}: {len(CANDIDATES)} candidates from {meta['compiler_sha256'][:16]}")


def run_once(binary: Path, args: list[str]) -> tuple[float, str]:
    start = time.perf_counter()
    proc = subprocess.run([TASKSET, "-c", "6", str(binary), *args],
                          capture_output=True, text=True)
    elapsed = time.perf_counter() - start
    if proc.returncode != 0:
        raise SystemExit(f"{binary} {args} failed ({proc.returncode}):\n{proc.stderr}")
    return elapsed, proc.stdout


def compare(stages: list[str], runs: int, input_path: Path) -> int:
    for stage in stages:
        if not (STAGES / stage / "stage.json").exists():
            raise SystemExit(f"stage {stage} not built; run build {stage} first")
    samples: dict[str, dict[str, list[float]]] = {s: {} for s in stages}
    digests: dict[str, dict[str, str]] = {s: {} for s in stages}
    for name, (_, extra) in CANDIDATES.items():
        # Interleave rounds so slow drift in machine load hits every stage equally.
        for _ in range(runs):
            for stage in stages:
                binary = STAGES / stage / name
                elapsed, output = run_once(binary, [str(input_path), *extra])
                samples[stage].setdefault(name, []).append(elapsed)
                digests[stage][name] = hashlib.sha256(output.encode()).hexdigest()[:16]

    base = stages[0]
    print(f"input {input_path}   runs {runs}   taskset -c 6   baseline {base}\n")
    header = f"{'candidate':<10}" + "".join(f"{s:>12}" for s in stages) + "".join(f"{'x ' + s:>10}" for s in stages[1:])
    print(header)
    print("-" * len(header))
    report = {"runs": runs, "stages": stages, "candidates": {}}
    for name in CANDIDATES:
        medians = {s: statistics.median(samples[s][name]) * 1000 for s in stages}
        row = f"{name:<10}" + "".join(f"{medians[s]:>12.3f}" for s in stages)
        row += "".join(f"{medians[base] / medians[s]:>9.2f}x" for s in stages[1:])
        print(row)
        report["candidates"][name] = {
            "median_ms": medians,
            "speedup_vs_base": {s: medians[base] / medians[s] for s in stages[1:]},
            "samples": {s: samples[s][name] for s in stages},
            "digest": {s: digests[s][name] for s in stages},
        }
    total_base = sum(report["candidates"][n]["median_ms"][base] for n in CANDIDATES)
    line = f"{'total':<10}" + "".join(
        f"{sum(report['candidates'][n]['median_ms'][s] for n in CANDIDATES):>12.3f}" for s in stages)
    line += "".join(
        f"{total_base / sum(report['candidates'][n]['median_ms'][s] for n in CANDIDATES):>9.2f}x" for s in stages[1:])
    print("-" * len(header))
    print(line)

    print()
    ok = True
    for name in CANDIDATES:
        unique = {digests[s][name] for s in stages}
        mark = "identical" if len(unique) == 1 else "MISMATCH " + " ".join(
            f"{s}={digests[s][name]}" for s in stages)
        if len(unique) != 1:
            ok = False
        print(f"  output {name:<8} {mark}")
    report["outputs_identical"] = ok
    out = AUDIT / "evidence" / "stages"
    out.mkdir(parents=True, exist_ok=True)
    (out / ("-".join(stages) + ".json")).write_text(json.dumps(report, indent=2) + "\n")
    print(f"\nwrote {out / ('-'.join(stages) + '.json')}")
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="command", required=True)
    b = sub.add_parser("build")
    b.add_argument("stage")
    b.add_argument("--input", default=str(DEFAULT_INPUT))
    c = sub.add_parser("compare")
    c.add_argument("stages", nargs="+")
    c.add_argument("--runs", type=int, default=15)
    c.add_argument("--input", default=str(DEFAULT_INPUT))
    args = ap.parse_args()
    if args.command == "build":
        build(args.stage, Path(args.input))
        return 0
    return compare(args.stages, args.runs, Path(args.input))


if __name__ == "__main__":
    raise SystemExit(main())

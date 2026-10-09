#!/usr/bin/env python3
"""FU-PORT: user-space instructions and cycles on CPU 8 (cpu_core events), the port's release
binaries against newest main's, interleaved: every round runs each cell once per compiler in a
shuffled order. Binaries are llvm_identity.py's (`.mylang-cache/fuport/llvm/{P,M}/LABEL.bin`).
Cells: the lanes' targeted parity programs, the four Lox VM cells and two tree-walker cells of
claude-parity-measure/.tmp/pm/lox (copied to .tmp/pm/lox), and EDA (all 34 golden designs, one
cell: the sum). Every tag of TAGS (default PM) runs each round; X (fu-final-x) and A (main ab85c16c2) are the
old-syntax builds, for context. usage: instructions.py ROUNDS OUT.json [TAGS]"""
import json, random, shutil, subprocess, sys
from pathlib import Path

WT = Path(__file__).resolve().parents[3]
BIN = WT / ".mylang-cache/fuport/llvm"
LOX = WT / ".tmp/pm/lox"
EDA = Path("/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore")
OUT = WT / ".mylang-cache/fuport/instr-eda"
PARITY = {"matmul": "parity-suite-matmul", "sort_quick": "parity-suite-sort_quick", "sieve": "parity-suite-sieve",
          "nbody": "parity-suite-nbody", "str_build": "parity-micro-str_build", "knucleotide": "parity-suite-knucleotide",
          "list_append_sum": "parity-micro-list_append_sum"}
LOXCELLS = {"vm/fib": ("vm", "fib.34"), "vm/invocation": ("vm", "invocation.1500000"), "vm/method_call": ("vm", "method_call.500000"),
            "vm/string_equality": ("vm", "string_equality.100000"), "tree/equality": ("tree", "equality.300000"),
            "tree/invocation": ("tree", "invocation.150000")}


def perf(argv, cwd):
    done = subprocess.run(["perf", "stat", "-x,", "-e", "cpu_core/instructions/u,cpu_core/cycles/u", "--", "taskset", "-c", "8", *map(str, argv)],
                          cwd=cwd, capture_output=True)
    counts = {}
    for line in done.stderr.decode().splitlines():
        fields = line.split(",")
        if len(fields) > 3 and fields[2].startswith("cpu_core/"):
            counts[fields[2].split("/")[1]] = int(fields[0])
    return done.returncode, done.stdout, counts


def eda_cell(tag):
    cases = json.loads((EDA / "golden/manifest.json").read_text())["cases"]
    total = {"instructions": 0, "cycles": 0}
    for case in cases:
        directory = OUT / tag / case["id"]
        shutil.rmtree(directory, ignore_errors=True)
        directory.mkdir(parents=True)
        status, _, counts = perf([BIN / tag / "eda.bin", "--model", f"golden/cases/{case['id']}/model.sexp", "--project-dir",
                                  f"golden/projects/{case['project']}", "--out-dir", directory, *case["flags"]], EDA)
        assert status == 0, case["id"]
        for k in total:
            total[k] += counts[k]
    return total


def cells():
    out = {}
    for name, label in PARITY.items():
        out[f"parity/{name}"] = lambda tag, label=label: perf([BIN / tag / f"{label}.bin"], WT)
    for name, (engine, script) in LOXCELLS.items():
        out[f"lox/{name}"] = lambda tag, engine=engine, script=script: perf([BIN / tag / "lox.bin", f"--engine={engine}", LOX / f"{script}.lox"], WT)
    out["eda/34 designs"] = lambda tag: (0, b"", eda_cell(tag))
    return out


def main():
    rounds, path = int(sys.argv[1]), Path(sys.argv[2])
    tags = list(sys.argv[3]) if len(sys.argv) > 3 else ["P", "M"]
    rng = random.Random(20261009)
    samples = {name: {tag: [] for tag in tags} for name in cells()}
    outputs = {}
    for r in range(rounds):
        for name, run in cells().items():
            order = list(tags)
            rng.shuffle(order)
            for tag in order:
                status, stdout, counts = run(tag)
                assert status == 0, (name, tag)
                outputs.setdefault((name, tag), stdout)
                assert outputs[(name, tag)] == stdout, (name, tag, "output changed between rounds")
                samples[name][tag].append(counts)
        print(f"round {r + 1} done", flush=True)
    result = {"cpu": 8, "rounds": rounds, "events": "cpu_core/instructions/u, cpu_core/cycles/u", "cells": {}}
    for name, by in samples.items():
        def median(tag, key):
            values = sorted(s[key] for s in by[tag])
            return values[len(values) // 2]
        row = {k: {tag: median(tag, k) for tag in tags} for k in ("instructions", "cycles")}
        for k in ("instructions", "cycles"):
            row[k]["ratio"] = row[k]["P"] / row[k]["M"]
            if "X" in tags and "A" in tags:
                row[k]["fux_ratio"] = row[k]["X"] / row[k]["A"]
        row["same_stdout"] = len({outputs[(name, tag)] for tag in tags}) == 1
        row["samples"] = by
        result["cells"][name] = row
    path.write_text(json.dumps(result, indent=1) + "\n")
    print(f"{'cell':28} {'port instr':>15} {'main instr':>15} {'P/M instr':>9} {'P/M cyc':>8} {'X/A instr':>9}")
    for name, row in result["cells"].items():
        fux = row["instructions"].get("fux_ratio")
        print(f"{name:28} {row['instructions']['P']:>15,} {row['instructions']['M']:>15,} {row['instructions']['ratio']:>9.3f} {row['cycles']['ratio']:>8.3f} {fux if fux is None else round(fux, 3)!s:>9}  same_stdout={row['same_stdout']}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""CPU-10 wall-time confirmation of wave PM's cycle bounds (coordinator, 2026-10-09).

PM measured cycles on CPU 8 of a busy machine. Before lanes F1 and S1 start, the
main bounds are re-taken as wall time on the quiet timing CPU: every arm of one
group runs interleaved (shuffled per round) under `taskset -c 10`, after warmup
rounds, and each arm's stdout must equal the group's reference arm. The caller
holds the CPU-10 flock.

usage: confirm.py --spec SPEC.json --out RESULT.json [--rounds 9] [--warmup 2] [--cpu 10]
SPEC: {"group": {"check": "ARM", "arms": {"ARM": [argv...], ...}}, ...}
"""
import argparse, hashlib, json, random, statistics, subprocess, time
from pathlib import Path


def run(argv, cpu):
    start = time.perf_counter_ns()
    proc = subprocess.run(["taskset", "-c", str(cpu), *argv], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return (time.perf_counter_ns() - start) / 1e6, proc.returncode, hashlib.sha256(proc.stdout).hexdigest()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--spec", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--rounds", type=int, default=9)
    p.add_argument("--warmup", type=int, default=2)
    p.add_argument("--cpu", type=int, default=10)
    a = p.parse_args()
    spec = json.loads(Path(a.spec).read_text())
    rng = random.Random(9)
    result = {}
    for group, g in spec.items():
        arms = g["arms"]
        outputs = {label: run(argv, a.cpu)[1:] for label, argv in arms.items()}
        samples = {label: [] for label in arms}
        for r in range(a.warmup + a.rounds):
            order = list(arms)
            rng.shuffle(order)
            for label in order:
                ms, _, _ = run(arms[label], a.cpu)
                if r >= a.warmup:
                    samples[label].append(ms)
        ref = statistics.median(samples[g["check"]])
        rows = {}
        for label in arms:
            med = statistics.median(samples[label])
            rows[label] = {"median_ms": med, "min_ms": min(samples[label]), "max_ms": max(samples[label]),
                           "ratio": med / ref, "status": outputs[label][0],
                           "output_ok": outputs[label] == outputs[g["check"]], "samples_ms": samples[label]}
        result[group] = {"reference": g["check"], "arms": rows}
        print(f"## {group} (÷ {g['check']}, {a.rounds} rounds, CPU {a.cpu})", flush=True)
        print("| arm | median ms | min | max | ratio | output |", flush=True)
        print("|---|---:|---:|---:|---:|---|", flush=True)
        for label, v in rows.items():
            print(f"| {label} | {v['median_ms']:.1f} | {v['min_ms']:.1f} | {v['max_ms']:.1f} | {v['ratio']:.3f} | {'ok' if v['output_ok'] and v['status'] == 0 else 'DIFFERS'} |", flush=True)
        Path(a.out).write_text(json.dumps(result, indent=1))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Deterministic, predeclared calibration and held-out transformation fixtures."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SHIFTS = [("left", 13), ("right", 7), ("left", 17), ("right", 11)]


def step(name, depth, indent):
    return "".join(f"{' ' * indent}{name} = bit_xor({name}, shift_{direction}({name}, {amount}))\n"
                   for direction, amount in SHIFTS[:depth])


def kernel(name, depth=3, unroll=1, lanes=1, fused=True, nested=False):
    source = f"func {name}(n: int, seed: int) -> int:\n"
    for lane in range(lanes):
        # XOR seeds avoids checked arithmetic affecting the modeled hot body.
        source += f"    mut x{lane} = bit_xor(seed, {lane})\n"
    if nested:
        source += "    for i in range(n):\n        for j in range(32):\n"
        source += step("x0", depth, 12)
    elif fused:
        # n is the number of outer iterations, not total scalar steps. The
        # manifest supplies n/unroll or n*32 to compare identical work.
        source += "    for i in range(n):\n"
        for _ in range(unroll):
            for lane in range(lanes):
                source += step(f"x{lane}", depth, 8)
    else:
        for lane in range(lanes):
            source += f"    for i{lane} in range(n):\n"
            source += step(f"x{lane}", depth, 8)
    value = "x0"
    for lane in range(1, lanes):
        value = f"bit_xor({value}, x{lane})"
    return source + f"    return {value}\n\n"


def main():
    definitions = [
        dict(name="cal_depth2", depth=2), dict(name="cal_depth4", depth=4),
        dict(name="one", depth=1), dict(name="one_unroll2", depth=1, unroll=2),
        dict(name="three"), dict(name="three_unroll4", unroll=4),
        dict(name="lanes2_separate", lanes=2, fused=False),
        dict(name="lanes2_fused", lanes=2),
        dict(name="lanes4_separate", lanes=4, fused=False),
        dict(name="lanes4_fused", lanes=4), dict(name="nested32", nested=True),
    ]
    source = "extern func runtime_bench_now(host: Host) -> i64 effects(host)\n\n"
    source += "".join(kernel(**d) for d in definitions)
    source += """func data_exit(n: int, seed: int) -> int:
    mut x = seed
    for i in range(n):
        if x == 0:
            break
        x = bit_xor(x, shift_left(x, 13))
    return x

func triangular(n: int, seed: int) -> int:
    mut x = seed
    for i in range(n):
        for j in range(i):
            x = bit_xor(x, shift_left(x, 13))
    return x

func parse_number(text: str) -> int:
    match parse_int(text):
        case Some(n):
            return n
        case None:
            return -1

func main(args: str[], host: Host, out: Stream) -> int:
    if len(args) != 3:
        return 2
    mut mode = parse_number(args[0])
    mut n = parse_number(args[1])
    mut seed = parse_number(args[2])
    if n < 0 or seed < 0:
        return 2
    mut value = 0
    mut start = runtime_bench_now(host)
"""
    names = [d["name"] for d in definitions] + ["data_exit", "triangular"]
    for index, name in enumerate(names):
        source += f"    {'if' if index == 0 else 'elif'} mode == {index}:\n        value = {name}(n, seed)\n"
    source += "    else:\n        return 2\n    mut elapsed = runtime_bench_now(host) - start\n    out.print(value, elapsed)\n    return 0\n"
    (ROOT / "kernels.my").write_text(source)
    modes = {name: i for i, name in enumerate(names)}
    n = 20_000_000
    def arm(name, count, depth=3, lanes=1, steps=None):
        return dict(function=name, mode=modes[name], n=count, seed=17,
                    oracle=dict(depth=depth, lanes=lanes, steps=count if steps is None else steps))
    suite = dict(
        schema="juice-ir-evaluation-v1",
        calibration=[arm("cal_depth2", n, depth=2), arm("cal_depth4", n, depth=4)],
        cases=[
            dict(name="identity", base=arm("three", n), candidate=arm("three", n)),
            dict(name="unroll2-short-chain", base=arm("one", n, depth=1),
                 candidate=arm("one_unroll2", n//2, depth=1, steps=n)),
            dict(name="unroll4-long-chain", base=arm("three", n),
                 candidate=arm("three_unroll4", n//4, steps=n)),
            dict(name="fuse-two-lanes", base=arm("lanes2_separate", n, lanes=2),
                 candidate=arm("lanes2_fused", n, lanes=2)),
            dict(name="fuse-four-lanes", base=arm("lanes4_separate", n, lanes=4),
                 candidate=arm("lanes4_fused", n, lanes=4)),
            dict(name="flatten-nested-loop", base=arm("nested32", n//32, steps=n),
                 candidate=arm("three", n)),
        ],
        abstentions=["data_exit", "triangular"],
        timing=dict(pairs=9, calibration_samples=9, warmup_pairs=1,
                    maximum_pair_spread=0.03, target_relative_ratio_error=0.05),
    )
    (ROOT / "suite.json").write_text(json.dumps(suite, indent=2) + "\n")


if __name__ == "__main__":
    main()

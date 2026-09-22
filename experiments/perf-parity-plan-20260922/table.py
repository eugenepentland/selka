#!/usr/bin/env python3
"""Render a bench.py result JSON as a ratio table (median paired ratio to zig-fast).

usage: table.py RESULT.json [--cpu] [--arms a,b,c] [--ms]
"""
import argparse
import json


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("result")
    ap.add_argument("--cpu", action="store_true", help="use CPU-time ratios instead of wall")
    ap.add_argument("--arms", help="comma-separated arm order")
    ap.add_argument("--ms", action="store_true", help="also print the reference median in ms")
    ap.add_argument("--ci", action="store_true", help="print 95%% intervals")
    opts = ap.parse_args()
    d = json.load(open(opts.result))
    key = "ratio_cpu" if opts.cpu else "ratio_wall"
    names = [n for n, b in d["benchmarks"].items() if any(key in a for a in b["arms"].values())]
    arms = opts.arms.split(",") if opts.arms else sorted({a for n in names for a in d["benchmarks"][n]["arms"]})
    header = ["benchmark"] + (["zig ms"] if opts.ms else []) + arms
    print("| " + " | ".join(header) + " |")
    print("|" + "---|" * len(header))
    for n in names:
        b = d["benchmarks"][n]["arms"]
        row = [n]
        if opts.ms:
            ref = b.get("zig-fast", {})
            row.append(f"{ref.get('wall_median', 0) * 1000:.1f}" if ref else "")
        for a in arms:
            r = b.get(a, {}).get(key)
            if not r:
                row.append("")
            elif opts.ci:
                row.append(f"{r['median']:.2f} [{r['lo']:.2f},{r['hi']:.2f}]")
            else:
                row.append(f"{r['median']:.2f}")
        print("| " + " | ".join(row) + " |")


if __name__ == "__main__":
    main()

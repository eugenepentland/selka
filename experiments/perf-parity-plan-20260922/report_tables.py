#!/usr/bin/env python3
"""Markdown tables for the audit from one or more bench.py result files.

usage: report_tables.py KIND RESULT.json [RESULT.json ...] [--cpu]

KIND:
  standing   ratio to zig-fast of the language arms, best mylang variant, peak RSS ratio
  price      ratio of each counterfactual arm to the same benchmark's `my` arm
             (both paired against zig-fast inside one batch), i.e. what one rule costs
  ladder     the plan's rungs as ratios to zig-fast
Geometric means are over the benchmarks that have the column.
"""
import argparse
import json
import math


def load(paths):
    merged = {}
    for p in paths:
        d = json.load(open(p))
        for name, b in d["benchmarks"].items():
            if any("ratio_wall" in a for a in b["arms"].values()):
                merged[name] = b
    return merged


def ratio(b, arm, key):
    r = b["arms"].get(arm, {}).get(key)
    return r["median"] if r else None


def gmean(xs):
    xs = [x for x in xs if x]
    return math.exp(sum(math.log(x) for x in xs) / len(xs)) if xs else None


def fmt(x, digits=2):
    return "" if x is None else f"{x:.{digits}f}"


def table(header, rows, means=True):
    out = ["| " + " | ".join(header) + " |", "|" + "|".join(["---"] + ["---:"] * (len(header) - 1)) + "|"]
    for row in rows:
        out.append("| " + " | ".join(row) + " |")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("kind", choices=["standing", "price", "ladder", "memory"])
    ap.add_argument("results", nargs="+")
    ap.add_argument("--cpu", action="store_true")
    opts = ap.parse_args()
    key = "ratio_cpu" if opts.cpu else "ratio_wall"
    data = load(opts.results)
    lines = []
    if opts.kind == "standing":
        arms = ["zig-safe", "rust", "rust-checked", "my", "my-unchecked"]
        header = ["program", "Zig ms"] + arms + ["best mylang variant", "RSS my/Zig"]
        rows, cols = [], {a: [] for a in arms}
        for name, b in data.items():
            ref = b["arms"]["zig-fast"]
            row = [name, f"{ref['wall_median'] * 1000:.1f}"]
            for a in arms:
                v = ratio(b, a, key)
                cols[a].append(v)
                row.append(fmt(v))
            variants = [(a, ratio(b, a, key)) for a in b["arms"]
                        if a.startswith("my-") and a not in ("my-unchecked",) and ":" not in a and ratio(b, a, key)]
            best = min(variants, key=lambda t: t[1]) if variants else None
            row.append(f"{best[0][3:]} {best[1]:.2f}" if best else "")
            rss_my, rss_z = b["arms"].get("my", {}).get("peak_rss_kb"), ref.get("peak_rss_kb")
            row.append(fmt(rss_my / rss_z, 1) if rss_my and rss_z else "")
            rows.append(row)
        rows.append(["**geomean**", ""] + [f"**{fmt(gmean(cols[a]))}**" for a in arms] + ["", ""])
        lines = table(header, rows)
    elif opts.kind == "price":
        arms = [("cf-nan", "NaN rule"), ("cf-negidx", "negative index"), ("cf-iter", "loop length re-check"),
                ("cf-lang", "all three rules"), ("cf-overflow", "overflow checks"), ("cf-bounds", "bounds + iter"),
                ("cf-checks", "all checks"), ("cf-frames", "frame protocol"), ("cf-all", "everything"),
                ("cf-noroots", "roots (vs nogc)"), ("l5", "lane 5")]
        header = ["program", "my × Zig"] + [label for _, label in arms]
        rows, cols = [], {a: [] for a, _ in arms}
        for name, b in data.items():
            base = ratio(b, "my", key)
            row = [name, fmt(base)]
            for a, _ in arms:
                v = ratio(b, a, key)
                if a == "cf-noroots":
                    nogc = ratio(b, "cf-nogc", key)
                    rel = v / nogc if v and nogc else None
                else:
                    rel = v / base if v and base else None
                cols[a].append(rel)
                row.append("" if rel is None else f"{(rel - 1) * 100:+.0f}%")
            rows.append(row)
        rows.append(["**geomean**", ""] + [f"**{(gmean(cols[a]) - 1) * 100:+.0f}%**" if gmean(cols[a]) else "" for a, _ in arms])
        lines = table(header, rows)
    elif opts.kind == "memory":
        header = ["program", "Zig MB", "Rust", "mylang", "best mylang variant"]
        rows = []
        for name, b in data.items():
            z = b["arms"]["zig-fast"].get("peak_rss_kb")
            if not z:
                continue
            def rel(arm):
                v = b["arms"].get(arm, {}).get("peak_rss_kb")
                return v / z if v else None
            variants = [(a, rel(a)) for a in b["arms"] if a.startswith("my-") and ":" not in a and a != "my-unchecked" and rel(a)]
            best = min(variants, key=lambda t: t[1]) if variants else None
            rows.append([name, f"{z / 1024:.1f}", fmt(rel("rust"), 1), fmt(rel("my"), 1),
                         f"{best[0][3:]} {best[1]:.1f}" if best else ""])
        lines = table(header, rows)
    else:
        arms = [("my", "today"), ("lad-nr", "+ noreturn"), ("lad-l5", "lane 5"), ("lad-l5-nr", "+ noreturn"),
                ("lad-l5-nr-lang", "+ language rules"), ("lad-l5-nr-lang-fr", "+ no frame record"),
                ("lad-l5-all", "unchecked bound"), ("rust", "Rust"), ("zig-safe", "Zig safe")]
        header = ["program"] + [label for _, label in arms]
        rows, cols = [], {a: [] for a, _ in arms}
        for name, b in data.items():
            row = [name]
            for a, _ in arms:
                v = ratio(b, a, key)
                cols[a].append(v)
                row.append(fmt(v))
            rows.append(row)
        rows.append(["**geomean**"] + [f"**{fmt(gmean(cols[a]))}**" for a, _ in arms])
        lines = table(header, rows)
    print("\n".join(lines))


if __name__ == "__main__":
    main()

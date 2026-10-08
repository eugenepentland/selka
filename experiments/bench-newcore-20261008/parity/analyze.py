#!/usr/bin/env python3
"""Tables for REPORT.md: new-core result.json against the old core's 2026-09-23 thresholds.

usage: analyze.py result.json thresholds.json
"""
import json
import math
import statistics
import sys

result = json.load(open(sys.argv[1]))
thresholds = json.load(open(sys.argv[2]))["benchmarks"]


def geo(xs):
    return math.exp(sum(math.log(x) for x in xs) / len(xs)) if xs else float("nan")


def pair_ratio(bench, a, b):
    """Median of per-round wall ratios a/b (same rounds, so paired)."""
    wa, wb = bench["arms"].get(a, {}).get("wall"), bench["arms"].get(b, {}).get("wall")
    if not wa or not wb:
        return None
    return statistics.median(x / y for x, y in zip(wa, wb))


rows = []
for name, bench in result["benchmarks"].items():
    arms = bench["arms"]
    my = arms.get("my", {})
    if "zig-fast" not in arms or not arms["zig-fast"].get("wall"):
        continue
    r = {"name": name, "group": bench["group"], "zig_ms": arms["zig-fast"]["wall_median"] * 1000,
         "my_ms": my.get("wall_median", float("nan")) * 1000,
         "fast": my.get("ratio_wall"), "safe": pair_ratio(bench, "my", "zig-safe"),
         "rust": pair_ratio(bench, "my", "rust"), "rustc": pair_ratio(bench, "my", "rust-checked"),
         "old": thresholds.get(name, {}).get("my", {}).get("ratio"),
         "sib": bench.get("sibling_busy"),
         "variants": {a: d["ratio_wall"]["median"] for a, d in arms.items()
                      if d.get("lang") == "my" and a != "my" and d.get("ratio_wall")},
         "old_variants": {a: e["ratio"] for a, e in thresholds.get(name, {}).items() if a != "my"},
         "confirm": (my.get("confirm") or {}).get("ratio_wall"),
         "instr": None}
    c = {a: (arms.get(a, {}).get("counters") or {}).get("instructions") for a in ("my", "zig-fast", "rust")}
    if c["my"] and c["zig-fast"]:
        r["instr"] = c["my"] / c["zig-fast"]
    r["instr_rust"] = c["my"] / c["rust"] if c["my"] and c["rust"] else None
    rows.append(r)

fmt = lambda x: "" if x is None else f"{x:.2f}"
print("| group | program | zig-fast ms | my ms | my/zig-fast (95% CI) | my/zig-safe | my/rust | my/rust-checked | old core my/zig-fast | new/old | instr my/zig | instr my/rust |")
print("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
for r in rows:
    f = r["fast"]
    ci = f"{f['median']:.2f} ({f['lo']:.2f}-{f['hi']:.2f})" if f else "n/a"
    change = f"{f['median'] / r['old']:.2f}" if f and r["old"] else ""
    print(f"| {r['group']} | {r['name']} | {r['zig_ms']:.1f} | {r['my_ms']:.1f} | {ci} | {fmt(r['safe'])} | {fmt(r['rust'])} | "
          f"{fmt(r['rustc'])} | {fmt(r['old'])} | {change} | {fmt(r['instr'])} | {fmt(r['instr_rust'])} |")


def col(key):
    return [r[key]["median"] if key == "fast" else r[key] for r in rows if r[key] is not None]


print()
print("| column | n | geomean | median | min | max |")
print("|---|---:|---:|---:|---:|---:|")
for label, key in (("my/zig-fast (new core)", "fast"), ("my/zig-safe", "safe"), ("my/rust", "rust"),
                   ("my/rust-checked", "rustc"), ("old core my/zig-fast (2026-09-23)", "old")):
    xs = col(key)
    print(f"| {label} | {len(xs)} | {geo(xs):.2f} | {statistics.median(xs):.2f} | {min(xs):.2f} | {max(xs):.2f} |")
both = [(r["fast"]["median"], r["old"]) for r in rows if r["fast"] and r["old"]]
print(f"| new/old (per program) | {len(both)} | {geo([a / b for a, b in both]):.2f} | "
      f"{statistics.median([a / b for a, b in both]):.2f} | {min(a / b for a, b in both):.2f} | {max(a / b for a, b in both):.2f} |")
print()
print("slower than zig-fast (ratio > 1.00):", sum(1 for x in col("fast") if x > 1.0), "of", len(col("fast")))
print("slower than zig-fast by >5% (ratio > 1.05):", sum(1 for x in col("fast") if x > 1.05))
print("slower than rust:", sum(1 for x in col("rust") if x > 1.0), "of", len(col("rust")))
print("slower than rust by >5%:", sum(1 for x in col("rust") if x > 1.05))
print("slower than zig-safe:", sum(1 for x in col("safe") if x > 1.0), "of", len(col("safe")))
print("slower than rust-checked:", sum(1 for x in col("rustc") if x > 1.0), "of", len(col("rustc")))
print("old core slower than zig-fast:", sum(1 for x in col("old") if x > 1.0), "of", len(col("old")))
print()
print("| program | variant | new my-variant/zig-fast | old (2026-09-23) |")
print("|---|---|---:|---:|")
for r in rows:
    for a in sorted(set(r["variants"]) | set(r["old_variants"])):
        print(f"| {r['name']} | {a} | {fmt(r['variants'].get(a))} | {fmt(r['old_variants'].get(a))} |")
print()
print("sibling busy:", {r["name"]: r["sib"] for r in rows})
print("confirmation passes:", {r["name"]: round(r["confirm"]["median"], 3) for r in rows if r["confirm"]})

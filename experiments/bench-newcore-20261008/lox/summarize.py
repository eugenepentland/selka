#!/usr/bin/env python3
"""Summarize a measure.py runtime.json (and optional compile/tests JSON) into the
tables REPORT.md uses: per-script medians and ratios to Zig ReleaseFast, geomeans,
mylang x Rust/Go, peak RSS.

usage: summarize.py RUNTIME_JSON [--old OLD_RUNTIME_JSON]
"""
from __future__ import annotations

import gzip
import json
import math
import statistics
import sys
from pathlib import Path

LABELS = [("mylang:release", "mylang new core"), ("zig:release", "Zig ReleaseFast"),
          ("zig:release-safe", "Zig ReleaseSafe"), ("rust:release", "Rust"), ("go:release", "Go")]


def load(path: str) -> dict:
    p = Path(path)
    raw = gzip.decompress(p.read_bytes()) if p.suffix == ".gz" else p.read_bytes()
    return json.loads(raw)


def med(xs):
    xs = [x for x in xs if x is not None]
    return statistics.median(xs) if xs else None


def geomean(xs):
    xs = [x for x in xs if x]
    return math.exp(sum(map(math.log, xs)) / len(xs)) if xs else None


def tables(data: dict, labels=LABELS) -> str:
    samples = data["samples"]
    present = [(k, n) for k, n in labels if any(k in per for per in samples.values())]
    out = []
    for engine in ("vm", "tree"):
        keys = sorted(k for k in samples if k.endswith("/" + engine))
        rounds = max(len(v) for k in keys for v in samples[k].values())
        out.append(f"### {engine} engine: median wall seconds over {rounds} rounds (x Zig ReleaseFast)\n")
        out.append("| script | " + " | ".join(n for _, n in present) + " | mylang x Rust | mylang x Go |")
        out.append("|---" * (len(present) + 3) + "|")
        ratios = {k: [] for k, _ in present}
        vs_rust, vs_go = [], []
        for key in keys:
            per = samples[key]
            m = {lab: med([s["wall"] for s in per.get(lab, [])]) for lab, _ in present}
            base = m["zig:release"]
            cells = []
            for lab, _ in present:
                if m[lab] is None:
                    cells.append("FAIL")
                    continue
                ratios[lab].append(m[lab] / base)
                cells.append(f"{m[lab]:.2f} ({m[lab] / base:.2f}x)")
            r = m["mylang:release"] / m["rust:release"]
            g = m["mylang:release"] / m["go:release"]
            vs_rust.append(r)
            vs_go.append(g)
            out.append(f"| {key.split('/')[0]} | " + " | ".join(cells) + f" | {r:.2f}x | {g:.2f}x |")
        out.append("| **geomean** | " + " | ".join(f"**{geomean(ratios[lab]):.2f}x**" for lab, _ in present)
                   + f" | **{geomean(vs_rust):.2f}x** | **{geomean(vs_go):.2f}x** |")
        out.append("")
        spreads = []
        for key in keys:
            for lab, _ in present:
                xs = [s["wall"] for s in samples[key].get(lab, []) if s["wall"] is not None]
                if len(xs) > 1:
                    spreads.append((max(xs) - min(xs)) / statistics.median(xs))
        out.append(f"Median (max-min)/median across rounds, all {engine} cells: {statistics.median(spreads) * 100:.1f}%"
                   f" (max {max(spreads) * 100:.1f}%)\n")
    out.append("### Peak RSS, MiB (max over rounds)\n")
    out.append("| script/engine | " + " | ".join(n for _, n in present) + " | mylang x Zig | mylang x Rust |")
    out.append("|---" * (len(present) + 3) + "|")
    rz, rr = [], []
    for key in sorted(samples):
        per = samples[key]
        rss = {lab: max((s["maxrss_kib"] or 0) for s in per.get(lab, [{"maxrss_kib": 0}])) / 1024 for lab, _ in present}
        a, z, r = rss["mylang:release"], rss["zig:release"], rss["rust:release"]
        rz.append(a / z if z else None)
        rr.append(a / r if r else None)
        out.append(f"| {key} | " + " | ".join(f"{rss[lab]:.1f}" for lab, _ in present)
                   + f" | {a / z:.1f}x | {a / r:.1f}x |")
    out.append(f"| **geomean ratio** | " + " |" * len(present) + f" **{geomean(rz):.1f}x** | **{geomean(rr):.1f}x** |")
    out.append("")
    if data.get("failures"):
        out.append(f"**{len(data['failures'])} failed runs:** " + json.dumps(data["failures"])[:2000])
    out.append(f"quiet waits: {len(data.get('quiet_waits', []))}, total "
               f"{sum(w['waited_s'] for w in data.get('quiet_waits', []))} s; load per round: "
               + ", ".join(f"{l[0]:.2f}" for l in data.get("loadavg_per_round", [])))
    return "\n".join(out)


def old_geomeans(data: dict) -> str:
    """Geomeans of the old (2026-09-23) run with the same arithmetic, for the side-by-side."""
    samples = data["samples"]
    lines = []
    for engine in ("vm", "tree"):
        keys = [k for k in samples if k.endswith("/" + engine)]
        res = {}
        for lab in ("mylang:release", "mylang:release-qbe", "zig:release-safe", "rust:release", "go:release"):
            res[lab] = geomean([med([s["wall"] for s in samples[k][lab]]) / med([s["wall"] for s in samples[k]["zig:release"]])
                                for k in keys])
        vr = geomean([med([s["wall"] for s in samples[k]["mylang:release"]]) / med([s["wall"] for s in samples[k]["rust:release"]]) for k in keys])
        vg = geomean([med([s["wall"] for s in samples[k]["mylang:release"]]) / med([s["wall"] for s in samples[k]["go:release"]]) for k in keys])
        lines.append(f"{engine}: " + ", ".join(f"{k}={v:.2f}x" for k, v in res.items()) + f", mylang/rust={vr:.2f}x, mylang/go={vg:.2f}x")
        rz = geomean([max(s["maxrss_kib"] for s in samples[k]["mylang:release"]) / max(s["maxrss_kib"] for s in samples[k]["zig:release"]) for k in keys])
        lines.append(f"{engine} RSS mylang/zig geomean={rz:.1f}x")
    return "\n".join(lines)


if __name__ == "__main__":
    args = sys.argv[1:]
    if "--old" in args:
        i = args.index("--old")
        print(old_geomeans(load(args[i + 1])))
        args = args[:i] + args[i + 2:]
    if args:
        print(tables(load(args[0])))

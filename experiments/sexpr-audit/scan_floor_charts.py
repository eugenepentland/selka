#!/usr/bin/env python3
"""Draw the scan-only floor chart (assembly and hand-written QBE IR).

Reads evidence/scan-floor.json (written by scan_floor.py). The machine is shared
and was loaded during the run, so every panel leads with the **fastest observed**
sample, which is the meaningful "floor" statistic; the median is drawn beside it
as a pale bar so the load skew stays visible. Linear axes only.

Usage: python3 experiments/sexpr-audit/scan_floor_charts.py [JSON] [-o PNG]
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

AUDIT = Path(__file__).resolve().parent
ZIG_RF = "zig ReleaseFast"
PY_IMPLS = ["python pure", "python + libs", "python tuned"]
COLORS = {
    "asm startup only": "#bdbdbd",
    "asm read only": "#c5b0d5",
    "asm scalar": "#ff9896",
    "asm sse2": "#e377c2",
    "asm avx2": "#d62728",
    "qbe ir scalar": "#c49c94",
    "qbe ir swar": "#8c564b",
    ZIG_RF: "#1f77b4",
    "zig ReleaseSafe": "#2ca02c",
    "mylang ReleaseFast": "#ff7f0e",
    "go": "#17becf",
    "zig llvm scalar": "#6baed6",
    "zig llvm swar": "#08519c",
    "python pure": "#9467bd",
    "python + libs": "#bcbd22",
    "python tuned": "#7f7f7f",
}
COMPILED = ["asm startup only", "asm read only", "asm scalar", "asm sse2", "asm avx2",
            "qbe ir scalar", "qbe ir swar", ZIG_RF, "zig ReleaseSafe",
            "mylang ReleaseFast", "go", "zig llvm scalar", "zig llvm swar"]
SCANNERS = ["asm scalar", "asm sse2", "asm avx2", "qbe ir scalar", "qbe ir swar",
            ZIG_RF, "zig ReleaseSafe", "go", "mylang ReleaseFast",
            "zig llvm scalar", "zig llvm swar"]
MEDIAN_COLOR = "#d9d9d9"


def _min_median_bars(ax, names, mins, medians, label_fmt="%.2f"):
    positions = list(range(len(names)))
    height = 0.38
    best = [mins[name] for name in names]
    mid = [medians[name] for name in names]
    bars = ax.barh([p - height / 2 for p in positions], best, height,
                   color=[COLORS.get(name, "#999999") for name in names],
                   label="fastest observed")
    ax.bar_label(bars, fmt=label_fmt, fontsize=8, padding=2)
    ax.barh([p + height / 2 for p in positions], mid, height,
            color=MEDIAN_COLOR, label="median")
    ax.set_yticks(positions, names, fontsize=8)
    ax.invert_yaxis()
    ax.grid(axis="x", alpha=0.3)
    ax.legend(fontsize=8, loc="center right")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("source", nargs="?",
                    default=str(AUDIT / "evidence/scan-floor.json"))
    ap.add_argument("-o", "--output",
                    default=str(AUDIT / "evidence/scan-floor.png"))
    args = ap.parse_args()
    data = json.loads(Path(args.source).read_text())
    mins = data["mins_ms"]
    med = data["medians_ms"]
    work = data.get("work_medians_ms", {})
    work_samples = data.get("work_samples_ms", {})
    runs = data["runs"]

    fig, axes = plt.subplots(2, 2, figsize=(15, 9.5))
    fig.suptitle(
        "scan floor: hand-written x86-64 assembly and hand-written QBE IR\n"
        f"{data['bytes']:,} byte input, {runs} runs pinned to core {data.get('core', '?')} "
        "\u2014  bars are fastest-observed ms, pale bars are medians (shared host)  \u2014  linear axes",
        fontsize=12, fontweight="bold")

    # (0,0) sorted fastest-observed process wall clock for the compiled scanners.
    ax = axes[0][0]
    order = sorted(COMPILED, key=lambda name: mins[name])
    _min_median_bars(ax, order, mins, med)
    ax.set_xlabel("process wall clock (ms)")
    ax.set_title("Compiled, assembly and hand-written IR (sorted by best)", fontsize=11)
    ax.set_xlim(0, max(med[name] for name in COMPILED) * 1.18)

    # (0,1) incremental cost of the scan itself over the read floor.
    ax = axes[0][1]
    floor = mins["asm read only"]
    increments = sorted(((name, max(0.0, mins[name] - floor)) for name in SCANNERS),
                        key=lambda row: row[1])
    bars = ax.barh(range(len(increments)), [value for _, value in increments],
                   color=[COLORS.get(name, "#999999") for name, _ in increments])
    ax.bar_label(bars, fmt="%.2f", fontsize=8, padding=2)
    ax.set_yticks(range(len(increments)), [name for name, _ in increments], fontsize=8)
    ax.invert_yaxis()
    ax.set_xlabel("fastest process wall \u2212 asm read-only fastest (ms)")
    ax.set_title("Cost of the scan itself\n(read + start-up cancelled)", fontsize=11)
    ax.set_xlim(0, max(value for _, value in increments) * 1.25)
    ax.grid(axis="x", alpha=0.3)

    # (1,0) slowdown against Zig ReleaseFast, on fastest-observed samples.
    ax = axes[1][0]
    ratios = sorted(((name, mins[name] / mins[ZIG_RF]) for name in SCANNERS),
                    key=lambda row: row[1])
    bars = ax.barh(range(len(ratios)), [value for _, value in ratios],
                   color=[COLORS.get(name, "#999999") for name, _ in ratios])
    ax.bar_label(bars, fmt="%.2fx", fontsize=8, padding=2)
    ax.set_yticks(range(len(ratios)), [name for name, _ in ratios], fontsize=8)
    ax.invert_yaxis()
    ax.axvline(1.0, color="black", linestyle="--", linewidth=1)
    ax.text(1.02, -0.55, "Zig RF", fontsize=8, va="top", ha="left")
    ax.set_xlabel("fastest process wall \u00f7 Zig ReleaseFast fastest")
    ax.set_title("Slowdown vs Zig ReleaseFast (below 1 = faster)", fontsize=11)
    ax.set_xlim(0, max(value for _, value in ratios) * 1.2)
    ax.grid(axis="x", alpha=0.3)

    # (1,1) the Python columns, for context.
    ax = axes[1][1]
    positions = list(range(len(PY_IMPLS)))
    width = 0.27
    py_min = [min(work_samples.get(name, [0.0])) if work_samples.get(name) else 0.0
              for name in PY_IMPLS]
    py_work = [work.get(name) or 0.0 for name in PY_IMPLS]
    series = [("process wall (best)", [mins[name] for name in PY_IMPLS], "#9467bd"),
              ("in-process work (best)", py_min, "#c5b0d5"),
              ("in-process work (median)", py_work, "#7f7f7f")]
    for offset, (label, values, color) in enumerate(series):
        bars = ax.bar([x + (offset - 1) * width for x in positions], values, width,
                      label=label, color=color)
        ax.bar_label(bars, fmt="%.1f", fontsize=7, padding=2)
    ax.set_xticks(positions, [name.replace("python ", "") for name in PY_IMPLS], fontsize=9)
    ax.set_ylabel("milliseconds")
    ax.set_ylim(0, max(mins[name] for name in PY_IMPLS) * 1.22)
    ax.set_title("Python columns (numpy import sits in the library process wall)",
                 fontsize=11)
    ax.legend(fontsize=8)
    ax.grid(axis="y", alpha=0.3)

    fig.text(0.5, 0.006,
             "asm-* are static syscall-only x86-64 programs (asm/scan.s); qbe-* are hand-written QBE IR "
             "(qbe/scan.ssa, qbe/scan_swar.ssa) linked statically with libc. Every scanner prints the same "
             "bytes=/delims= line and matches the Zig digest. The host load average was "
             f"{data['loadavg'][0][0]:.1f} at the start and {data['loadavg'][1][0]:.1f} at the end, so the "
             "median bars are inflated; the fastest-observed bars are the floor.",
             ha="center", fontsize=8, style="italic")
    fig.tight_layout(rect=(0, 0.035, 1, 0.91))
    fig.savefig(args.output, dpi=135)
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

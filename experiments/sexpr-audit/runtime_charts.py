#!/usr/bin/env python3
"""Draw the seven-implementation sexpr runtime chart.

Reads evidence/runtime-compare.json (written by compare_impls.py). Every axis is
linear: the compiled engines (Zig RF/RS, mylang, Go) and the interpreted columns
(pure Python, Python + libraries, tuned Python) get their own absolute panels so
neither is flattened by the other's scale, then in-process work, the slowdown
against Zig ReleaseFast, the Zig ReleaseSafe/ReleaseFast ratio, and the Python
library/tuning speed-ups.

Usage: python3 experiments/sexpr-audit/runtime_charts.py [JSON] [-o PNG]
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

AUDIT = Path(__file__).resolve().parent
PHASES = ["loop", "scan", "tokens", "parse", "census", "render"]
LABELS = {
    "loop": "loop\n(empty)",
    "scan": "scan\n(byte compare)",
    "tokens": "tokens\n(read+tokenize)",
    "parse": "parse\n(+parse)",
    "census": "census\n(+walk)",
    "render": "render\n(+print)",
}
ZIG_RF = "zig ReleaseFast"
ZIG_RS = "zig ReleaseSafe"
MYLANG = "mylang ReleaseFast"
GO = "go"
PURE = "python pure"
LIBS = "python + libs"
TUNED = "python tuned"
IMPLS = [ZIG_RF, ZIG_RS, MYLANG, GO, PURE, LIBS, TUNED]
COLORS = {
    ZIG_RF: "#1f77b4",
    ZIG_RS: "#2ca02c",
    MYLANG: "#d62728",
    GO: "#17becf",
    PURE: "#9467bd",
    LIBS: "#ff7f0e",
    TUNED: "#8c564b",
}


def _bars(ax, series, width, fmt="%.1f", fontsize=6):
    """Grouped bars: `series` maps label -> (values, color)."""
    count = len(series)
    positions = list(range(len(PHASES)))
    for offset, (label, (values, color)) in enumerate(series.items()):
        shift = (offset - (count - 1) / 2) * width
        bars = ax.bar([x + shift for x in positions], values, width,
                      label=label, color=color)
        ax.bar_label(bars, fmt=fmt, fontsize=fontsize, padding=1)
    ax.set_xticks(positions, [LABELS[p] for p in PHASES], fontsize=8)
    ax.legend(fontsize=7)
    ax.grid(axis="y", alpha=0.3)


def _ratio_panel(ax, series, title, ylabel, fmt="%.1fx", fontsize=8, ylim=None):
    for offset, (label, (values, color)) in enumerate(series.items()):
        count = len(series)
        width = 0.8 / count
        shift = (offset - (count - 1) / 2) * width
        bars = ax.bar([x + shift for x in range(len(PHASES))], values, width,
                      label=label, color=color)
        ax.bar_label(bars, fmt=fmt, fontsize=fontsize, padding=1)
    ax.axhline(1.0, color="black", linestyle="--", linewidth=1)
    ax.set_title(title, fontsize=11)
    ax.set_ylabel(ylabel)
    ax.set_xticks(range(len(PHASES)), [LABELS[p] for p in PHASES], fontsize=8)
    ax.grid(axis="y", alpha=0.3)
    ax.legend(fontsize=7)
    if ylim:
        ax.set_ylim(*ylim)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("source", nargs="?",
                    default=str(AUDIT / "evidence/runtime-compare.json"))
    ap.add_argument("-o", "--output",
                    default=str(AUDIT / "evidence/runtime-compare.png"))
    args = ap.parse_args()
    data = json.loads(Path(args.source).read_text())
    med = data["medians_ms"]
    work = data.get("work_medians_ms", {})
    runs = data["runs"]

    fig, axes = plt.subplots(2, 3, figsize=(17, 10))
    fig.suptitle(
        "sexpr runtime: Zig RF/RS, mylang RF, Go, and three Python ports\n"
        f"{data['bytes']:,} byte input, median of {runs} runs pinned to core "
        f"{data.get('core', '?')}  \u2014  every axis linear",
        fontsize=13, fontweight="bold")

    # (0,0) compiled engines, process wall clock.
    ax = axes[0][0]
    compiled = [ZIG_RF, ZIG_RS, MYLANG, GO]
    _bars(ax, {impl: ([med[impl][p] for p in PHASES], COLORS[impl]) for impl in compiled},
          width=0.2, fmt="%.1f")
    top = max(med[impl][p] for impl in compiled for p in PHASES)
    ax.set_ylim(0, top * 1.18)
    ax.set_ylabel("wall clock (ms)")
    ax.set_title("Compiled engines, whole process (linear axis)", fontsize=11)

    # (0,1) interpreted columns, same phase order and their own scale.
    ax = axes[0][1]
    interpreted = [PURE, LIBS, TUNED]
    _bars(ax, {impl: ([med[impl][p] for p in PHASES], COLORS[impl]) for impl in interpreted},
          width=0.26, fmt="%.1f")
    top = max(med[impl][p] for impl in interpreted for p in PHASES)
    ax.set_ylim(0, top * 1.18)
    ax.set_ylabel("wall clock (ms)")
    ax.set_title("Interpreted columns, whole process\n(same CPython; start-up included)",
                 fontsize=11)

    # (0,2) in-process work, start-up removed.
    ax = axes[0][2]
    _bars(ax, {impl: ([work[impl][p] for p in PHASES], COLORS[impl]) for impl in interpreted},
          width=0.26, fmt="%.1f")
    top = max(work[impl][p] for impl in interpreted for p in PHASES)
    ax.set_ylim(0, top * 1.18)
    ax.set_ylabel("milliseconds")
    ax.set_title("Interpreted columns, in-process work\n(interpreter start-up and imports excluded)",
                 fontsize=11)

    # (1,0) slowdown against Zig ReleaseFast.
    ax = axes[1][0]
    _ratio_panel(ax, {
        ZIG_RS: ([med[ZIG_RS][p] / med[ZIG_RF][p] for p in PHASES], COLORS[ZIG_RS]),
        MYLANG: ([med[MYLANG][p] / med[ZIG_RF][p] for p in PHASES], COLORS[MYLANG]),
        GO: ([med[GO][p] / med[ZIG_RF][p] for p in PHASES], COLORS[GO]),
        PURE: ([med[PURE][p] / med[ZIG_RF][p] for p in PHASES], COLORS[PURE]),
        TUNED: ([med[TUNED][p] / med[ZIG_RF][p] for p in PHASES], COLORS[TUNED]),
    }, "Slowdown vs Zig ReleaseFast (process wall)",
        "impl \u00f7 Zig ReleaseFast", fmt="%.0fx")

    # (1,1) the prior finding, kept: Zig ReleaseSafe vs ReleaseFast.
    ax = axes[1][1]
    ratios = [med[ZIG_RS][p] / med[ZIG_RF][p] for p in PHASES]
    bars = ax.bar(range(len(PHASES)), ratios, 0.5, color=COLORS[ZIG_RS])
    ax.bar_label(bars, fmt="%.2fx", fontsize=9, padding=2)
    ax.axhline(1.0, color="black", linestyle="--", linewidth=1)
    ax.text(len(PHASES) - 0.4, 1.002, "parity", fontsize=8, ha="right", va="bottom")
    ax.set_ylim(0.8, 1.08)
    ax.set_title("Zig ReleaseSafe \u00f7 ReleaseFast\n(below 1 = safe build is faster)", fontsize=11)
    ax.set_ylabel("ReleaseSafe \u00f7 ReleaseFast")
    ax.set_xticks(range(len(PHASES)), [LABELS[p] for p in PHASES], fontsize=8)
    ax.grid(axis="y", alpha=0.3)

    # (1,2) Python: libraries and tuning, over pure Python in-process work.
    ax = axes[1][2]
    _ratio_panel(ax, {
        f"pure \u00f7 libs": ([work[PURE][p] / work[LIBS][p] for p in PHASES], COLORS[LIBS]),
        f"pure \u00f7 tuned": ([work[PURE][p] / work[TUNED][p] for p in PHASES], COLORS[TUNED]),
    }, "Python speed-up over pure Python\n(in-process work, above 1 = faster)",
        "pure \u00f7 variant", fmt="%.2fx")

    fig.text(0.5, 0.006,
             "mylang has no ReleaseSafe guest mode; its column is `mylang build --mode ReleaseFast`. "
             "scan is the only phase a library accelerates (numpy): at process level the lazy numpy import "
             "costs more than the scan, and stdlib `bytes.count` beats numpy for this predicate. "
             "Outputs are byte-identical across all seven for scan, parse, census and render.",
             ha="center", fontsize=8, style="italic")
    fig.tight_layout(rect=(0, 0.03, 1, 0.93))
    fig.savefig(args.output, dpi=135)
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

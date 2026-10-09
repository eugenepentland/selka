#!/usr/bin/env python3
"""Render public benchmark snapshots from retained samples; run with matplotlib."""

import json
import math
from pathlib import Path
from statistics import median

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt


ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
COLORS = ("#3157b7", "#39776a", "#c26c32")
plt.rcParams.update({
    "font.family": "DejaVu Sans", "font.size": 11,
    "axes.spines.top": False, "axes.spines.right": False,
    "axes.spines.left": False, "axes.edgecolor": "#cbd5e1",
    "text.color": "#17243b", "axes.labelcolor": "#17243b",
    "xtick.color": "#475569", "ytick.color": "#17243b",
    "svg.hashsalt": "selka-showcase-20261009",
})


def read(relative):
    return json.loads((ROOT / relative).read_text())


def save(fig, name):
    target = OUT / name
    fig.savefig(target, bbox_inches="tight", facecolor="white",
                metadata={"Date": None, "Creator": "Selka benchmark snapshot renderer"})
    target.write_text("\n".join(line.rstrip() for line in target.read_text().splitlines()) + "\n")
    plt.close(fig)


def runtime():
    data = read("experiments/parity-confirm-20261009/result.json")
    labels = {
        "matmul": "Matrix multiplication", "bytes_scan": "Byte scanning",
        "knucleotide": "DNA subsequence counting", "scan_split": "Scan and split",
        "sieve": "Prime sieve", "str_build": "String building", "nbody": "N-body",
    }
    fig, ax = plt.subplots(figsize=(10, 6.6))
    arms = (("my", "Selka release"), ("zig-safe", "Zig ReleaseSafe"),
            ("rust-checked", "Rust + overflow checks"))
    for offset, (arm, label) in enumerate(arms):
        positions, values = [], []
        for index, (_, row) in enumerate(data.items()):
            if arm not in row["arms"]:
                continue
            result = row["arms"][arm]
            assert result["status"] == 0 and result["output_ok"]
            assert math.isclose(result["median_ms"], median(result["samples_ms"]))
            positions.append(index + (offset - 1) * 0.23)
            values.append(result["median_ms"] / row["arms"]["zig-safe"]["median_ms"])
        bars = ax.barh(positions, values, height=0.21, label=label, color=COLORS[offset])
        ax.bar_label(bars, labels=[f"{v:.2f}×" for v in values], padding=4, fontsize=9)
    ax.set_yticks(range(len(data)), [labels[name] for name in data])
    ax.invert_yaxis()
    ax.set_xlim(0, 3.05)
    ax.set_xlabel("Elapsed time / Zig ReleaseSafe · lower is better")
    ax.set_title("Runtime snapshot · 9 October 2026", loc="left", pad=48,
                 fontsize=19, weight="bold")
    ax.legend(loc="lower left", bbox_to_anchor=(0, 1.02), ncol=3, frameon=False,
              fontsize=10)
    ax.xaxis.grid(True, color="#e2e8f0")
    ax.set_axisbelow(True)
    ax.tick_params(axis="y", length=0, pad=8)
    fig.text(0.125, -0.02,
             "All 7 workloads in the confirmation run · medians of 9 interleaved rounds\n"
             "Prebuilt processes, startup included · no Rust measurement for scan/split",
             fontsize=9, color="#475569")
    save(fig, "showcase-runtime.svg")


def builds():
    data = read("bench/parity/debug_speedup_20261009.json")["rebuild"]
    modes = (("debug", "Debug"), ("optimized_debug", "Optimized Debug (experimental)"),
             ("release", "Release"))
    phases = ("cold", "edit", "replay")
    fig, ax = plt.subplots(figsize=(10, 4.3))
    for offset, (mode, label) in enumerate(modes):
        values = []
        for phase in phases:
            result = data[mode][phase]
            assert math.isclose(result["median_s"], median(result["samples_s"]))
            values.append(1000 * result["median_s"])
        bars = ax.barh([i + (offset - 1) * 0.23 for i in range(3)], values,
                       height=0.21, label=label, color=COLORS[offset])
        ax.bar_label(bars, labels=[f"{v:.0f} ms" for v in values], padding=4, fontsize=10)
    ax.set_yticks(range(3), ["Fresh guest objects", "Leaf edit", "Unchanged build"])
    ax.invert_yaxis()
    ax.set_xlim(0, 245)
    ax.set_xlabel("Build elapsed time (ms) · lower is better")
    ax.set_title("Small-project rebuilds · 9 October 2026", loc="left", pad=48,
                 fontsize=19, weight="bold")
    ax.legend(loc="lower left", bbox_to_anchor=(0, 1.02), ncol=3, frameon=False,
              fontsize=9)
    ax.xaxis.grid(True, color="#e2e8f0")
    ax.set_axisbelow(True)
    ax.tick_params(axis="y", length=0, pad=8)
    fig.text(0.125, -0.05,
             "Nine-module invoice project · medians of 7 trials · Debug-built compiler\n"
             "Runtime and toolchain caches prewarmed, including the fresh-object case",
             fontsize=9, color="#475569")
    save(fig, "showcase-builds.svg")


if __name__ == "__main__":
    runtime()
    builds()

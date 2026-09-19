#!/usr/bin/env python3
"""Render the Zig-vs-mylang S-expression reader comparison charts.

Reads experiments/sexpr-port/evidence/metrics.json (produced by metrics.py)
and writes PNGs into experiments/sexpr-port/evidence/.

Needs matplotlib; run with a Python that has it, e.g.
  /home/epentland/ai/canopy/rust-workflow/.venv/bin/python \
      experiments/sexpr-port/charts.py
"""

from __future__ import annotations

import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

REPO = Path(__file__).resolve().parents[2]
EVIDENCE = REPO / "experiments/sexpr-port/evidence"

MODULES = ["ast", "tokenizer", "parser", "printer"]
ZIG_COLOR = "#2f6f9f"
MY_COLOR = "#e2793a"
CODE_COLOR = "#2f6f9f"
COMMENT_COLOR = "#8fb8d6"
BLANK_COLOR = "#e6e6e6"


def load() -> dict:
    return json.loads((EVIDENCE / "metrics.json").read_text())


def bar_labels(ax, bars, fmt="{:.0f}", dy=1.0):
    for bar in bars:
        height = bar.get_height()
        ax.annotate(
            fmt.format(height),
            xy=(bar.get_x() + bar.get_width() / 2, height),
            xytext=(0, 2),
            textcoords="offset points",
            ha="center",
            va="bottom",
            fontsize=9,
        )


def figure_comparison(data: dict) -> Path:
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    fig.suptitle(
        "S-expression reader: mylang port vs the Zig implementation (eda/src/sexpr)",
        fontsize=15,
        fontweight="bold",
    )

    # 1. total lines per module
    ax = axes[0][0]
    x = np.arange(len(MODULES))
    width = 0.38
    zig = [data["zig"].get(m, {}).get("total", 0) for m in MODULES]
    my = [data["mylang"].get(m, {}).get("total", 0) for m in MODULES]
    b1 = ax.bar(x - width / 2, zig, width, label="Zig", color=ZIG_COLOR)
    b2 = ax.bar(x + width / 2, my, width, label="mylang", color=MY_COLOR)
    bar_labels(ax, b1)
    bar_labels(ax, b2)
    ax.set_xticks(x, MODULES)
    ax.set_ylabel("lines (incl. blank + comments)")
    ax.set_title("Total lines per module")
    ax.legend()
    ax.grid(axis="y", alpha=0.3)

    # 2. core composition (ast + tokenizer + parser)
    ax = axes[0][1]
    zig_core = data["totals"]["zig_core"]
    my_core = data["totals"]["my_core"]
    groups = ["Zig core\n(ast+tok+parser)", "mylang core\n(ast+tok+parser)"]
    code = [zig_core["code"], my_core["code"]]
    comment = [zig_core["comment"], my_core["comment"]]
    blank = [zig_core["blank"], my_core["blank"]]
    xs = np.arange(2)
    ax.bar(xs, code, 0.5, label="code", color=CODE_COLOR)
    ax.bar(xs, comment, 0.5, bottom=code, label="comment", color=COMMENT_COLOR)
    bottoms = [c + m for c, m in zip(code, comment)]
    ax.bar(xs, blank, 0.5, bottom=bottoms, label="blank", color=BLANK_COLOR)
    for xi, (c, cm, bl) in enumerate(zip(code, comment, blank)):
        ax.text(xi, c / 2, f"{c}", ha="center", va="center", color="white", fontweight="bold")
        ax.text(xi, c + cm / 2, f"{cm}", ha="center", va="center", color="#20415c")
        ax.text(xi, c + cm + bl / 2, f"{bl}", ha="center", va="center", color="#555555")
        ax.text(xi, c + cm + bl + 15, f"{c + cm + bl}", ha="center", va="bottom", fontweight="bold")
    ax.set_xticks(xs, groups)
    ax.set_ylabel("lines")
    ax.set_title("Line composition of the core reader")
    ax.legend()
    ax.grid(axis="y", alpha=0.3)

    # 3. declarations and tests
    ax = axes[1][0]
    metrics = ["functions", "types", "test cases"]
    zig_vals = [
        data["totals"]["zig_all"]["decls"].get("fn", 0),
        data["totals"]["zig_all"]["decls"].get("type", 0),
        data["totals"]["zig_all"]["tests"],
    ]
    my_all = data["totals"]["my_all"]
    my_vals = [
        my_all["decls"].get("fn", 0),
        my_all["decls"].get("type", 0),
        my_all["tests"] + data["totals"]["my_tests"]["tests"],
    ]
    x = np.arange(len(metrics))
    b1 = ax.bar(x - width / 2, zig_vals, width, label="Zig", color=ZIG_COLOR)
    b2 = ax.bar(x + width / 2, my_vals, width, label="mylang", color=MY_COLOR)
    bar_labels(ax, b1)
    bar_labels(ax, b2)
    ax.set_xticks(x, metrics)
    ax.set_title("Declarations (Zig: all 4 modules; guest tests counted separately)")
    ax.legend()
    ax.grid(axis="y", alpha=0.3)

    # 4. code characters per module
    ax = axes[1][1]
    x = np.arange(len(MODULES))
    zig_chars = [data["zig"].get(m, {}).get("chars", 0) for m in MODULES]
    my_chars = [data["mylang"].get(m, {}).get("chars", 0) for m in MODULES]
    b1 = ax.bar(x - width / 2, zig_chars, width, label="Zig", color=ZIG_COLOR)
    b2 = ax.bar(x + width / 2, my_chars, width, label="mylang", color=MY_COLOR)
    bar_labels(ax, b1)
    bar_labels(ax, b2)
    ax.set_xticks(x, MODULES)
    ax.set_ylabel("characters in file")
    ax.set_title("Source size in characters")
    ax.legend()
    ax.grid(axis="y", alpha=0.3)

    fig.tight_layout(rect=(0, 0, 1, 0.96))
    out = EVIDENCE / "sexpr-loc-comparison.png"
    fig.savefig(out, dpi=130)
    plt.close(fig)
    return out


def figure_context(data: dict) -> Path:
    fig, axes = plt.subplots(1, 2, figsize=(14, 6))
    fig.suptitle(
        "How the port compares, and how it sits beside earlier mylang readers",
        fontsize=15,
        fontweight="bold",
    )

    # ratio per module
    ax = axes[0]
    labels = []
    ratios = []
    for m in MODULES:
        z = data["zig"].get(m, {}).get("total", 0)
        y = data["mylang"].get(m, {}).get("total", 0)
        if z:
            labels.append(m)
            ratios.append(y / z)
    zc = data["totals"]["zig_core"]["total"]
    yc = data["totals"]["my_core"]["total"]
    labels.append("core total")
    ratios.append(yc / zc)
    colors = [MY_COLOR if r < 1 else "#b23b3b" for r in ratios]
    bars = ax.barh(np.arange(len(labels)), ratios, color=colors)
    ax.axvline(1.0, color="#444444", linestyle="--", linewidth=1)
    for bar, r in zip(bars, ratios):
        ax.text(bar.get_width() + 0.02, bar.get_y() + bar.get_height() / 2, f"{r:.2f}x", va="center", fontsize=10)
    ax.set_yticks(np.arange(len(labels)), labels)
    ax.set_xlabel("mylang lines / Zig lines")
    ax.set_title("Line-count ratio (below 1.0 = shorter)")
    ax.set_xlim(0, max(ratios) * 1.25)
    ax.grid(axis="x", alpha=0.3)

    # context: total lines of each reader
    ax = axes[1]
    names = ["Zig sexpr\n(4 modules)"]
    values = [data["totals"]["zig_all"]["total"]]
    colors = [ZIG_COLOR]
    names.append("mylang port\n(4 modules)")
    values.append(data["totals"]["my_all"]["total"])
    colors.append(MY_COLOR)
    for name, entry in data["context"].items():
        names.append(name.replace("readiness/", "probe\n"))
        values.append(entry["total"])
        colors.append("#6aa84f")
    bars = ax.bar(np.arange(len(names)), values, color=colors)
    bar_labels(ax, bars)
    ax.set_xticks(np.arange(len(names)), names, fontsize=9)
    ax.set_ylabel("total lines")
    ax.set_title("Reader size in context")
    ax.grid(axis="y", alpha=0.3)

    fig.tight_layout(rect=(0, 0, 1, 0.93))
    out = EVIDENCE / "sexpr-loc-context.png"
    fig.savefig(out, dpi=130)
    plt.close(fig)
    return out


def main() -> int:
    data = load()
    for path in (figure_comparison(data), figure_context(data)):
        print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

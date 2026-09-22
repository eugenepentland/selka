#!/usr/bin/env python3
"""Render the GC/arena/native full-SVG runtime comparison.

The figure deliberately contains runtime only.  This measurement batch has no
RSS observations, so older memory measurements must not be combined with it.

Run from the repository root:

  MPLCONFIGDIR=$PWD/.tmp/mplcfg \
    /home/epentland/ai/canopy/rust-workflow/.venv/bin/python \
    experiments/svg-arenas-20260921/charts.py
"""

from __future__ import annotations

import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.ticker import MaxNLocator  # noqa: E402


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
INPUT = HERE / "native-measurements.json"
FIGURE_STEM = ROOT / "docs/audits/figures/full-svg-gc-arena-native-2026-09-21"

CASES = (
    ("fixture", "Fixture"),
    ("changed-net", "Changed net"),
    ("changed-value", "Changed value"),
)

# Keep related builds adjacent.  Colour denotes implementation family; bounded
# variants use a lighter shade because the limit is part of the build setup.
ARMS = (
    ("netlisp", "Zig NetLisp\n(different engine/output)", "#7A8491"),
    ("rust-o3", "Rust O3\n(same SVG)", "#D66A3A"),
    ("go-fast", "Go default optimization\n(same SVG)", "#18A4C7"),
    ("zig-o3", "Zig ReleaseFast\n(same SVG)", "#EAA629"),
    ("gc-o3", "mylang GC · LLVM O3", "#446CB3"),
    ("gc-lto", "mylang GC · LLVM O3 + LTO", "#274B87"),
    ("gc-bounded", "mylang GC · LLVM O3 · tool limits", "#8DA7D6"),
    ("gc-lto-bounded", "mylang GC · LLVM O3 + LTO · tool limits", "#6888C2"),
    ("arena-o3", "mylang arena · LLVM O3", "#3D8B63"),
    ("arena-lto", "mylang arena · LLVM O3 + LTO", "#236744"),
    ("arena-bounded", "mylang arena · LLVM O3 · tool limits", "#8DBCA1"),
    ("arena-lto-bounded", "mylang arena · LLVM O3 + LTO · tool limits", "#66A17F"),
)


def load_measurements() -> dict:
    if not INPUT.exists():
        raise SystemExit(
            f"missing input: {INPUT}\n"
            "Create native-measurements.json, then rerun the command in this "
            "script's docstring."
        )

    data = json.loads(INPUT.read_text())
    summary = data.get("summary")
    if not isinstance(summary, dict):
        raise SystemExit(f"{INPUT}: missing object 'summary'")

    errors = []
    for case, _ in CASES:
        medians = summary.get(case, {}).get("median_ms", {})
        for arm, _, _ in ARMS:
            value = medians.get(arm)
            if not isinstance(value, (int, float)) or value <= 0:
                errors.append(f"summary.{case}.median_ms.{arm}")
    if errors:
        raise SystemExit(
            f"{INPUT}: missing or non-positive numeric values:\n  "
            + "\n  ".join(errors)
        )
    return data


def main() -> None:
    data = load_measurements()
    summary = data["summary"]
    all_values = [
        summary[case]["median_ms"][arm]
        for case, _ in CASES
        for arm, _, _ in ARMS
    ]
    axis_max = max(all_values) * 1.17

    plt.rcParams.update(
        {
            "font.family": "DejaVu Sans",
            "axes.titleweight": "bold",
            "axes.titlesize": 12,
            "axes.labelsize": 10,
            "xtick.labelsize": 9,
            "ytick.labelsize": 9,
        }
    )
    figure, axes = plt.subplots(
        1,
        3,
        figsize=(17, 8.8),
        sharex=True,
        sharey=True,
        gridspec_kw={"wspace": 0.08},
    )
    positions = list(range(len(ARMS)))
    labels = [label for _, label, _ in ARMS]
    colours = [colour for _, _, colour in ARMS]

    for axis, (case, title) in zip(axes, CASES):
        values = [summary[case]["median_ms"][arm] for arm, _, _ in ARMS]
        bars = axis.barh(positions, values, height=0.72, color=colours)
        axis.set_title(title, pad=11)
        axis.set_xlim(0, axis_max)
        axis.xaxis.set_major_locator(MaxNLocator(nbins=5, min_n_ticks=4))
        axis.grid(axis="x", color="#D8DCE2", linewidth=0.8)
        axis.set_axisbelow(True)
        axis.spines[["top", "right", "left"]].set_visible(False)
        axis.tick_params(axis="y", length=0)
        for bar, value in zip(bars, values):
            axis.text(
                value + axis_max * 0.012,
                bar.get_y() + bar.get_height() / 2,
                f"{value:.2f}",
                va="center",
                ha="left",
                fontsize=8,
                color="#27313D",
            )

    axes[0].set_yticks(positions, labels)
    axes[0].invert_yaxis()
    axes[1].set_xlabel("Median fresh-process wall time (ms) · shared linear scale")

    figure.suptitle(
        "Full SVG generation: native ports, mylang GC, and mylang arenas",
        x=0.055,
        y=0.968,
        ha="left",
        fontsize=17,
        fontweight="bold",
    )
    figure.text(
        0.055,
        0.925,
        "31 timed rounds after 3 warmups on CPU 6 · one fresh process per run",
        ha="left",
        fontsize=10.5,
        color="#46515E",
    )
    figure.text(
        0.055,
        0.042,
        "End-to-end timing includes startup, input read, parse, layout, routing, SVG file write, and shutdown. "
        "Runtime only; this batch contains no RSS measurements.",
        ha="left",
        fontsize=9,
        color="#46515E",
    )
    figure.text(
        0.055,
        0.019,
        "Tool limits: step and call-depth checks; all mylang builds use a 256 MiB managed memory budget.",
        ha="left",
        fontsize=9,
        color="#46515E",
    )
    figure.subplots_adjust(left=0.34, right=0.985, top=0.875, bottom=0.105)

    FIGURE_STEM.parent.mkdir(parents=True, exist_ok=True)
    outputs = (FIGURE_STEM.with_suffix(".png"), FIGURE_STEM.with_suffix(".svg"))
    figure.savefig(outputs[0], dpi=180, facecolor="white")
    figure.savefig(outputs[1], facecolor="white")
    plt.close(figure)
    for output in outputs:
        print(output)


if __name__ == "__main__":
    main()

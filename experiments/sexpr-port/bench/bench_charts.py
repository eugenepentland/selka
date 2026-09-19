#!/usr/bin/env python3
"""Render the mylang-vs-Zig speed comparison from evidence/bench*.json.

Writes:
  evidence/sexpr-speed-comparison.png         main compile + execution comparison
  evidence/sexpr-speed-compiler-modes.png     effect of the mylang compiler's own mode

Every axis is linear. Because the raw ranges span four orders of magnitude
(0.016 s to 79 s), the panels are grouped by magnitude instead of compressed
with a log axis: cold builds, project-cold builds, warm/incremental builds, and
Zig and mylang execution each get their own linear scale.

The mylang compile panels use the ReleaseFast-built compiler from
`bench-compiler.json` when that file exists (the fair configuration); execution
numbers always come from `bench.json`, which does not depend on the compiler's
own mode.

Needs matplotlib; run with a Python that has it, e.g.
  /home/epentland/ai/canopy/rust-workflow/.venv/bin/python \
      experiments/sexpr-port/bench/bench_charts.py
"""

from __future__ import annotations

import json
import statistics
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

EVIDENCE = Path(__file__).resolve().parents[1] / "evidence"

ZIG_COLOR = "#2f6f9f"
ZIG_SAFE_COLOR = "#7fb2d6"
MY_COLOR = "#e2793a"
MY_DEBUG_COLOR = "#f0b184"

MEASURES = ["cold", "cold_local", "warm", "tweak"]
MEASURE_LABELS = ["cold\n(all caches empty)", "cold project\n(toolchain warm)", "warm\n(nothing changed)", "after tweak\n(incremental)"]
PHASES = ["frontend_seconds", "codegen_seconds", "link_seconds"]
PHASE_LABELS = ["frontend", "codegen", "link"]
PHASE_COLORS = ["#2f6f9f", "#e2793a", "#8fbf6a"]


def median_phase(samples, key):
    values = [s.get(key) for s in samples if s.get(key) is not None]
    return statistics.median(values) if values else 0.0


def load_compiler():
    path = EVIDENCE / "bench-compiler.json"
    return json.loads(path.read_text()) if path.exists() else None


def annotate_bars(ax, bars, values, fmt="{:.2f}", rotation=0, dy=2):
    for bar, value in zip(bars, values):
        ax.annotate(fmt.format(value), xy=(bar.get_x() + bar.get_width() / 2, value), xytext=(0, dy),
                    textcoords="offset points", ha="center", va="bottom", fontsize=8, rotation=rotation)


def main() -> int:
    data = json.loads((EVIDENCE / "bench.json").read_text())
    compiler = load_compiler()
    fast = compiler["guest_compile"]["ReleaseFast"] if compiler else None

    def zc(measure):
        return data["zig"]["ReleaseFast"][measure]["median"]

    def mc(measure):
        """mylang compile time with its compiler built ReleaseFast."""
        if fast:
            return fast[measure]["median"]
        return data["mylang"]["ReleaseFast"][measure]["median"]

    # Three compile configs, each with the same (ReleaseFast) compiler on the
    # mylang side so the bars are directly comparable.
    configs = [("Zig ReleaseFast", ZIG_COLOR, lambda m: zc(m)),
               ("Zig ReleaseSafe", ZIG_SAFE_COLOR, lambda m: data["zig"]["ReleaseSafe"][m]["median"]),
               ("mylang ReleaseFast", MY_COLOR, mc)]

    fig, axes = plt.subplots(2, 3, figsize=(17, 9.5))
    fig.suptitle(
        "sexpr: mylang port vs Zig — compile (cold/project-cold/warm/tweak) and execution speed"
        + ("   [mylang compiler built ReleaseFast; all axes linear]" if fast else "   [all axes linear]"),
        fontsize=15, fontweight="bold",
    )

    # 1. cold compile
    ax = axes[0][0]
    values = [fn("cold") for _, _, fn in configs]
    bars = ax.bar([n.replace(" ", "\n") for n, _, _ in configs], values,
                  color=[c for _, c, _ in configs])
    annotate_bars(ax, bars, values, "{:.2f}s")
    ax.set_ylim(0, max(values) * 1.18)
    ax.set_ylabel("seconds")
    ax.set_title("Compile: cold (all caches empty)")
    ax.grid(axis="y", alpha=0.3)

    # 2. project-cold compile
    ax = axes[0][1]
    values = [fn("cold_local") for _, _, fn in configs]
    bars = ax.bar([n.replace(" ", "\n") for n, _, _ in configs], values,
                  color=[c for _, c, _ in configs])
    annotate_bars(ax, bars, values, "{:.2f}s")
    ax.set_ylim(0, max(values) * 1.18)
    ax.set_ylabel("seconds")
    ax.set_title("Compile: cold project (toolchain warm)")
    ax.grid(axis="y", alpha=0.3)

    # 3. warm vs tweak
    ax = axes[0][2]
    x = np.arange(2)
    width = 0.26
    warm = [fn("warm") for _, _, fn in configs]
    tweak = [fn("tweak") for _, _, fn in configs]
    for i, (name, color, _) in enumerate(configs):
        offset = (i - 1) * width
        b1 = ax.bar(x[0] + offset, warm[i], width, color=color)
        b2 = ax.bar(x[1] + offset, tweak[i], width, color=color, label=name)
        annotate_bars(ax, b1, [warm[i]], "{:.3f}s", rotation=90)
        annotate_bars(ax, b2, [tweak[i]], "{:.3f}s", rotation=90)
    ax.set_xticks(x, ["warm (nothing changed)", "after one-constant tweak"])
    ax.set_ylim(0, (max(warm + tweak)) * 1.35)
    ax.set_ylabel("seconds")
    ax.set_title("Compile: warm and incremental (same scale)")
    ax.legend(fontsize=8)
    ax.grid(axis="y", alpha=0.3)

    # 4. Zig execution (its own linear scale)
    ax = axes[1][0]
    x = np.arange(2)
    width = 0.35
    for i, (label, color, key) in enumerate((("ReleaseFast", ZIG_COLOR, "ReleaseFast"),
                                             ("ReleaseSafe", ZIG_SAFE_COLOR, "ReleaseSafe"))):
        values = [data["zig"][key]["execute"][w]["median"] * 1000 for w in ("stats", "render")]
        bars = ax.bar(x + (i - 0.5) * width, values, width, label=label, color=color)
        annotate_bars(ax, bars, values, "{:.2f}ms")
    ax.set_xticks(x, ["census (parse + walk)", "render (parse + print)"])
    ax.set_ylim(0, 7.5)
    ax.set_ylabel("milliseconds per run")
    ax.set_title("Execute: Zig (927 KB input, median of 25)")
    ax.legend(fontsize=8)
    ax.grid(axis="y", alpha=0.3)

    # 5. mylang execution (its own linear scale)
    ax = axes[1][1]
    for i, (label, color, key) in enumerate((("ReleaseFast", MY_COLOR, "ReleaseFast"),
                                             ("Debug", MY_DEBUG_COLOR, "Debug"))):
        values = [data["mylang"][key]["execute"][w]["median"] * 1000 for w in ("stats", "render")]
        bars = ax.bar(x + (i - 0.5) * width, values, width, label=label, color=color)
        annotate_bars(ax, bars, values, "{:.0f}ms")
    ax.set_xticks(x, ["census (parse + walk)", "render (parse + print)"])
    ax.set_ylim(0, 1200)
    ax.set_ylabel("milliseconds per run")
    ax.set_title("Execute: mylang (927 KB input, median of 25)")
    ax.legend(fontsize=8)
    ax.grid(axis="y", alpha=0.3)

    # 6. who is faster, as a factor >= 1 (linear, no log needed)
    ax = axes[1][2]
    factors = [
        ("compile cold", zc("cold") / mc("cold"), "mylang"),
        ("compile cold project", zc("cold_local") / mc("cold_local"), "mylang"),
        ("compile after tweak", zc("tweak") / mc("tweak"), "mylang"),
        ("compile warm", mc("warm") / zc("warm"), "Zig"),
        ("run: census", data["mylang"]["ReleaseFast"]["execute"]["stats"]["median"] / data["zig"]["ReleaseFast"]["execute"]["stats"]["median"], "Zig"),
        ("run: render", data["mylang"]["ReleaseFast"]["execute"]["render"]["median"] / data["zig"]["ReleaseFast"]["execute"]["render"]["median"], "Zig"),
    ]
    names = [f[0] for f in factors]
    values = [f[1] for f in factors]
    colors = ["#e2793a" if f[2] == "mylang" else "#2f6f9f" for f in factors]
    bars = ax.barh(np.arange(len(factors)), values, color=colors)
    for bar, factor, (_, _, winner) in zip(bars, values, factors):
        ax.text(bar.get_width() + max(values) * 0.02, bar.get_y() + bar.get_height() / 2,
                f"{factor:.1f}x  {winner} faster", va="center", fontsize=9)
    ax.set_yticks(np.arange(len(factors)), names)
    ax.invert_yaxis()
    ax.set_xlim(0, max(values) * 1.45)
    ax.set_xlabel("factor (linear; always >= 1, colour shows who wins)")
    ax.set_title("Who is faster, and by how much (ReleaseFast)")
    ax.grid(axis="x", alpha=0.3)

    fig.tight_layout(rect=(0, 0, 1, 0.94))
    out = EVIDENCE / "sexpr-speed-comparison.png"
    fig.savefig(out, dpi=130)
    plt.close(fig)
    print(f"wrote {out}")

    if compiler:
        figure_compiler_modes(compiler)
    return 0


def figure_compiler_modes(compiler: dict) -> None:
    modes = list(compiler["guest_compile"].keys())
    mode_colors = {"Debug": "#8a8a8a", "ReleaseFast": MY_COLOR, "ReleaseSafe": ZIG_COLOR}

    def value(mode, measure):
        return compiler["guest_compile"][mode][measure]["median"]

    fig, axes = plt.subplots(2, 2, figsize=(14, 9.5))
    fig.suptitle("How much does the mylang compiler's own optimize mode matter? (all axes linear)",
                 fontsize=15, fontweight="bold")

    # A. cold guest build by compiler mode
    ax = axes[0][0]
    values = [value(m, "cold") for m in modes]
    bars = ax.bar(modes, values, color=[mode_colors[m] for m in modes])
    annotate_bars(ax, bars, values, "{:.2f}s")
    ax.set_ylim(0, max(values) * 1.2)
    ax.set_ylabel("seconds")
    ax.set_title("Guest build: cold")
    ax.grid(axis="y", alpha=0.3)

    # B. warm and tweak by compiler mode (same linear scale)
    ax = axes[0][1]
    x = np.arange(2)
    width = 0.3
    for i, mode in enumerate(modes):
        values = [value(mode, "warm"), value(mode, "tweak")]
        bars = ax.bar(x + (i - 1) * width, values, width, label=f"compiler {mode}", color=mode_colors[mode])
        annotate_bars(ax, bars, values, "{:.3f}s", rotation=90)
    ax.set_xticks(x, ["warm (nothing changed)", "after one-constant tweak"])
    ax.set_ylim(0, 0.95)
    ax.set_ylabel("seconds")
    ax.set_title("Guest build: warm and incremental")
    ax.legend(fontsize=8)
    ax.grid(axis="y", alpha=0.3)

    # C. phases with the ReleaseFast compiler
    ax = axes[1][0]
    samples = {m: compiler["guest_compile"]["ReleaseFast"][m]["samples"] for m in MEASURES}
    x = np.arange(len(MEASURES))
    bottoms = np.zeros(len(MEASURES))
    for phase, label, color in zip(PHASES, PHASE_LABELS, PHASE_COLORS):
        values = np.array([median_phase(samples[m], phase) for m in MEASURES])
        ax.bar(x, values, 0.5, bottom=bottoms, label=label, color=color)
        for xi, (val, bottom) in enumerate(zip(values, bottoms)):
            if val > 0.05:
                ax.text(xi, bottom + val / 2, f"{val:.2f}", ha="center", va="center", fontsize=8,
                        color="white" if phase != "link_seconds" else "#333333")
        bottoms += values
    for xi, m in enumerate(MEASURES):
        ax.text(xi, bottoms[xi] + 0.03, f"{value('ReleaseFast', m):.2f}s", ha="center", va="bottom",
                fontsize=8, fontweight="bold")
    ax.set_xticks(x, MEASURE_LABELS, fontsize=9)
    ax.set_ylim(0, max(bottoms) * 1.2)
    ax.set_ylabel("seconds")
    ax.set_title("mylang build phases (ReleaseFast compiler)")
    ax.legend(fontsize=8)
    ax.grid(axis="y", alpha=0.3)

    # D. speedup from optimizing the compiler
    ax = axes[1][1]
    items = [("cold", "cold"), ("warm", "warm"), ("after tweak", "tweak")]
    x = np.arange(len(items))
    for i, mode in enumerate(("ReleaseFast", "ReleaseSafe")):
        ratios = [value("Debug", m) / value(mode, m) for _, m in items]
        bars = ax.bar(x + (i - 0.5) * 0.35, ratios, 0.35, label=f"{mode} vs Debug", color=mode_colors[mode])
        annotate_bars(ax, bars, ratios, "{:.2f}x")
    ax.axhline(1.0, color="#444444", linestyle="--", linewidth=1)
    ax.set_xticks(x, [i[0] for i in items])
    ax.set_ylim(0, 10)
    ax.set_ylabel("time relative to the Debug compiler (linear)")
    ax.set_title("Speedup from optimizing the compiler itself")
    ax.legend(fontsize=8)
    ax.grid(axis="y", alpha=0.3)

    fig.tight_layout(rect=(0, 0, 1, 0.93))
    out = EVIDENCE / "sexpr-speed-compiler-modes.png"
    fig.savefig(out, dpi=130)
    plt.close(fig)
    print(f"wrote {out}")


if __name__ == "__main__":
    raise SystemExit(main())

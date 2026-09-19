#!/usr/bin/env python3
"""Render the execution-gap audit from evidence/audit.json + variants.json.

Writes experiments/sexpr-audit/evidence/sexpr-audit.png (all axes linear).

Needs matplotlib; run with e.g.
  /home/epentland/ai/canopy/rust-workflow/.venv/bin/python \
      experiments/sexpr-audit/audit_charts.py
"""

from __future__ import annotations

import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

AUDIT = Path(__file__).resolve().parent
EVIDENCE = AUDIT / "evidence"
MY = "#e2793a"
ZIG = "#2f6f9f"


def main() -> int:
    data = json.loads((EVIDENCE / "audit.json").read_text())
    variants = json.loads((EVIDENCE / "variants.json").read_text())
    attr = data["attribution"]
    micro = data["micro"]

    fig, axes = plt.subplots(2, 2, figsize=(15, 10))
    fig.suptitle("Why the mylang sexpr port is ~60x slower: execution-gap audit (linear axes)",
                 fontsize=15, fontweight="bold")

    # A. phase totals, stacked by implementation
    ax = axes[0][0]
    phases = ["read", "tokenize", "parse", "walk"]
    labels = ["read", "tokenize", "parse", "walk the AST"]
    colors = ["#b0b0b0", "#c0392b", "#e2793a", "#f0b184"]
    bottoms = {"mylang": 0.0, "zig": 0.0}
    for phase, label, color in zip(phases, labels, colors):
        values = [attr[impl][phase] for impl in ("mylang", "zig")]
        ax.bar(["mylang", "Zig"], values, 0.5, bottom=[bottoms["mylang"], bottoms["zig"]],
               label=label, color=color)
        for xi, (impl, value) in enumerate(zip(("mylang", "zig"), values)):
            if value > 2:
                ax.text(xi, bottoms[impl] + value / 2, f"{value:.1f}", ha="center", va="center",
                        fontsize=8, color="white" if color != "#f0b184" else "#333333")
        for impl, value in zip(("mylang", "zig"), values):
            bottoms[impl] += value
    for xi, impl in enumerate(("mylang", "zig")):
        ax.text(xi, bottoms[impl] + 2, f"{attr[impl]['census_total']:.1f} ms total", ha="center",
                va="bottom", fontsize=9, fontweight="bold")
    ax.set_ylabel("milliseconds (census run)")
    ax.set_ylim(0, 160)
    ax.set_title("Where census time goes: tokenize is 92% of mylang's run")
    ax.legend(fontsize=8)
    ax.grid(axis="y", alpha=0.3)

    # B. per-phase ratio
    ax = axes[0][1]
    keys = ["read", "tokenize", "parse", "walk", "render_extra"]
    ratios = [attr["mylang"][k] / attr["zig"][k] if attr["zig"][k] > 1e-9 else 0 for k in keys]
    bars = ax.barh(np.arange(len(keys)), ratios, color=[MY] * len(keys))
    for bar, ratio in zip(bars, ratios):
        ax.text(bar.get_width() + 3, bar.get_y() + bar.get_height() / 2, f"{ratio:.1f}x",
                va="center", fontsize=9)
    ax.set_yticks(np.arange(len(keys)), ["read", "tokenize", "parse", "walk", "render"])
    ax.invert_yaxis()
    ax.set_xlim(0, max(ratios) * 1.25)
    ax.set_xlabel("mylang / Zig (linear)")
    ax.set_title("Per-phase slowdown (ReleaseFast)")
    ax.grid(axis="x", alpha=0.3)

    # C. micro workloads
    ax = axes[1][0]
    names = [k for k in ("loop (empty)", "scan (2 compares)") if k in micro["zig"]]
    n = 927415
    x = np.arange(len(names))
    for i, (impl, color) in enumerate((("mylang", MY), ("zig", ZIG))):
        values = [micro[impl][k]["median_ms"] for k in names]
        bars = ax.bar(x + (i - 0.5) * 0.35, values, 0.35, label=impl, color=color)
        for bar, value in zip(bars, values):
            ax.text(bar.get_x() + bar.get_width() / 2, value, f"{value / n * 1e6:.1f} ns/byte",
                    ha="center", va="bottom", fontsize=8, rotation=90)
    ax.set_xticks(x, names)
    ax.set_ylabel("milliseconds for 927,415 iterations")
    ax.set_title("Generated-code cost per byte (same loop, both sides)")
    ax.legend(fontsize=8)
    ax.grid(axis="y", alpha=0.3)

    # D. instrumentation counterfactual
    ax = axes[1][1]
    rows = ["empty loop", "byte scan", "tokenize", "census"]
    x = np.arange(len(rows))
    series = [("baseline", "baseline", "#8a8a8a"),
              ("no per-op step check", "nostep", "#e2793a"),
              ("no step check + no position marker", "nomark", "#2f6f9f")]
    for i, (label, key, color) in enumerate(series):
        values = [variants[r][key] for r in rows]
        bars = ax.bar(x + (i - 1) * 0.27, values, 0.27, label=label, color=color)
        for bar, value in zip(bars, values):
            ax.text(bar.get_x() + bar.get_width() / 2, value, f"{value:.1f}", ha="center",
                    va="bottom", fontsize=7)
    ax.set_xticks(x, rows)
    ax.set_ylabel("milliseconds")
    ax.set_title("Removing per-instruction instrumentation (patched compiler)")
    ax.legend(fontsize=8)
    ax.grid(axis="y", alpha=0.3)

    fig.tight_layout(rect=(0, 0, 1, 0.94))
    out = EVIDENCE / "sexpr-audit.png"
    fig.savefig(out, dpi=130)
    plt.close(fig)
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

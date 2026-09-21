#!/usr/bin/env python3
"""Render the backend comparison and recompilation charts.

Reads the two measurement reports this directory produces:

* `measure.json`   - `measure.py`, wall-clock runtime per arm and workload;
* `incremental.json` - `qualify_incremental.py`, the cold/project-cold/warm/
  after-tweak compile series per arm.

and writes PNGs into `docs/audits/figures/`. Needs matplotlib; run it with the
interpreter that has it:

  /home/epentland/ai/canopy/rust-workflow/.venv/bin/python \
      experiments/llvm-backend/backend_charts.py

Every panel carries its own numbers, so a reader can check a bar against the
report it came from without opening the JSON. Ratios are quoted against the
bundled QBE arm, because that is the default a mylang user gets.
"""

from __future__ import annotations

import argparse
import json
from datetime import date
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
FIGURES = REPO / "docs" / "audits" / "figures"

#: arm -> (label, colour). Zig is the reference implementation; the three mylang
#: arms share a family so the backend question reads at a glance.
STYLE = {
    "zig": ("Zig (ReleaseFast)", "#4c566a"),
    "qbe": ("mylang + QBE", "#5e81ac"),
    "llvm-o2": ("mylang + LLVM -O2", "#d08770"),
    "llvm-o3": ("mylang + LLVM -O3", "#a3be8c"),
}
#: The order arms appear in every panel.
ORDER = ("zig", "qbe", "llvm-o2", "llvm-o3")
STAGES = (("cold", "cold\n(all caches empty)"), ("cold_local", "project-cold\n(toolchain warm)"),
          ("warm", "warm\n(nothing changed)"), ("tweak", "after change\n(one constant)"))


def load(path: Path) -> dict:
    """One measurement report, or an empty report when it has not been run."""
    return json.loads(path.read_text()) if path.is_file() else {}


def runtime_panel(ax, report: dict, workloads: list[str], title: str) -> None:
    """Grouped wall-clock bars for one pair of input sizes."""
    arms = [arm for arm in ORDER if arm in report.get("workloads", {}).get(workloads[0], {}).get("arms", {})]
    width = 0.8 / len(arms)
    for index, arm in enumerate(arms):
        values = [report["workloads"][workload]["arms"][arm]["wall_ms_median"] for workload in workloads]
        positions = np.arange(len(workloads)) + index * width - 0.4 + width / 2
        bars = ax.bar(positions, values, width * 0.92, label=STYLE[arm][0], color=STYLE[arm][1])
        for bar, value in zip(bars, values):
            ax.annotate(f"{value:.1f}", (bar.get_x() + bar.get_width() / 2, value), ha="center",
                        va="bottom", fontsize=7.5, color="#2e3440")
    ax.set_xticks(np.arange(len(workloads)))
    ax.set_xticklabels([workload.split("-")[0] + ("\n7.42 MB" if "-" in workload else "\n927 KB") for workload in workloads])
    ax.set_ylabel("wall clock (ms, median)")
    ax.set_title(title, fontsize=10, fontweight="bold")
    ax.grid(axis="y", alpha=0.3)
    ax.set_axisbelow(True)
    # The ratio against QBE is the number that decides whether the LLVM arm is
    # worth its extra build cost, so it goes on the panel rather than in prose.
    for index, workload in enumerate(workloads):
        base = report["workloads"][workload]["arms"]["qbe"]["wall_ms_median"]
        for offset, arm in enumerate(arms):
            if arm == "qbe":
                continue
            ratio = base / report["workloads"][workload]["arms"][arm]["wall_ms_median"]
            position = index + offset * width - 0.4 + width / 2
            ax.annotate(f"{ratio:.2f}×", (position, 0), xytext=(0, 3), textcoords="offset points",
                        ha="center", va="bottom", fontsize=7, color="#bf616a", rotation=90)
    ax.legend(fontsize=8, frameon=False)


def compile_panel(ax, report: dict, log: bool) -> None:
    """The compile series: one group per stage, one bar per arm."""
    arms = [arm for arm in ORDER if arm in report.get("arms", {})]
    width = 0.8 / len(arms)
    for index, arm in enumerate(arms):
        values = [report["medians"][arm][stage] for stage, _ in STAGES]
        positions = np.arange(len(STAGES)) + index * width - 0.4 + width / 2
        bars = ax.bar(positions, values, width * 0.92, label=STYLE[arm][0], color=STYLE[arm][1])
        for bar, value in zip(bars, values):
            ax.annotate(f"{value:.3g}", (bar.get_x() + bar.get_width() / 2, value), ha="center",
                        va="bottom", fontsize=7, color="#2e3440")
    ax.set_xticks(np.arange(len(STAGES)))
    ax.set_xticklabels([label for _, label in STAGES], fontsize=8)
    ax.set_ylabel("wall clock (s, median)" + ("  — log scale" if log else ""))
    ax.set_yscale("log" if log else "linear")
    ax.grid(axis="y", alpha=0.3)
    ax.set_axisbelow(True)
    ax.legend(fontsize=8, frameon=False)


def runtime_figure(runtime: dict, stamp: str) -> Path:
    """Render the runtime chart: render and census, both input sizes."""
    figure, axes = plt.subplots(1, 2, figsize=(12.5, 4.6))
    runtime_panel(axes[0], runtime, ["render", "render-7.4MB"], "Schematic render — wall clock")
    runtime_panel(axes[1], runtime, ["census", "census-7.4MB"], "Schematic census — wall clock")
    identity = runtime.get("inputs", {}).get("input.sexp", {}).get("sha256", "")[:12]
    figure.suptitle("mylang backend comparison — S-expression schematic reader/renderer\n"
                    f"red numbers are the ratio against mylang+QBE (higher is better); "
                    f"input sha256 {identity}…; {runtime.get('rounds', '?')} rounds, "
                    f"{runtime.get('sink', 'capture')} stdout", fontsize=9.5)
    figure.tight_layout(rect=(0, 0, 1, 0.88))
    path = FIGURES / f"backend-comparison-{stamp}.png"
    figure.savefig(path, dpi=150)
    plt.close(figure)
    return path


def incremental_figure(incremental: dict, stamp: str) -> Path:
    """Render the compile and recompile chart: the whole series, then the rerun."""
    figure, axes = plt.subplots(1, 2, figsize=(12.5, 4.8))
    compile_panel(axes[0], incremental, log=True)
    axes[0].set_title("Compile and recompile cost", fontsize=10, fontweight="bold")
    # Right panel: the two stages a developer actually sits through on an edit,
    # on a linear axis so a 0.1 s difference is visible.
    arms = [arm for arm in ORDER if arm in incremental.get("arms", {})]
    width = 0.8 / len(arms)
    for index, arm in enumerate(arms):
        values = [incremental["medians"][arm]["warm"], incremental["medians"][arm]["tweak"]]
        positions = np.arange(2) + index * width - 0.4 + width / 2
        bars = axes[1].bar(positions, values, width * 0.92, label=STYLE[arm][0], color=STYLE[arm][1])
        for bar, value in zip(bars, values):
            axes[1].annotate(f"{value * 1000:.0f} ms", (bar.get_x() + bar.get_width() / 2, value),
                             ha="center", va="bottom", fontsize=7.5, color="#2e3440")
    axes[1].set_xticks(np.arange(2))
    axes[1].set_xticklabels(["warm\n(nothing changed)", "after change\n(one constant)"], fontsize=8)
    axes[1].set_ylabel("wall clock (s, median)")
    axes[1].set_title("Recompilation on an edit", fontsize=10, fontweight="bold")
    axes[1].grid(axis="y", alpha=0.3)
    axes[1].set_axisbelow(True)
    axes[1].legend(fontsize=8, frameon=False)
    figure.suptitle("mylang backend comparison — build cost of the benchmark entry "
                    f"({incremental.get('mode', '?')}, {incremental.get('rounds', '?')} rounds, medians)\n"
                    "every arm builds the same source; the 'after change' edit is the same "
                    "one constant in each language", fontsize=9.5)
    figure.tight_layout(rect=(0, 0, 1, 0.88))
    path = FIGURES / f"backend-incremental-{stamp}.png"
    figure.savefig(path, dpi=150)
    plt.close(figure)
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", default=str(REPO / ".mylang-cache" / "bench" / "measure.json"))
    parser.add_argument("--incremental", default=str(REPO / ".mylang-cache" / "bench" / "incremental.json"))
    parser.add_argument("--stamp", default=date.today().isoformat())
    options = parser.parse_args()
    FIGURES.mkdir(parents=True, exist_ok=True)
    runtime = load(Path(options.runtime))
    incremental = load(Path(options.incremental))
    if not runtime:
        parser.error(f"no runtime report at {options.runtime}")
    written = [runtime_figure(runtime, options.stamp)]
    if incremental:
        written.append(incremental_figure(incremental, options.stamp))
    else:
        print(f"no incremental report at {options.incremental}; skipped the build chart")
    for path in written:
        print(f"wrote {path.relative_to(REPO)}  ({path.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

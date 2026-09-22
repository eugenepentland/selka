#!/usr/bin/env python3
"""Draw the full-SVG figure: four languages on one algorithm, NetLisp for scale.

Reads `measurements.json` and `memory.json` written by `measure.py` and renders
`docs/audits/figures/full-svg-native-ports-2026-09-21.png`.

  MPLCONFIGDIR=$PWD/.tmp/mplcfg \
    /home/epentland/ai/canopy/rust-workflow/.venv/bin/python \
    experiments/full-svg-benchmark/charts.py
"""
from pathlib import Path
import json

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
FIGURE = ROOT / 'docs/audits/figures/full-svg-native-ports-2026-09-21.png'
CASES = ('fixture', 'changed-net', 'changed-value')

ARMS = (
    ('netlisp-llvm-fast', 'NetLisp\n(Zig, different engine)', '#9aa4b2'),
    ('rust-o3', 'Rust -O3', '#d2691e'),
    ('go-fast', 'Go', '#00a2d8'),
    ('zig-o3', 'Zig -OReleaseFast', '#f7a41d'),
    ('mylang-o3', 'mylang LLVM O3', '#4a9eff'),
)


def main():
    measurements = json.loads((OUT / 'measurements.json').read_text())
    memory = json.loads((OUT / 'memory.json').read_text())
    summary = measurements['summary']

    figure, (runtime, rss) = plt.subplots(1, 2, figsize=(13, 5.2),
                                          gridspec_kw={'width_ratios': [2.1, 1]})
    width = 0.8 / len(ARMS)
    for index, (arm, label, colour) in enumerate(ARMS):
        offsets = [position + index * width - 0.4 + width / 2
                   for position in range(len(CASES))]
        values = [summary[case]['median_ms'][arm] for case in CASES]
        bars = runtime.bar(offsets, values, width, label=label, color=colour)
        for bar, value in zip(bars, values):
            runtime.annotate(f'{value:.2f}', (bar.get_x() + bar.get_width() / 2, value),
                             ha='center', va='bottom', fontsize=7.5, rotation=90,
                             xytext=(0, 2), textcoords='offset points')
    runtime.set_xticks(range(len(CASES)))
    runtime.set_xticklabels(CASES)
    runtime.set_yscale('log')
    runtime.set_ylabel('median process wall clock (ms, log scale)')
    runtime.set_title('Source-to-SVG, one process per run, CPU 6, 31 rounds')
    runtime.grid(axis='y', which='both', alpha=0.25)
    runtime.legend(fontsize=8, ncol=2)
    runtime.set_ylim(top=max(summary[case]['median_ms'][arm] for case in CASES
                             for arm, _, _ in ARMS) * 3.2)

    positions = range(len(ARMS))
    heights = [memory['fixture'][arm]['median_peak_rss_kib'] / 1024 for arm, _, _ in ARMS]
    rss.bar(positions, heights, color=[colour for _, _, colour in ARMS])
    for position, height in zip(positions, heights):
        rss.annotate(f'{height:.2f}', (position, height), ha='center', va='bottom',
                     fontsize=8, xytext=(0, 2), textcoords='offset points')
    rss.set_xticks(list(positions))
    rss.set_xticklabels([label.replace('\n', ' ') for _, label, _ in ARMS],
                        rotation=30, ha='right', fontsize=8)
    rss.set_ylabel('median peak RSS (MiB)')
    rss.set_title('Peak RSS, fixture')
    rss.grid(axis='y', alpha=0.25)

    figure.tight_layout()
    FIGURE.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(FIGURE, dpi=150)
    print(FIGURE)


if __name__ == '__main__':
    main()

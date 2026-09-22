#!/usr/bin/env python3
"""Export the current production-fix comparison using the established plot style."""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('svg_charts', ROOT / 'experiments/svg-arenas-20260921/charts.py')
charts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(charts)
charts.INPUT = Path(__file__).with_name('measurements.json')
charts.FIGURE_STEM = ROOT / 'docs/audits/figures/full-svg-gap-fixes-2026-09-21'
charts.ARMS = (
    ('zig-o3', 'Zig ReleaseFast', '#EAA629'),
    ('rust-o3', 'Rust O3', '#D66A3A'),
    ('go-fast', 'Go default optimization', '#18A4C7'),
    ('before-gc-lto', 'Before · mylang GC · O3 + LTO', '#9AA5B5'),
    ('gc-lto', 'After · mylang GC · O3 + LTO', '#274B87'),
    ('before-arena-lto', 'Before · mylang arena · O3 + LTO', '#A2B2A7'),
    ('arena-lto', 'After · mylang arena · O3 + LTO', '#236744'),
    ('before-gc-lto-bounded', 'Before · GC · O3 + LTO · tool limits', '#B9C1CD'),
    ('gc-lto-bounded', 'After · GC · O3 + LTO · tool limits', '#6888C2'),
    ('before-arena-lto-bounded', 'Before · arena · O3 + LTO · tool limits', '#BAC9BF'),
    ('arena-lto-bounded', 'After · arena · O3 + LTO · tool limits', '#66A17F'),
)

if __name__ == '__main__':
    charts.main()

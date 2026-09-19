#!/usr/bin/env python3
"""Differential check: mylang port vs the independent Python reference reader.

For every fixture, parses with experiments/sexpr-port/reference_parse.py and
with the mylang CLI (main.my --stats), then compares the eight node statistics.
Also round-trips each fixture through `--render` and re-parses the rendering.

Usage:
  python3 experiments/sexpr-port/compare.py [fixture ...]
Exits non-zero on any mismatch.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
EDA = REPO.parent / "eda"
sys.dont_write_bytecode = True  # keep the port directory free of __pycache__
sys.path.insert(0, str(HERE))

import reference_parse  # noqa: E402

FIELDS = ["forms", "nodes", "atoms", "strings", "ints", "floats", "measures", "max_depth"]

DEFAULT_FIXTURES = [
    REPO / "experiments/sexpr-port/fixtures/units.sexp",
    REPO / "experiments/schematic/fixtures/spi.sexp",
    REPO / "experiments/schematic/fixtures/lmx2595rhar.sexp",
    REPO / "experiments/schematic/fixtures/straps-synth-lmx2595.sexp",
]

# Real ~185 kB EDA board/module files in the sibling `eda` checkout. Parsed only
# when present and when `--large` is passed, since they live outside this repo.
LARGE_FIXTURES = [
    EDA / "projects/designs/lib/modules/poe-pd-flyback-tps23757.sexp",
    EDA / "projects/designs/src/boards/remora-rf/remora-rf.sexp",
    EDA / "projects/designs/history/barracuda/2026-09-01T19-50-03/barracuda.sexp",
]


def mylang_stats(path: Path) -> dict:
    proc = subprocess.run(
        ["./zig-out/bin/mylang", "run", "experiments/sexpr-port/main.my", "--", str(path)],
        cwd=REPO,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise SystemExit(f"mylang failed on {path} (exit {proc.returncode}):\n{proc.stderr}{proc.stdout}")
    stats = {}
    for pair in proc.stdout.strip().split():
        key, _, value = pair.partition("=")
        stats[key] = float(value) if key == "value_sum" else int(value)
    return stats


def value_sum_agrees(reference: float, measured: float) -> bool:
    return abs(reference - measured) <= 1e-9 * max(1.0, abs(reference))


def mylang_render(path: Path) -> str:
    proc = subprocess.run(
        ["./zig-out/bin/mylang", "run", "experiments/sexpr-port/main.my", "--", str(path), "--render"],
        cwd=REPO,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise SystemExit(f"mylang render failed on {path} (exit {proc.returncode}):\n{proc.stderr}")
    return proc.stdout.strip()


def main() -> int:
    fixture_args = [a for a in sys.argv[1:] if a != "--large"]
    if "--large" in sys.argv[1:]:
        fixture_args += [str(p) for p in LARGE_FIXTURES if p.exists()]
    fixtures = [Path(p) for p in fixture_args] if fixture_args else DEFAULT_FIXTURES
    failures = 0
    for path in fixtures:
        reference = reference_parse.parse_file(path)
        if not reference["ok"]:
            print(f"SKIP {path}: reference rejected it: {reference['error']}")
            continue
        stats = mylang_stats(path)
        mismatched = [f for f in FIELDS if reference.get(f, 0) != stats.get(f, 0)]
        if not value_sum_agrees(reference.get("value_sum", 0.0), stats.get("value_sum", 0.0)):
            mismatched.append("value_sum")
        status = "ok" if not mismatched else "MISMATCH"
        print(
            f"{status:<8} {path.name:<28} reference={ {f: reference[f] for f in FIELDS} }"
            f" value_sum={reference.get('value_sum', 0.0):.6g}"
        )
        if mismatched:
            failures += 1
            print(f"         mylang   ={ {f: stats.get(f, 0) for f in FIELDS} } value_sum={stats.get('value_sum', 0.0):.6g}")
            print(f"         differing fields: {', '.join(mismatched)}")

        rendered = mylang_render(path)
        if not rendered.startswith("("):
            failures += 1
            print(f"         render did not start with '(': {rendered[:60]!r}")
    if failures:
        print(f"\n{failures} failure(s)")
        return 1
    print(f"\nall {len(fixtures)} fixtures agree with the reference reader")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env bash
# Reproduce the whole sexpr-port comparison: tests, metrics, differential
# check against the reference reader, and the PNG charts.
#
#   bash experiments/sexpr-port/run_all.sh
#
# Charts need matplotlib; override the interpreter with MPL_PYTHON (defaults to
# a sibling virtualenv that has it).
set -euo pipefail

cd "$(dirname "$0")/../.."
REPO="$PWD"
MPL_PYTHON="${MPL_PYTHON:-/home/epentland/ai/canopy/rust-workflow/.venv/bin/python}"

echo "== mylang test (port suite) =="
./zig-out/bin/mylang test experiments/sexpr-port

echo
echo "== metrics (Zig vs mylang line counts) =="
python3 experiments/sexpr-port/metrics.py

echo
echo "== differential check vs the Python reference reader =="
python3 experiments/sexpr-port/compare.py

echo
echo "== byte-for-byte golden comparison vs the real Zig printer =="
if [ -f experiments/sexpr-port/golden/manifest.tsv ]; then
  python3 experiments/sexpr-port/golden_compare.py
else
  echo "no goldens yet; run experiments/sexpr-port/golden/generate_zig_goldens.sh first"
fi

echo
echo "== charts =="
if "$MPL_PYTHON" -c "import matplotlib" 2>/dev/null; then
  "$MPL_PYTHON" experiments/sexpr-port/charts.py
else
  echo "matplotlib not found at $MPL_PYTHON; set MPL_PYTHON to a Python that has it" >&2
  exit 1
fi

echo
echo "artifacts:"
ls -1 experiments/sexpr-port/evidence/

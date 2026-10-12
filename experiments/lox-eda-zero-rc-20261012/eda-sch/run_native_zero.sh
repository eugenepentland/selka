#!/bin/bash
set -euo pipefail
# Run under scripts/build-slot.sh build after sourcing dev-env.sh.
compiler_path=/home/epentland/ai/canopy/mylang-memory-20261012/zig-out/bin/mylang
entry_path=experiments/lox-eda-zero-rc-20261012/eda/source/src/export_kicad_sch_test.my
MYL_CORE_LEAKCHECK=1 "$compiler_path" test "$entry_path" --unoptimized --experimental-zero-rc --json --force --max-steps=1000000000 --max-frames=40000 --max-memory=2G --cache-dir .tmp/eda-sch-zero-private-cache

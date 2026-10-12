#!/usr/bin/env bash
set -euo pipefail
cd /home/epentland/ai/canopy/mylang-memory-20261012-support7
source /home/epentland/.config/mylang/dev-env.sh
export TMPDIR="$PWD/.tmp/memory-closeout/coordinator-applications"
mkdir -p "$TMPDIR"
python3 -B experiments/memory-closeout-20261012/A06/qualify.py \
  --compiler /home/epentland/ai/canopy/mylang-memory-20261012/.tmp/memory-closeout/coordinator/support7-install/bin/mylang \
  --zig "$ZIG" \
  --output /home/epentland/ai/canopy/mylang-memory-20261012/.tmp/memory-closeout/coordinator/support7-applications

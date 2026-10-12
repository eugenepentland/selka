#!/usr/bin/env bash
set -euo pipefail
source /home/epentland/.config/mylang/dev-env.sh
MM_COORDINATOR=/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/memory-closeout/coordinator
MM_COMPILER="$MM_COORDINATOR/support6-install/bin/mylang"
MM_OUTPUT="$MM_COORDINATOR/support6-a06"
python3 -B experiments/memory-closeout-20261012/A06/guest-migrations/probe.py --compiler "$MM_COMPILER" --output "$MM_OUTPUT/guest-source" --limit 64
python3 -B experiments/memory-closeout-20261012/A06/additional-migrations/migrate.py --compiler "$MM_COMPILER" --output "$MM_OUTPUT/additional-source" --limit 23
python3 -B experiments/memory-closeout-20261012/A06/migration-native.py --compiler "$MM_COMPILER" --zig "$ZIG" --output "$MM_OUTPUT/native" --cases ce2_effects --modes debug,verify

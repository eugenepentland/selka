#!/usr/bin/env bash
# Check one task against one arm without launching a session:
#   dev/verify_task.sh TASK ARM
# ARM is a design name (B, P1, P2) or a path to an arm directory. The hidden
# tests, goldens and manifest come from ../mylang-eval/cascade/<task>/.
set -euo pipefail
ROOT=/home/epentland/ai/canopy/mylang
cd "$ROOT"
exec python3 experiments/cascade/run.py --arm "$2" --task "$1" --n 0 --verify-only --no-save

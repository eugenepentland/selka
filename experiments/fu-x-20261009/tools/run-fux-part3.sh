#!/usr/bin/env bash
# FU-X Part 3 only (coordinator, 2026-10-09): attempt 3's Part 1 was green except two checks that
# read cached guest-test results as failures (0 passed, 65/310 cached, 0 failed: the compiler is
# byte-identical to attempt 2's, which ran them fresh). Run the CPU-10 timing it would have run.
set -u
WT=/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure
X=$WT/experiments/fu-x-20261009
T=$X/tools
source $T/env.sh
cd $WT
echo "STEP part3 start $(git rev-parse --short HEAD) $(date -u +%T)"
LOX_SKIP= bash $T/part3.sh lox; echo "STEP lox done $(date -u +%T)"
bash $T/part3.sh eda; echo "STEP eda done $(date -u +%T)"
bash $T/part3.sh parity; echo "STEP parity done $(date -u +%T)"
for n in 1 2 3; do bash $T/part3.sh rows $n; echo "STEP rows $n done $(date -u +%T)"; done
echo "STEP part3 done $(date -u +%T)"

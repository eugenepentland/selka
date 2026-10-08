#!/usr/bin/env bash
# Parity suite, new core (main 5a6b501d, ReleaseFast compiler), 9 rounds pinned to CPU 10,
# whole run (build + qualify + time) under the shared CPU-10 lock. Run from the worktree root.
set -euo pipefail
ROOT=/home/epentland/ai/canopy/mylang-worktrees/claude-bench-newcore
P=$ROOT/.mylang-cache/bench/parity
OUT=$ROOT/experiments/bench-newcore-20261008/parity
mkdir -p "$P/tmp" "$P/work" "$P/zig-global" "$OUT"
export TMPDIR=$P/tmp ZIG_GLOBAL_CACHE_DIR=$P/zig-global PATH=$HOME/.cargo/bin:$PATH
cd "$ROOT"
flock /run/user/1000/mylang-slots/cpu10.lock \
  python3 bench/parity/bench_parity.py run \
    --mylang "$HOME/.cache/mylang/bench-newcore-5a6b501d/bin/mylang" \
    --zig zig --rustc "$HOME/.cargo/bin/rustc" \
    --cpu 10 --rounds 9 --warmups 2 --jobs 4 \
    --work "$P/work" --json "$OUT/result.json" \
  > "$OUT/run.stdout.txt" 2> "$OUT/run.stderr.txt"

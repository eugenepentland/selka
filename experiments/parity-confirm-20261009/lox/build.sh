#!/usr/bin/env bash
# Builds the Lox VM confirmation arms (coordinator, 2026-10-09): cf.py variants of the Lox
# port with main 35df839be's compiler (kept binaries), and the PM-3 Lox VM ladder rungs.
# Run under build-slot.
set -eu
W=/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure
PM=$W/experiments/parity-measure-20261008
C=$W/.tmp/confirm-lox
S=$W/.tmp/pm/lox
export ZIG_LOCAL_CACHE_DIR=$W/.zig-cache ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache TMPDIR=$C/tmp
mkdir -p $C/tmp $C/ladders
M=/home/epentland/.cache/mylang/main-35df839b/bin/mylang
P=$W/.mylang-cache/lox/ports/mylang
python3 $PM/tools/cf.py --program $P/main.my --cwd $P --mylang $M --work $C/cf --name lox --rounds 1 --keep \
  --variants base,bounds,checks,norc,checks+norc \
  --case "step=[\"--engine=vm\", \"$S/step.10000000.lox\"]" \
  --case "vm/fib=[\"--engine=vm\", \"$S/fib.34.lox\"]" \
  --case "vm/string_equality=[\"--engine=vm\", \"$S/string_equality.100000.lox\"]" \
  --case "vm/invocation=[\"--engine=vm\", \"$S/invocation.1500000.lox\"]" > $C/cf-lox.log 2>&1
echo "cf lox=$?"
FLAGS="-O3 -march=native -mllvm -x86-experimental-pref-innermost-loop-alignment=6"
for r in 0 2 5 6; do zig cc $FLAGS -DRUNG=$r -o $C/ladders/loxvm.r$r $PM/ladders/loxvm.c -lm; echo "ladder loxvm rung $r=$?"; done
echo "build done"

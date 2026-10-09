#!/usr/bin/env bash
# Builds the confirmation arms (coordinator, 2026-10-09): cf.py variants with the
# PM-1 compiler (kept binaries) and the ideal-C ladder rungs. Run under build-slot.
set -eu
W=/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure
PM=$W/experiments/parity-measure-20261008
C=$W/.tmp/confirm
export ZIG_LOCAL_CACHE_DIR=$W/.zig-cache ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache TMPDIR=$C/tmp
mkdir -p $C/tmp $C/ladders
M=/home/epentland/.cache/mylang/pm-a677da7a/bin/mylang
P=$W/bench/parity
cf() { python3 $PM/tools/cf.py --program $1 --mylang $M --work $C/cf --name $2 --rounds 1 --keep --variants $3 > $C/cf-$2.log 2>&1; echo "cf $2=$?"; }
cf $P/suite/matmul.my matmul base,tbaa,checks+tbaa
cf $P/micro/bytes_scan.my bytes_scan base,overflow
cf $P/suite/sieve.my sieve base,overflow,checks
cf $P/suite/nbody.my nbody base,unique
FLAGS="-O3 -march=native -mllvm -x86-experimental-pref-innermost-loop-alignment=6"
rung() { zig cc $FLAGS -DRUNG=$2 ${3:-} -o $C/ladders/$1.r$2 $PM/ladders/$1.c -lm; echo "ladder $1 rung $2=$?"; }
rung matmul 0 -fno-strict-aliasing; rung matmul 2 -fno-strict-aliasing; rung matmul 6
for r in 0 1 2; do rung knucleotide $r; rung scan_split $r; rung str_build $r; done
echo "build done"

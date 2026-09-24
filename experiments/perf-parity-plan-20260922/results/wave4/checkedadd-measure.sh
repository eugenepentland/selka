#!/usr/bin/env bash
# usage: measure.sh TAG ROUNDS
# Builds the `before` arm (base compiler, stock adapter) of every program into the
# bench work directory, then times zig-fast, zig-safe, my (lane), my-unchecked and
# before on CPU 0 with bench.py; records CPU 1 (the SMT sibling) busy fraction.
set -e
W=$(cd "$(dirname "$0")/.." && pwd)
TAG=$1; ROUNDS=${2:-11}
export TMPDIR=/home/epentland/.cache/mylang-tmp
# ReleaseFast, LLVM O3 + LTO: the default build when this ran; `--release` since 2026-09-23.
RELEASE="--backend llvm --llvm-opt 3 --lto"
B=$W/experiments/perf-parity-plan-20260922/bench.py
OUT=$W/experiments/perf-parity-plan-20260922/results/wave4
WORK=$W/.tmp/bench
mkdir -p "$WORK"
SUITE=$W/experiments/perf-parity-plan-20260922/suite
MICRO=$W/experiments/perf-parity-audit-20260921/micro
NAMES="binary_trees spectral_norm mandelbrot raytrace knucleotide text_ops sort_builtin sort_quick sort_records sieve nbody fannkuch_redux matmul"
MNAMES="fib calls intloop float_loop list_records records dict_count bytes_scan list_append_sum"
for n in $NAMES; do
  [ -x "$WORK/$n.before" ] || "$W/.tmp/install-base/bin/mylang" build "$SUITE/$n.my" -o "$WORK/$n.before" --cache-dir "$W/.tmp/cache-base" $RELEASE
done
for n in $MNAMES; do
  [ -x "$WORK/$n.before" ] || "$W/.tmp/install-base/bin/mylang" build "$MICRO/$n.my" -o "$WORK/$n.before" --cache-dir "$W/.tmp/cache-base" $RELEASE
done
sib() { awk '/^cpu1 /{print $2+$3+$4+$7+$8, $2+$3+$4+$5+$6+$7+$8}' /proc/stat; }
s0=$(sib)
python3 $B $MNAMES --src $MICRO --mylang $W/.tmp/install-lane/bin/mylang --work $WORK \
  --cpu 0 --rounds $ROUNDS --arms zig-fast zig-safe my my-unchecked --cf before --json $OUT/checkedadd-$TAG-micro.json
s1=$(sib)
python3 $B $NAMES --src $SUITE --mylang $W/.tmp/install-lane/bin/mylang --work $WORK \
  --cpu 0 --rounds $ROUNDS --arms zig-fast zig-safe my my-unchecked --cf before --json $OUT/checkedadd-$TAG-suite.json
s2=$(sib)
python3 - "$s0" "$s1" "$s2" <<'EOF'
import sys
p = [tuple(map(int, a.split())) for a in sys.argv[1:]]
for label, (a, b) in (("micro", (p[0], p[1])), ("suite", (p[1], p[2]))):
    print(f"sibling_busy CPU1 during {label}: {(b[0]-a[0])/max(1,b[1]-a[1]):.2f}")
EOF
echo MEASURE-DONE

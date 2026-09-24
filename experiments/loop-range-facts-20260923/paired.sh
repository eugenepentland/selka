#!/usr/bin/env bash
# Paired before/after batch: the lane's compiler as the `my` arm, the
# vectorizer-blockers compiler (main ba857f44, the lane's base) prebuilt as
# the `vecblock` arm, Zig ReleaseFast as the reference, one CPU, arms shuffled
# every round.
# usage: paired.sh LANE_MYLANG BEFORE_MYLANG WORK JSON CPU ROUNDS
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
lane=$1; before=$2; work=$3; json=$4; cpu=$5; rounds=$6
export TMPDIR=${TMPDIR:-/home/epentland/.cache/mylang-tmp}
mkdir -p "$work"
suite="matmul nbody spectral_norm sieve fannkuch_redux raytrace mandelbrot knucleotide"
micro="bytes_scan list_append_sum intloop float_loop list_records records str_build"
for name in $suite; do
  "$before" build "$root/bench/parity/suite/$name.my" -o "$work/$name.vecblock" --cache-dir="$work/before-cache" >/dev/null
done
for name in $micro; do
  "$before" build "$root/bench/parity/micro/$name.my" -o "$work/$name.vecblock" --cache-dir="$work/before-cache" >/dev/null
done
"$before" build "$root/bench/parity/suite/fannkuch_redux_array.my" -o "$work/fannkuch_redux_array.vecblock" --cache-dir="$work/before-cache" >/dev/null
python3 "$root/experiments/perf-parity-plan-20260922/bench.py" $suite $micro \
  --src "$root/bench/parity/suite" --src "$root/bench/parity/micro" \
  --work "$work" --mylang "$lane" --cpu "$cpu" --rounds "$rounds" --arms my my-array zig-fast \
  --cf vecblock --json "$json"

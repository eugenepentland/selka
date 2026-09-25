#!/usr/bin/env bash
# Build dict_bench.c against each named runtime source directory and print the
# instruction count (perf stat, median of 3) of each mode on each runtime.
# usage: run_dict_bench.sh OUTDIR RT_DIR...
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=$1; shift
mkdir -p "$out"
for rt in "$@"; do
  name=$(basename "$rt")
  [ "$name" = src ] && name=new
  zig cc -std=c11 -O2 -fPIC -ffunction-sections -fdata-sections -g0 -I "$rt" "$here/dict_bench.c" \
    "$rt"/native_{heap,arena,dictionary,equal,text,collections,bytes}.c -o "$out/dict_bench-$name"
done
for mode in str int pop; do
  line="$mode"
  for rt in "$@"; do
    name=$(basename "$rt"); [ "$name" = src ] && name=new
    counts=()
    for rep in 1 2 3; do
      counts+=($(taskset -c ${BENCH_CPU:-10} perf stat -x, -e instructions:u -- "$out/dict_bench-$name" "$mode" 2>&1 >/dev/null | grep -v atom | grep instructions | cut -d, -f1))
    done
    median=$(printf '%s\n' "${counts[@]}" | sort -n | sed -n 2p)
    line="$line $name=$median"
  done
  echo "$line"
done

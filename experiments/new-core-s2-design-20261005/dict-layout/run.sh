#!/bin/sh
# Build and run the S2 dictionary-layout microbenchmark on CPU 10 (user cycles per op).
# Usage: ./run.sh [rounds]   -> results/layouts-<date>.txt
set -eu
cd "$(dirname "$0")"
rounds=${1:-7}
zig cc -O3 -march=native -o bench bench.c
mkdir -p results
out=results/layouts-$(date +%Y%m%d).txt
{
  echo "# zig cc -O3 -march=native; taskset -c 10; $(grep -m1 'model name' /proc/cpuinfo)"
  for n in 64 4096 65536; do taskset -c 10 ./bench $n "$rounds" 2>&1; done
  echo "# PRESIZE=1 (2n entries reserved up front)"
  for n in 64 4096; do PRESIZE=1 taskset -c 10 ./bench $n "$rounds" 2>&1; done
} | tee "$out"
rm -f bench

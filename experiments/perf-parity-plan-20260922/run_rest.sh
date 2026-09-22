#!/usr/bin/env bash
# The remaining batches, in sequence on CPU 6 (the slow batch runs separately on CPU 8):
# the plan ladder for the fast programs, the micro-kernels with Rust, the parser
# (compilers and ladder binaries), and the schematic renderer.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
TMP="$(cd "$HERE/../../.." && pwd)"
A3="$TMP/../perf-audit-20260922/install-a3/bin/mylang"
L5="$TMP/install-lane5/bin/mylang"
LAD="--cf lad-nr --cf lad-l5 --cf lad-l5-nr --cf lad-l5-nr-lang --cf lad-l5-nr-lang-fr --cf lad-l5-all"
python3 bench.py binary_trees spectral_norm mandelbrot raytrace knucleotide text_ops sort_builtin sort_quick sort_records sieve \
  --rounds 7 --warmups 2 --cpu 6 --arms zig-fast zig-safe rust my my-unchecked $LAD --json results/ladder-fast.json > results/ladder-fast.log 2>&1
python3 bench.py intloop calls fib records list_append_sum list_records dict_count str_build alloc_churn float_loop bytes_scan \
  --src ../perf-parity-audit-20260921/micro --src micro-rust --work "$TMP/work/micro" \
  --rounds 7 --warmups 2 --cpu 6 $LAD --json results/micro.json > results/micro.log 2>&1
python3 parser_bench.py --arm a3="$A3" --arm a3-unchecked="$A3:--unchecked" --arm l5="$L5" --arm l5-unchecked="$L5:--unchecked" \
  --rounds 11 --cpu 6 --json results/parser.json > results/parser.log 2>&1
W="$TMP/work/parser-cf"
BINS=""
for arm in cf-plain cf-frames cf-checks cf-nogc cf-noroots lad-nr lad-l5 lad-l5-nr lad-l5-nr-lang lad-l5-nr-lang-fr lad-l5-all; do
  BINS="$BINS --bin $arm=$W/main.$arm"
done
python3 parser_bench.py $BINS --rounds 11 --cpu 6 --json results/parser-ladder.json > results/parser-ladder.log 2>&1
(cd ../schematic-parity-gap-20260922/scripts && mkdir -p "$TMP/work/schematic/bench" && \
  BENCH_WORK="$TMP/work/schematic/bench" python3 bench_svg.py --arms "$HERE/schematic/arms.json" \
  --out "$HERE/results/schematic.json" --rounds 31 --warmups 3 --cpu 6 --reference zig-o3) > results/schematic.log 2>&1
echo "rest done" >> results/schematic.log

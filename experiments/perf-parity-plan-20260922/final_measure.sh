#!/usr/bin/env bash
# Final parity re-measure: before (audit compiler install-a3) vs after (final integration
# compiler), each on LLVM (default) and QBE, against Zig ReleaseFast/Safe and Rust.
# usage: final_measure.sh <final-install-dir> <cpu> [rounds]
# env: BEFORE=<old mylang binary> (default: the plan's install-a3), OUT=<work dir>
set -uo pipefail
FINAL=$1/bin/mylang; CPU=$2; ROUNDS=${3:-11}
H=$(cd "$(dirname "$0")" && pwd)
MICRO=$H/../perf-parity-audit-20260921/micro
BEFORE=${BEFORE:-$H/../../.tmp/perf-audit-20260922/install-a3/bin/mylang}   # the plan's measured compiler
OUT=${OUT:-$H/../../.tmp/parity-final}; mkdir -p "$OUT"
echo "final compiler: $FINAL ($(sha256sum < "$FINAL" | cut -c1-12)); cpu $CPU; rounds $ROUNDS"

prebuild() {  # <work> <srcdir> <stem...>: before arms, LLVM and QBE
  local work=$1 src=$2; shift 2; mkdir -p "$work"
  for stem in "$@"; do
    ( cd "$src" && "$BEFORE" build "$stem.my" -o "$work/$stem.before" --cache-dir "$work/mycache-before" >/dev/null 2>&1 ) \
      || echo "  before: $stem does not build with the audit compiler (new in this run)"
    ( cd "$src" && "$BEFORE" build "$stem.my" -o "$work/$stem.before-qbe" --backend qbe --cache-dir "$work/mycache-before-qbe" >/dev/null 2>&1 ) || true
  done
}

SUITE="binary_trees fannkuch_redux knucleotide mandelbrot matmul nbody raytrace sieve sort_builtin sort_quick sort_records spectral_norm text_ops"
MICROS="alloc_churn bytes_scan calls dict_count fib float_loop intloop list_append_sum list_records records str_build"
LIB="scan_count scan_replace scan_split slice_walk"

echo "== prebuild before arms"
prebuild "$OUT/suite" "$H/suite" $(cd "$H/suite" && ls *.my | sed 's/\.my$//')
prebuild "$OUT/micro" "$MICRO" $(cd "$MICRO" && ls *.my | sed 's/\.my$//')
prebuild "$OUT/lib" "$H/lib" $LIB

echo "== suite"
python3 "$H/bench.py" $SUITE --src "$H/suite" --mylang "$FINAL" --work "$OUT/suite" --cpu "$CPU" --rounds "$ROUNDS" \
  --qbe --cf before --cf before-qbe --json "$OUT/suite.json" > "$OUT/suite.log" 2>&1; echo "suite exit $?"
echo "== micro"
python3 "$H/bench.py" $MICROS --src "$MICRO" --src "$H/micro-rust" --mylang "$FINAL" --work "$OUT/micro" --cpu "$CPU" --rounds "$ROUNDS" \
  --qbe --cf before --cf before-qbe --json "$OUT/micro.json" > "$OUT/micro.log" 2>&1; echo "micro exit $?"
echo "== lib"
python3 "$H/bench.py" $LIB --src "$H/lib" --mylang "$FINAL" --work "$OUT/lib" --cpu "$CPU" --rounds "$ROUNDS" \
  --qbe --cf before --cf before-qbe --json "$OUT/lib.json" > "$OUT/lib.log" 2>&1; echo "lib exit $?"
for f in suite micro lib; do echo "== $f"; python3 "$H/table.py" "$OUT/$f.json" --ci 2>&1 | head -80; done

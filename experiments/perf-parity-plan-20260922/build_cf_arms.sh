#!/usr/bin/env bash
# Build every counterfactual arm the audit times, for the benchmarks named on the
# command line, into the bench work directory, with the compiler under test (a3)
# and with the lane-5 compiler (l5-*). Timing is bench.py's job (--cf ARM).
#
#   build_cf_arms.sh NAME [NAME...]
#
# Arms (see rewrite_il.py):
#   cf-plain      unmodified manifest rebuild (must equal the plain build)
#   cf-nan        NaN canonicalization removed
#   cf-overflow   integer overflow checks removed
#   cf-bounds     index bounds + for-loop length checks removed
#   cf-checks     every check class removed (overflow, cast, bounds, iter, alloc)
#   cf-frames     frame record, stack-floor test and position stores removed
#   cf-negidx     Python negative-index normalization skipped
#   cf-iter       for-loop list-length (iteration invalidation) checks removed
#   cf-lang       the three rules Zig/Rust do not have: nan + negidx + iter
#   cf-all        all of the above
#   cf-nogc       the collector never runs
#   cf-noroots    the collector never runs and no root record is published
#   l5            the lane-5 compiler's plain build
#   l5-nan        lane 5 + cf-nan
#   l5-lang       lane 5 + cf-lang
#   l5-all        lane 5 + cf-all
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(cd "$HERE/../../.." && pwd)"          # .tmp/perf-plan-20260922
WORK="${WORK:-$TMP/work/bench}"
L5="${L5:-$TMP/install-lane5/bin/mylang}"
ALL=nan,negidx,overflow,cast,bounds,iter,alloc,frames,positions
LANG=nan,negidx,iter
mkdir -p "$WORK" "$WORK/l5"
for name in "$@"; do
  python3 "$HERE/counterfactual.py" "$name" --work "$WORK" \
    --arm cf-nan=nan --arm cf-overflow=overflow --arm cf-bounds=bounds,iter \
    --arm cf-checks=overflow,cast,bounds,iter,alloc --arm cf-frames=frames,positions \
    --arm cf-negidx=negidx --arm cf-iter=iter --arm cf-lang=$LANG \
    --arm cf-all=$ALL --arm cf-nogc=nogc --arm cf-noroots=nogc,roots
  python3 "$HERE/counterfactual.py" "$name" --work "$WORK/l5" --mylang "$L5" \
    --arm cf-nan=nan --arm cf-lang=$LANG --arm cf-all=$ALL
  cp -f "$WORK/l5/$name.cf-plain" "$WORK/$name.l5"
  cp -f "$WORK/l5/$name.cf-nan" "$WORK/$name.l5-nan"
  cp -f "$WORK/l5/$name.cf-lang" "$WORK/$name.l5-lang"
  cp -f "$WORK/l5/$name.cf-all" "$WORK/$name.l5-all"
  cp -f "$WORK/l5/$name.cf.json" "$WORK/$name.l5.cf.json"
done

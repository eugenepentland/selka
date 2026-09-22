#!/usr/bin/env bash
# Build the plan's composition ladder for the benchmarks named on the command
# line: each rung adds one wave of the plan on top of the previous one, so the
# ladder shows how far each wave gets. Binaries land in the bench work directory
# as <name>.lad-<rung>; bench.py times them with --cf lad-<rung>.
#
#   build_ladder.sh [--src DIR] NAME [NAME...]
#
# Rungs (all LLVM O3 + LTO, through an adapter copy that accepts `hlt`):
#   lad-nr               today's compiler + failure paths end in `unreachable`
#                        (sound in an executable: the fail helper longjmps)
#   lad-l5               the lane-5 compiler (aggregates read/written in place)
#   lad-l5-nr            + noreturn failure paths
#   lad-l5-nr-lang       + the language rules changed: NaN canonicalized only
#                        when observed, no dynamic negative index, no for-loop
#                        length re-check
#   lad-l5-nr-lang-fr    + no frame record / position stores (roadmap item 2's
#                        return-address map, priced as its absence)
#   lad-l5-all           every check and protocol stripped (the unchecked bound)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(cd "$HERE/../../.." && pwd)"
WORK="${WORK:-$TMP/work/bench}"
A3="${A3:-$TMP/../perf-audit-20260922/install-a3/bin/mylang}"
L5="${L5:-$TMP/install-lane5/bin/mylang}"
ADAPTER="${ADAPTER:-$TMP/work/adapter-hlt/qbe_llvm.py}"
SRC=()
if [ "${1:-}" = "--src" ]; then SRC=(--src "$2"); shift 2; fi
LANG=nan,negidx,iter
ALL=nan,negidx,overflow,cast,bounds,iter,alloc,frames,positions
mkdir -p "$WORK/lad-a3" "$WORK/lad-l5"
for name in "$@"; do
  python3 "$HERE/counterfactual.py" "$name" "${SRC[@]}" --work "$WORK/lad-a3" --mylang "$A3" --adapter "$ADAPTER" \
    --arm nr=noreturn
  python3 "$HERE/counterfactual.py" "$name" "${SRC[@]}" --work "$WORK/lad-l5" --mylang "$L5" --adapter "$ADAPTER" \
    --arm nr=noreturn --arm nr-lang=noreturn,$LANG --arm nr-lang-fr=noreturn,$LANG,frames,positions --arm all=$ALL
  cp -f "$WORK/lad-a3/$name.nr" "$WORK/$name.lad-nr"
  cp -f "$WORK/lad-l5/$name.cf-plain" "$WORK/$name.lad-l5"
  cp -f "$WORK/lad-l5/$name.nr" "$WORK/$name.lad-l5-nr"
  cp -f "$WORK/lad-l5/$name.nr-lang" "$WORK/$name.lad-l5-nr-lang"
  cp -f "$WORK/lad-l5/$name.nr-lang-fr" "$WORK/$name.lad-l5-nr-lang-fr"
  cp -f "$WORK/lad-l5/$name.all" "$WORK/$name.lad-l5-all"
done

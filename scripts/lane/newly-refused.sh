#!/usr/bin/env bash
# newly-refused.sh COMPILER [KIT] : what COMPILER refuses that the kit's base compiler accepted.
# Checks every prepared project (the trees the BASE compiler's `selka fix` prepared; never COMPILER's own fix, which would hide
# a refusal that carries a repair) with COMPILER, compares error by error with proj-base/ (file, line, code), then runs
# COMPILER's `selka fix --check` on those old-prepared trees and counts the edits by code (an edit under an E_ code is a
# newly refused place; a W_ edit is a new warning with a repair). Three compiler processes at a time, stores of its own.
# Output: a line per project, up to ten newly refused places, the path of the full comparison. Exit 0 when nothing is newly
# refused, 1 otherwise. KIT defaults to the newest READY kit (scripts/lane/kit.sh prepare makes one).
set -u
. "$(dirname "$0")/lib.sh"
case "${1:-}" in -h|--help|"") sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; [ -n "${1:-}" ] && exit 0; exit 2;; esac
compiler=$(realpath "$1"); compiler_check "$compiler"
KIT=$(resolve_kit "${2:-}")
id=$("$compiler" --version 2>/dev/null | sed -n 's/.*identity \([0-9a-f]*\).*/\1/p'); [ -n "$id" ] || id=$(date +%H%M%S)
OUT=$KIT/refused/$id
rm -rf "$OUT"; mkdir -p "$OUT"
t0=$SECONDS
python3 -B "$LANE_DIR/kitproj.py" sweep "$KIT" "$compiler" "$OUT" "$KIT/stores/refused" || echo "newly-refused: a check or fix --check ended with an odd status (see above)" >&2
units=$(wc -l < "$OUT/SUMMARY.txt")
echo "newly-refused: $("$compiler" --version | cut -d, -f1,2) against kit $(basename "$KIT") (base $(sed -n 2p "$KIT/READY" | cut -d' ' -f4-)), $units units in $(elapsed "$t0")"
python3 -B "$LANE_DIR/kitproj.py" compare "$KIT/proj-base" "$OUT" "$OUT/COMPARISON.txt"; rc=$?
echo "full comparison: $OUT/COMPARISON.txt (raw output per unit beside it)"
exit $rc

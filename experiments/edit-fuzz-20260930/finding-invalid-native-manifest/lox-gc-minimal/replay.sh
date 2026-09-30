#!/bin/sh
# Replays the recorded edit sequence and, after the original state and after every
# edit, builds incrementally (persistent cache) and whole-program (fresh cache) and
# compares. usage: replay.sh COMPILER WORKDIR [--gc-runtime]
set -u
COMPILER=$1; WORK=$2; EXTRA=${3:-}
HERE=$(cd "$(dirname "$0")" && pwd)
rm -rf "$WORK"; mkdir -p "$WORK/out"; cp -rL "$HERE/original" "$WORK/project"; cd "$WORK/project"
check() {
  rm -f "$WORK/out/inc" "$WORK/out/whole"
  "$COMPILER" build main.my --project -o "$WORK/out/inc" --cache-dir="$WORK/cache-inc" --report $EXTRA >"$WORK/inc.log" 2>&1; ri=$?
  rm -rf "$WORK/cache-whole"
  "$COMPILER" build main.my --project --whole-program -o "$WORK/out/whole" --cache-dir="$WORK/cache-whole" $EXTRA >"$WORK/whole.log" 2>&1; rw=$?
  compiled=$(grep -o '"module_build":{[^}]*}' "$WORK/inc.log" || true)
  if [ $ri -eq 0 ] && [ $rw -eq 0 ]; then
    if cmp -s "$WORK/out/inc" "$WORK/out/whole"; then echo "$1: MATCH $compiled"; else echo "$1: MISMATCH (binaries differ) $compiled"; fi
  elif [ $ri -ne 0 ] && [ $rw -ne 0 ]; then echo "$1: both failed (matches)"
  else echo "$1: MISMATCH (incremental exit $ri, whole exit $rw)"; fi
}
check original
for p in "$HERE"/edits/*.patch; do
  patch -p1 -s -F0 < "$p" || { echo "$p does not apply"; exit 3; }
  check "$(basename "$p")"
done

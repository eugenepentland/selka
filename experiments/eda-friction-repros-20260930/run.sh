#!/usr/bin/env bash
# Replays every reproducer against one compiler and prints its current outcome.
# Usage: run.sh /path/to/mylang   (scratch and caches go under $TMPDIR or /tmp)
set -u
M=${1:?usage: run.sh /path/to/mylang}
here=$(cd "$(dirname "$0")" && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/eda-repros.XXXXXX")
show() { printf '%s\n' "$1" | head -4 | sed 's/^/    /'; }
for f in "$here"/wp*/*.my "$here"/fixed/*.my; do
  rel=${f#"$here"/}
  if head -1 "$f" | grep -q '^module '; then
    out=$(cd "$(dirname "$f")" && "$M" check-module "$(basename "$f")" 2>&1); rc=$?
    echo "== $rel (check-module) exit=$rc"
  else
    out=$(timeout 120 "$M" run "$f" --cache-dir="$scratch/cache" 2>&1); rc=$?
    echo "== $rel (run) exit=$rc"
  fi
  show "$out"
done
for f in "$here"/wp4/*_80k*.my; do
  "$M" build "$f" -o "$scratch/bin" --cache-dir="$scratch/cache" >/dev/null 2>&1 || { echo "== timing ${f#"$here"/}: build failed"; continue; }
  s=$(date +%s.%N); "$scratch/bin" >/dev/null 2>&1; e=$(date +%s.%N)
  echo "== timing ${f#"$here"/}: $(echo "$e - $s" | bc) s"
done

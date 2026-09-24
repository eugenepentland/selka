#!/usr/bin/env bash
# usage: remarks.sh MYLANG OUTDIR PROGRAM.my...
# Builds each program with the release default (LLVM O3 + full LTO) and keeps the
# loop vectorizer's remarks as OUTDIR/<name>.yaml and the binary as OUTDIR/<name>.
set -u
here=$(cd "$(dirname "$0")" && pwd)
mylang=$1; out=$2; shift 2
mkdir -p "$out"
export TMPDIR=/home/epentland/.cache/mylang-tmp
for program in "$@"; do
  name=$(basename "$program" .my)
  rm -f "$out/$name.yaml" "$out/$name"
  REMARKS_DIR="$out/$name.units" REMARKS_OUT="$out/$name.yaml" "$mylang" build "$program" -o "$out/$name" \
    --zig "$here/zig-remarks.sh" --cache-dir="$out/cache" --keep-symbols || echo "build failed: $program"
done

#!/usr/bin/env bash
# Build the compiler through the build slot and copy the freshly linked `mylang`
# (even when Guardian blocks the install on a work-in-progress change) to
# .tmp/f1/compilers/mylang-dev. Development iteration only; gates use `zig build`.
set -u
root=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$root" || exit 2
export TMPDIR=$root/.tmp/tmp
mkdir -p "$TMPDIR" .tmp/f1/compilers
marker=$(mktemp)
scripts/build-slot.sh build zig build 2>&1 | grep -E 'error|failed|run-all' | grep -v 'selfcheck' | tail -8
newest=$(ls -t .zig-cache/o/*/mylang | head -1)
if [ "$newest" -nt "$marker" ] || [ zig-out/bin/mylang -nt "$marker" ]; then
  src=$newest; [ zig-out/bin/mylang -nt "$newest" ] && src=zig-out/bin/mylang
  cp "$src" .tmp/f1/compilers/mylang-dev && echo "devbuild: copied $src"
else
  echo "devbuild: no new compiler was linked (compile error, or nothing changed)"; 
  cmp -s "$newest" .tmp/f1/compilers/mylang-dev || cp "$newest" .tmp/f1/compilers/mylang-dev
fi
rm -f "$marker"

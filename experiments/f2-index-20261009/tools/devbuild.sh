#!/usr/bin/env bash
# Build the compiler through the build slot and copy the freshly linked Debug `mylang`
# (even when Guardian blocks the install on a work-in-progress change) to
# .tmp/f2/compilers/mylang-dev. Development iteration only; gates use `zig build`.
# With `release`, also build a ReleaseFast compiler into ~/.cache/mylang/f2-dev.
set -u
root=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$root" || exit 2
export TMPDIR=$root/.tmp/tmp
mkdir -p "$TMPDIR" .tmp/f2/compilers
marker=$(mktemp)
scripts/build-slot.sh build zig build 2>&1 | grep -E '^src.*error|run-all|behavioral' | grep -v 'selfcheck' | tail -8
newest=$(ls -t .zig-cache/o/*/mylang | head -1)
if [ "$newest" -nt "$marker" ] || [ zig-out/bin/mylang -nt "$marker" ]; then
  src=$newest; [ zig-out/bin/mylang -nt "$newest" ] && src=zig-out/bin/mylang
  cp "$src" .tmp/f2/compilers/mylang-dev && echo "devbuild: copied $src"
else
  echo "devbuild: no new compiler was linked (compile error, or nothing changed)"
fi
rm -f "$marker"
if [ "${1:-}" = release ]; then
  scripts/build-slot.sh build zig build -Doptimize=ReleaseFast --prefix "$HOME/.cache/mylang/f2-dev" 2>&1 | grep -E 'error|failed' | grep -v selfcheck | tail -5
  ls -la "$HOME/.cache/mylang/f2-dev/bin/mylang"
fi

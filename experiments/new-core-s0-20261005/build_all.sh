#!/usr/bin/env bash
# Build every binary measure.py compares into OUT (default ./bin).
# usage: build_all.sh OUT SPIKE_MYLANG
#   OUT           output directory
#   SPIKE_MYLANG  a compiler built from claude/llvm-direct-spike-20261004 (optional)
# env MYLANG (default zig-out/bin/mylang), MYLANG_CORE (default zig-out/bin/mylang-core)
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
out=${1:-$PWD/bin}
spike=${2:-}
mylang=${MYLANG:-$root/zig-out/bin/mylang}
core=${MYLANG_CORE:-$root/zig-out/bin/mylang-core}
src=$root/test/core/int_math.my
clock=$root/benchmarks/runtime/ports/native_clock.c
mkdir -p "$out"
cache=$(mktemp -d "${TMPDIR:-/tmp}/new-core-measure.XXXXXX")
"$mylang" build "$src" -o "$out/int_math_old" --release --link "$clock" --cache-dir "$cache/old"
"$core" build "$src" -o "$out/int_math_new" --release --link "$clock" --cache-dir "$cache/core"
"$core" build "$src" -o "$out/int_math_new_nofacts" --release --no-facts --link "$clock" --cache-dir "$cache/core"
if [ -n "$spike" ]; then
  MYLANG_LLVM_DIRECT=1 "$spike" build "$src" -o "$out/int_math_spike_l1" --release --link "$clock" --cache-dir "$cache/spike1"
  MYLANG_LLVM_DIRECT=2 "$spike" build "$src" -o "$out/int_math_spike_l2" --release --link "$clock" --cache-dir "$cache/spike2"
fi
zig cc -O3 -o "$out/int_math_c" "$root/experiments/runtime-ideal-ladder-20261004/int_math.c"
rm -rf "$cache"

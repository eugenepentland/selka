#!/usr/bin/env bash
# Build every binary measure_kernels.py compares into OUT.
# usage: build_kernels.sh OUT [SPIKE_MYLANG]
# env MYLANG (default zig-out/bin/mylang), MYLANG_CORE (default zig-out/bin/mylang-core)
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
out=$1
spike=${2:-}
mylang=${MYLANG:-$root/zig-out/bin/mylang}
core=${MYLANG_CORE:-$root/zig-out/bin/mylang-core}
clock=$root/benchmarks/runtime/ports/native_clock.c
mkdir -p "$out"
cache=$(mktemp -d "${TMPDIR:-/tmp}/new-core-kernels.XXXXXX")
for k in int_math float_math call_direct branch_predictable branch_mixed binary_search; do
  "$mylang" build "$root/test/core/$k.my" -o "$out/${k}_old" --release --link "$clock" --cache-dir "$cache/old"
  "$core" build "$root/test/core/$k.my" -o "$out/${k}_new" --release --link "$clock" --cache-dir "$cache/core"
done
"$mylang" build "$root/test/core/compute_s0.my" -o "$out/compute_s0_old" --release --link "$clock" --cache-dir "$cache/old"
"$core" build "$root/test/core/compute_s0.my" -o "$out/compute_s0_new" --release --link "$clock" --cache-dir "$cache/core"
if [ -n "$spike" ]; then
  MYLANG_LLVM_DIRECT=2 "$spike" build "$root/benchmarks/runtime/expanded/compute/main.my" -o "$out/compute_spike_l2" --release --link "$clock" --cache-dir "$cache/spike"
fi
ladder=$root/experiments/runtime-ideal-ladder-20261004
for c in int_math float_math branch_mixed; do
  zig cc -O3 -ffp-contract=off -fno-strict-aliasing -o "$out/${c}_c" "$ladder/$c.c" -lm
done
rm -rf "$cache"

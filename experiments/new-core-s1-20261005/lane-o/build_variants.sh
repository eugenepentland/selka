#!/usr/bin/env bash
# build_variants.sh OUT NAME CORE [FLAGS...]: build the S0 kernels (test/core) with one
# mylang-core and flags into OUT/NAME/<file>, release, linked with the benchmark clock.
set -eu
out=$1; name=$2; core=$3; shift 3
root=$(cd "$(dirname "$0")/../../.." && pwd)
mkdir -p "$out/$name"
for file in int_math float_math call_direct branch_predictable branch_mixed binary_search; do
  "$core" build "$root/test/core/$file.my" -o "$out/$name/$file" --release --cache-dir "$out/cache-$name" \
    --link "$root/benchmarks/runtime/ports/native_clock.c" "$@"
done

#!/bin/bash
# Builds every ladder kernel twice: native (zig cc defaults to the host CPU, like MyLang LLVM)
# and baseline x86-64 (no AVX2, like the Rust arm). Hand-AVX2 versions compile only in the first.
# -fno-strict-aliasing: mylang's IL carries no TBAA; -ffp-contract=off: separate float operations.
set -e
cd "$(dirname "$0")"
export TMPDIR="${TMPDIR:-$PWD/../../.tmp}"
mkdir -p build "$TMPDIR"
CF="-O3 -ffp-contract=off -fno-strict-aliasing -lm"
for src in ${@:-float_math list_filter}; do
    zig cc $CF -o build/$src $src.c
    zig cc $CF -mcpu=x86_64 -o build/${src}_base $src.c
done

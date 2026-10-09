#!/usr/bin/env bash
# Source from a runtime-parity wave 3 worktree before builds or measurements.
RP3_ROOT=$(git rev-parse --show-toplevel)
RP3_EVIDENCE="$RP3_ROOT/experiments/runtime-parity-3-20261009"
RP3_TAG=${RP3_TAG:-base}
export TMPDIR="$RP3_ROOT/.tmp/rp3"
export ZIG_LOCAL_CACHE_DIR="$RP3_ROOT/.zig-cache-rp3"
export MYLANG_CORE_RUNTIME_CACHE="$RP3_ROOT/.mylang-cache/runtime-rp3-$RP3_TAG"
mkdir -p "$TMPDIR" "$ZIG_LOCAL_CACHE_DIR" "$MYLANG_CORE_RUNTIME_CACHE"

#!/usr/bin/env bash
# Run from the S06 checkout. Native compilation uses the shared admission queue.
set -euo pipefail
s06_zig=${S06_ZIG:-$(command -v zig)}
[[ "$($s06_zig version)" == "$(cat .zigversion)" ]]
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache/S06"
export TMPDIR="$PWD/.tmp/S06"
mkdir -p "$ZIG_LOCAL_CACHE_DIR" "$TMPDIR"
git show fbfcaa7a923186a8e773c3760f81c10aa345a432:src/core/test_runner_discover.zig > "$TMPDIR/baseline_discover.zig"
scripts/build-slot.sh build "$s06_zig" test --dep mylang -Mroot=experiments/development-loop-closeout-20261012/S06/rejected_discovery.zig --dep typed -Mmylang=experiments/development-loop-closeout-20261012/S06/typed_shim.zig -Mtyped=src/typed.zig --test-filter S06
scripts/build-slot.sh build "$s06_zig" test --dep baseline --dep candidate --dep typed -Mroot=experiments/development-loop-closeout-20261012/S06/discovery_profile.zig --dep mylang -Mbaseline=.tmp/S06/baseline_discover.zig --dep mylang -Mcandidate=experiments/development-loop-closeout-20261012/S06/rejected_discovery.zig --dep typed -Mmylang=experiments/development-loop-closeout-20261012/S06/typed_shim.zig -Mtyped=src/typed.zig --test-filter S06 --test-no-exec -O ReleaseFast -femit-bin=.tmp/S06/discovery-profile
# S10 owns isolated scheduling/repetitions. A plain build-admitted execution is
# correctness/operational evidence only, not qualified latency.

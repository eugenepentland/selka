#!/usr/bin/env bash
# Reconstruct the Lox port the way exp/e2-p3-value-copies' prepare_lox.sh does:
# bench/lox-20260922 at 6f76140e (last commit with call-site `mut` markers) plus
# that experiment's lox-port.patch (semantics-preserving adaptations to current
# checker rules), and copy the benchmark's scripts/expected/sizes.
# usage: prepare_lox.sh WORK   (WORK defaults to <repo>/.tmp-pc)
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
work=${1:-$repo/.tmp-pc}
mkdir -p "$work/lox"
git -C "$repo" show exp/e2-p3-value-copies:experiments/value-semantics-20260924/p3/lox-port.patch > "$work/lox/lox-port.patch"
git -C "$repo" archive 6f76140e benchmarks/lox/ports/mylang | tar -x -C "$work/lox"
(cd "$work/lox/benchmarks/lox/ports/mylang" && patch -p1 < "$work/lox/lox-port.patch")
# The benchmark data (scripts, expected outputs, sizes) at the same commit.
git -C "$repo" archive 6f76140e benchmarks/lox/bench | tar -x -C "$work/lox"
rm -rf "$work/lox/bench" && mv "$work/lox/benchmarks/lox/bench" "$work/lox/bench"

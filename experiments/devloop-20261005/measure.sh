#!/usr/bin/env bash
# Dev-loop probe, 2026-10-05. Run from a worktree whose compiler is already built
# (warm Zig cache). Every source edit is a unique comment and is reverted.
# Usage: experiments/devloop-20261005/measure.sh   (prints one line per step)
set -u
cd "$(git rev-parse --show-toplevel)"
WT=$PWD
export ZIG_LOCAL_CACHE_DIR=${ZIG_LOCAL_CACHE_DIR:-$WT/.tmp/zig-local-cache}
export TMPDIR=${TMPDIR:-$WT/.tmp/tmp}
mkdir -p "$TMPDIR" "$ZIG_LOCAL_CACHE_DIR"
LOG=$WT/.tmp/devloop.log; : > "$LOG"
t() { local name=$1; shift; local s e rc; s=$(date +%s.%N); "$@" >>"$LOG" 2>&1; rc=$?; e=$(date +%s.%N)
      printf '%-52s %7.1fs rc=%d\n' "$name" "$(echo "$e - $s" | bc)" "$rc"; }
edit() { echo "// devloop probe $(date +%s%N)" >> "$1"; }
slot() { scripts/build-slot.sh build "$@"; }
t "zig build -Dcompiler-only (no-op)"                 slot zig build -Dcompiler-only=true -j2
edit src/qbe_scalar.zig
t "edit back-end leaf -> zig build -Dcompiler-only"   slot zig build -Dcompiler-only=true -j2
edit src/qbe_scalar.zig
t "edit back-end leaf -> zig build (all binaries)"    slot zig build -j2
edit src/qbe_scalar.zig
t "edit -> test-units -Dtest-filter=arena"            slot zig build test-units -Dtest-filter=arena -j2
edit src/qbe_scalar.zig
t "edit -> test-cli -Dtest-filter=fmt"                slot zig build test-cli -Dtest-filter=fmt -j2
git checkout -q src/qbe_scalar.zig
edit src/semantic_cache.zig
t "edit front-end file -> zig build -Dcompiler-only"  slot zig build -Dcompiler-only=true -j2
git checkout -q src/semantic_cache.zig
t "rebuild clean tree"                                slot zig build -Dcompiler-only=true -j2
C=$WT/.tmp/devloop-guest-cache; rm -rf "$C"
t "mylang test tests/lang (empty guest cache)"        slot ./zig-out/bin/mylang test tests/lang --cache-dir="$C"
t "mylang test tests/lang (fully cached)"             ./zig-out/bin/mylang test tests/lang --cache-dir="$C"
edit src/qbe_scalar.zig
t "edit -> rebuild"                                   slot zig build -Dcompiler-only=true -j2
t "mylang test tests/lang after compiler edit"        ./zig-out/bin/mylang test tests/lang --cache-dir="$C"
git checkout -q src/qbe_scalar.zig
t "rebuild clean tree"                                slot zig build -Dcompiler-only=true -j2
t "full gate: zig build test (incl. slot wait)"       scripts/build-slot.sh gate zig build test --summary all -j2
grep -E '^build-slot: (gate|build) slot' "$LOG"

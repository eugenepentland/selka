#!/usr/bin/env bash
# Dev-loop baseline of the new core (plan §7). Run from the worktree root under
# scripts/build-slot.sh with ZIG_LOCAL_CACHE_DIR, ZIG_GLOBAL_CACHE_DIR and TMPDIR set.
# Each edit changes one line of src/core/main.zig (the usage text) and is reverted.
set -u
root=$(pwd)
file=src/core/main.zig
backup=$(mktemp "${TMPDIR:-/tmp}/devloop.XXXXXX")
cp "$file" "$backup"
trap 'cp "$backup" "$file"; rm -f "$backup"' EXIT
now() { date +%s.%N; }
edit() { sed -i "s/\\\\usage[^:]*: mylang-core build/\\\\usage $1: mylang-core build/" "$file"; }
step() { # label command...
  local label=$1; shift
  local start end
  start=$(now)
  "$@" >/dev/null 2>&1
  local status=$?
  end=$(now)
  printf '%-48s %6.2f s (exit %d)\n' "$label" "$(echo "$end - $start" | bc)" "$status"
}
zig build core -j2 >/dev/null 2>&1
stamp=$(date +%s)
for i in 1 2 3 4 5; do
  edit "core$stamp$i"; step "one-line edit -> zig build core" zig build core -j2
done
step "no change -> zig build core" zig build core -j2
for i in 1 2 3; do
  edit "test$stamp$i"; step "one-line edit -> zig build test-core" zig build test-core -j2
done
step "no change -> zig build test-core" zig build test-core -j2
cp "$backup" "$file"
zig build core -j2 >/dev/null 2>&1
src=test/core/int_math.my
clock=$root/benchmarks/runtime/ports/native_clock.c
out=$(mktemp -d "${TMPDIR:-/tmp}/devloop-out.XXXXXX")
for mode in debug release; do
  flag=""; [ "$mode" = release ] && flag="--release"
  cold=$(mktemp -d "${TMPDIR:-/tmp}/devloop-cache.XXXXXX")
  step "mylang-core build slice $mode, empty cache" zig-out/bin/mylang-core build $src -o $out/p $flag --link $clock --cache-dir $cold
  for i in 1 2 3; do
    step "mylang-core build slice $mode, runtime cached" zig-out/bin/mylang-core build $src -o $out/p $flag --link $clock --cache-dir $cold
  done
  rm -rf "$cold"
done
for mode in debug release; do
  flag=""; [ "$mode" = release ] && flag="--release"
  for i in 1 2; do
    cold=$(mktemp -d "${TMPDIR:-/tmp}/devloop-cache.XXXXXX")
    step "old mylang build slice $mode, empty cache" zig-out/bin/mylang build $src -o $out/q $flag --link $clock --cache-dir $cold
    step "old mylang build slice $mode, warm cache" zig-out/bin/mylang build $src -o $out/q $flag --link $clock --cache-dir $cold
    rm -rf "$cold"
  done
done
rm -rf "$out"

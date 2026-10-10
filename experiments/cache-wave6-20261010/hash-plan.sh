#!/usr/bin/env bash
# Run from this repository root, with a frozen Debug compiler as the first argument.
# Uses the ordinary gate admission and restores reserved CPU2 affinity only inside
# the admitted command. GNU time measures command execution, excluding slot wait.
set -eu
compiler=${1:?usage: hash-plan.sh COMPILER OUTPUT_PREFIX}
prefix=${2:?usage: hash-plan.sh COMPILER OUTPUT_PREFIX}
fixture=.mylang-cache/cache-wave6/hash
mkdir -p "$fixture" .mylang-cache/cache-wave6/tmp
cp experiments/cache-wave6-20261010/hash-fixture-juice.toml "$fixture/juice.toml"
cp experiments/cache-wave6-20261010/hash-fixture-program.c "$fixture/program.c"
cp experiments/cache-wave6-20261010/hash-fixture-data.txt "$fixture/data.txt"
export TMPDIR="$PWD/.mylang-cache/cache-wave6/tmp"
export MYLANG_ZIG=/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig
export ZIG="$MYLANG_ZIG"
scripts/build-slot.sh gate bash -c '
    for n in 1 2 3; do
        taskset -c 2 /usr/bin/time -f "wall=%e user=%U system=%S max_rss_kib=%M" \
            -o "$2-$n.time" "$1" juice plan .mylang-cache/cache-wave6/hash/juice.toml \
            --perf /usr/bin/perf --cache-dir .mylang-cache/cache-wave6/hash/native \
            > "$2-$n-plan.json" || exit
    done
' hash-plan "$compiler" "$prefix"

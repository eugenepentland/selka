#!/usr/bin/env bash
# usage: [COMP=compiler] rbuild.sh OUTDIR SRC [extra build flags...]
# Builds SRC with the worktree adapter, logging zig commands and saving LTO remarks + temps under OUTDIR.
set -e
WT=$(cd "$(dirname "$0")/../.." && pwd)
out=$1; src=$2; shift 2
comp=${COMP:?set COMP to the mylang compiler under test}
mkdir -p "$out"; out=$(cd "$out" && pwd)
case "$src" in /*) ;; *) src=$WT/$src ;; esac
export TMPDIR=${TMPDIR:-$HOME/.cache/mylang-tmp}
export ZW_LOG=$out/zig.log ZW_REMARKS=$out/rem.yaml ZW_SAVE=${ZW_SAVE-1} ZW_KEEP=$out/lto
export MYLANG_QBE_LLVM_DUMP=$out/units MYLANG_QBE_LLVM_REMARKS=$out/unit-remarks
export MYLANG_ZIG=$WT/experiments/vectorizer-blockers-20260923/zigwrap.sh
export MYLANG_LLVM_ADAPTER=${ADAPTER:-$WT/experiments/llvm-backend/qbe_llvm.py}
rm -f "$out/zig.log" "$out/rem.yaml"
cd "$out"
"$comp" build "$src" -o "$out/prog" --cache-dir "$out/cache" "$@"

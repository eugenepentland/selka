#!/usr/bin/env bash
# Lox stage B on the take-fix compiler (9c24997e): runtime on CPU 10 under cpu10.lock,
# 3 rounds, the six cells that cannot finish left out; then the compile ladder and the
# unit tests under bench-compile.lock through a build slot.
set -u
cd "$(dirname "$0")/.."
export WORK=$PWD LOX_BENCH_MYLANG=$HOME/.cache/mylang/bench-newcore-9c24997e/bin/mylang
export TMPDIR=$PWD/.tmp/lox-bench/tmp XDG_CACHE_HOME=$PWD/.tmp/xdg PYTHONDONTWRITEBYTECODE=1 PATH=$HOME/.cargo/bin:$PATH
export LOX_SKIP=binary_trees/tree,binary_trees/vm,instantiation/vm,method_call/tree,trees/tree,trees/vm
SLOT=/home/epentland/ai/canopy/mylang-worktrees/claude-bench-newcore/scripts/build-slot.sh
LOCKS=/run/user/1000/mylang-slots
echo "runtime start $(date -u +%T) load $(cut -d' ' -f1-3 /proc/loadavg)"
flock "$LOCKS/cpu10.lock" python3 harness/measure.py runtime --ports mylang,zig,rust,go --profiles release,zig:release-safe --rounds 3 --cpu 10; echo "runtime=$?"
echo "compile start $(date -u +%T) load $(cut -d' ' -f1-3 /proc/loadavg)"
flock "$LOCKS/bench-compile.lock" "$SLOT" build -- python3 harness/measure.py compile --ports mylang,zig,rust,go --profiles release,debug --rounds 3 --cpus 0-1,4-9,12-19; echo "compile=$?"
flock "$LOCKS/bench-compile.lock" "$SLOT" build -- python3 harness/measure.py tests --ports mylang,zig,rust,go --rounds 3 --cpus 0-1,4-9,12-19; echo "tests=$?"
echo "done $(date -u +%T)"; ls -t results | head -5

#!/usr/bin/env bash
# CE-X, coordinator (2026-10-08): the six Lox cells that did not finish this morning. The
# feasibility pass found the final compiler finishes each in 0.25-5.6 s, so they get the timed
# protocol here: the final compiler against Zig, Zig-safe, Rust and Go, 3 rounds on CPU 10 under
# the lock, prebuilt binaries. The base compiler is left out: it did not finish these cells in
# 150 s this morning, and the user approved dropping its re-run.
set -u
WT=/home/epentland/ai/canopy/mylang-worktrees/claude-copy-elim
source $WT/experiments/ce-x-20261008/tools/env.sh
L=$WT/.mylang-cache/lox
LOCK=/run/user/1000/mylang-slots/cpu10.lock
cd $L
export WORK=$L LOX_BENCH_MYLANG=/home/epentland/.cache/mylang/ce-final-41931120/bin/mylang LOX_PREBUILT=1
export XDG_CACHE_HOME=$L/.tmp/xdg PYTHONDONTWRITEBYTECODE=1 PATH=$HOME/.cargo/bin:$PATH TMPDIR=$L/.tmp/lox-bench/tmp
# Every cell except the six: the 20 cells the main run timed.
export LOX_SKIP=closures/vm,closures/tree,equality/vm,equality/tree,fib/vm,fib/tree,instantiation/tree,invocation/vm,invocation/tree,method_call/vm,properties/vm,properties/tree,string_equality/vm,string_equality/tree,strings/vm,strings/tree,zoo/vm,zoo/tree,zoo_batch/vm,zoo_batch/tree
echo "$(date -u +%T) lox6 start load $(cut -d' ' -f1-3 /proc/loadavg)"
flock $LOCK python3 harness/measure.py runtime --ports mylang,zig,rust,go --profiles release,zig:release-safe --rounds 3 --cpu 10; echo "lox6=$?"
echo "$(date -u +%T) lox6 end"; ls -td results/*-runtime | head -1

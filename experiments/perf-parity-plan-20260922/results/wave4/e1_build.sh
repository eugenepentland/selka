#!/usr/bin/env bash
# E1: price the frame-map design's constraints on top of this lane's base.
#   <name>.before   plain default build, base compiler
#   <name>.fr       record, floor guard and positions stripped (stock adapter)
#   <name>.frk      record and positions stripped, floor guard kept (stock adapter)
#   <name>.frka1    as frk, adapter with FP non-leaf, no tail calls, noinline
#                   unless the unit makes no call, nomerge calls
set -u
W=/home/epentland/ai/canopy/mylang/.claude/worktrees/agent-a7fe8727a075af7ba
export TMPDIR=$HOME/.cache/mylang-tmp
MY=$W/.tmp/install-base/bin/mylang
SUITE=$W/experiments/perf-parity-plan-20260922/suite
MICRO=$W/experiments/perf-parity-audit-20260921/micro
BENCH=$W/.tmp/bench
mkdir -p $BENCH $W/.tmp/exp/e1-a0 $W/.tmp/exp/e1-a1
build_set() {
  src=$1; shift
  for n in "$@"; do
    python3 $W/.tmp/exp/counterfactual.py $n --src $src --work $W/.tmp/exp/e1-a0 --mylang $MY \
      --adapter $W/.tmp/exp/adapter-a0/qbe_llvm.py --arm fr=frames,positions --arm frk=framesk,positions
    python3 $W/.tmp/exp/counterfactual.py $n --src $src --work $W/.tmp/exp/e1-a1 --mylang $MY \
      --adapter $W/.tmp/exp/adapter-a1/qbe_llvm.py --arm frk=framesk,positions
    cp -f $W/.tmp/exp/e1-a0/$n.cf-plain $BENCH/$n.before
    cp -f $W/.tmp/exp/e1-a0/$n.fr $BENCH/$n.fr
    cp -f $W/.tmp/exp/e1-a0/$n.frk $BENCH/$n.frk
    cp -f $W/.tmp/exp/e1-a1/$n.frk $BENCH/$n.frka1
  done
}
build_set $SUITE binary_trees spectral_norm mandelbrot raytrace knucleotide text_ops sort_builtin sort_quick sort_records sieve nbody fannkuch_redux matmul
build_set $MICRO fib calls
echo E1-BUILD-DONE

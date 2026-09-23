#!/usr/bin/env bash
# R6: final lane compiler (CFI walk) against the base and the ladder-style
# counterfactuals; then the parser. CPU 0, loaded machine.
W=/home/epentland/ai/canopy/mylang/.claude/worktrees/agent-a7fe8727a075af7ba
export TMPDIR=$HOME/.cache/mylang-tmp
MY=$W/.tmp/install/bin/mylang
B=$W/experiments/perf-parity-plan-20260922/bench.py
OUT=$W/.tmp/exp/results
NAMES="binary_trees spectral_norm mandelbrot raytrace knucleotide text_ops sort_builtin sort_quick sort_records sieve nbody fannkuch_redux matmul"
python3 $B fib calls --src $W/experiments/perf-parity-audit-20260921/micro --mylang $MY --work $W/.tmp/bench \
  --cpu 0 --rounds 15 --arms zig-fast my --cf before --cf frk --cf fr --json $OUT/r6-micro.json
python3 $B $NAMES --src $W/experiments/perf-parity-plan-20260922/suite --mylang $MY --work $W/.tmp/bench \
  --cpu 0 --rounds 11 --arms zig-fast my --cf before --cf frk --cf fr --json $OUT/r6-suite.json
ROUNDS=11 bash $W/.tmp/exp/parser.sh
echo R6-DONE

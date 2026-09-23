#!/usr/bin/env bash
# R7: CFI walk (my) vs the same compiler with guest frame pointers kept (myfp).
W=/home/epentland/ai/canopy/mylang/.claude/worktrees/agent-a7fe8727a075af7ba
export TMPDIR=$HOME/.cache/mylang-tmp
MY=$W/.tmp/install/bin/mylang
B=$W/experiments/perf-parity-plan-20260922/bench.py
OUT=$W/.tmp/exp/results
FP=$W/.tmp/exp/adapter-fp
mkdir -p $FP
cp $W/experiments/llvm-backend/*.py $FP/
sed -i 's|return \["uwtable", |return ["uwtable", "\\"frame-pointer\\"=\\"non-leaf\\"", |' $FP/llvm_emit.py
grep -n 'return \["uwtable"' $FP/llvm_emit.py
SUITE=$W/experiments/perf-parity-plan-20260922/suite
MICRO=$W/experiments/perf-parity-audit-20260921/micro
b() { src=$1; shift; for n in "$@"; do (cd $src && $MY build $n.my -o $W/.tmp/bench/$n.myfp --cache-dir $W/.tmp/bench/fpcache \
  --backend llvm --llvm-opt 3 --lto --llvm-adapter $FP/qbe_llvm.py) || echo "FP BUILD FAIL $n"; done; }
b $MICRO fib
b $SUITE matmul fannkuch_redux sort_quick raytrace sieve spectral_norm
python3 $B fib --src $MICRO --mylang $MY --work $W/.tmp/bench --cpu 0 --rounds 15 --arms zig-fast --skip-build \
  --cf my --cf myfp --cf before --json $OUT/r7-micro.json
python3 $B matmul fannkuch_redux sort_quick raytrace sieve spectral_norm --src $SUITE --mylang $MY --work $W/.tmp/bench \
  --cpu 0 --rounds 15 --arms zig-fast --skip-build --cf my --cf myfp --cf before --json $OUT/r7-suite.json
echo R7-DONE

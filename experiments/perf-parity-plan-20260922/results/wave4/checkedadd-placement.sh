#!/usr/bin/env bash
# Build fib from source paths of different lengths (which moves the code in the
# binary) with the base and the lane compiler; print each build's fib address.
set -e
W=$(cd "$(dirname "$0")/.." && pwd)
export TMPDIR=/home/epentland/.cache/mylang-tmp
D=$W/.tmp/placement
mkdir -p $D
for pad in a bb cccc dddddddd eeeeeeeeeeeeeeee ffffffffffffffffffffffffffffffff; do
  mkdir -p $D/$pad
  cp $W/experiments/perf-parity-audit-20260921/micro/fib.my $D/$pad/fib.my
  for arm in base lane; do
    $W/.tmp/install-$arm/bin/mylang build $D/$pad/fib.my -o $D/fib-$arm-$pad --cache-dir $W/.tmp/cache-$arm
    addr=$(objdump -d --no-show-raw-insn $D/fib-$arm-$pad | grep -B4 "cmp    %rsp,0x40(%rdi)" | head -1 | awk '{print $1}')
    echo "$arm $pad $addr"
  done
done

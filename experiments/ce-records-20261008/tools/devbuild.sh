#!/usr/bin/env bash
# Build and install the compiler through the build slot into a private prefix, and copy it
# to .mylang-cache/ce/compilers/NAME (default `dev`): a compiler for counting, never the gate.
set -u
WT=/home/epentland/ai/canopy/mylang-worktrees/claude-ce-records
source $WT/experiments/ce-records-20261008/tools/env.sh
cd $WT
name=${1:-dev}
prefix=$WT/.mylang-cache/ce/prefix-$name
rm -rf "$prefix"
$WT/scripts/build-slot.sh build zig build --prefix "$prefix" 2>&1 | grep -E "error:|failed|run-all" | grep -v "failed command" | head -20
mkdir -p $WT/.mylang-cache/ce/compilers
if [ -x "$prefix/bin/mylang" ]; then
  cp "$prefix/bin/mylang" $WT/.mylang-cache/ce/compilers/$name
  echo "compiler $name: $(sha256sum < $WT/.mylang-cache/ce/compilers/$name | cut -c1-16)"
else
  echo "compiler $name: NOT INSTALLED (build or Guardian failed)"; exit 1
fi

#!/usr/bin/env bash
# matrix.sh: before/after test-after-edit timings. Each compiler has its own warm cache.
D=/tmp/claude-1000/-home-epentland-ai-canopy-mylang/03fe2647-29f7-4cb8-b6b6-59b6334d6da0/scratchpad/testloop
EDA=/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore
declare -A C=([base]=$HOME/.cache/mylang/test-loop-wip/bin/mylang [new]=$HOME/.cache/mylang/t3b-wip/bin/mylang)
for c in base new; do
  export MYLANG=${C[$c]} PROBE=$EDA/.cache/probe-t3b-$c
  JOBS=4 $D/probe.sh warm > /dev/null 2>&1; JOBS=4 $D/probe.sh warm 2>&1 | tail -2 | paste - - | sed "s/^/warm $c: /"
  for j in 4 all; do for k in hub leaf iface comment; do for r in 1 2 3; do
    out=$(JOBS=$j $D/probe.sh edit $k 2>&1)
    w=$(echo "$out" | sed -n 3p | awk '{print $2}'); n=$(echo "$out" | sed -n 2p | awk '{print $1}')
    echo "$c jobs=$j $k r$r wall=$w ran=$n"
  done; done; done
done

#!/usr/bin/env bash
D=/tmp/claude-1000/-home-epentland-ai-canopy-mylang/03fe2647-29f7-4cb8-b6b6-59b6334d6da0/scratchpad/testloop
EDA=/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore
declare -A C=([base]=$HOME/.cache/mylang/test-loop-wip/bin/mylang [new]=$HOME/.cache/mylang/t3b-wip/bin/mylang)
for r in 1 2 3 4 5; do for j in 4 all; do for k in iface comment hub leaf; do for c in base new; do
  out=$(MYLANG=${C[$c]} PROBE=$EDA/.cache/probe-t3b-$c JOBS=$j $D/probe.sh edit $k 2>&1)
  echo "$c jobs=$j $k r$r wall=$(echo "$out" | sed -n 3p | awk '{print $2}') ran=$(echo "$out" | sed -n 2p | awk '{print $1}') load=$(cut -d' ' -f1 /proc/loadavg)"
done; done; done; done

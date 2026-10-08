#!/usr/bin/env bash
# interleave-batch.sh: main against fast spawn plus no cache sync, 5 interleaved rounds.
D=$(cd "$(dirname "$0")" && pwd)
EDA=/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore
declare -A C=([nosync]=$HOME/.cache/mylang/nosync-wip/bin/mylang [union]=$HOME/.cache/mylang/union-wip/bin/mylang)
for c in nosync union; do
  MYLANG=${C[$c]} PROBE=$EDA/.cache/probe-b-$c JOBS=all $D/probe.sh warm > /dev/null 2>&1
  echo "warm $c: $(MYLANG=${C[$c]} PROBE=$EDA/.cache/probe-b-$c JOBS=all $D/probe.sh warm 2>&1 | tail -2 | paste - -)"
done
for r in 1 2 3; do for j in all; do for k in hub leaf iface comment; do for c in nosync union; do
  out=$(MYLANG=${C[$c]} PROBE=$EDA/.cache/probe-b-$c JOBS=$j $D/probe.sh edit $k 2>&1)
  echo "$c jobs=$j $k r$r wall=$(echo "$out" | sed -n 3p | awk '{print $2}') ran=$(echo "$out" | sed -n 2p | awk '{print $1}') load=$(cut -d' ' -f1 /proc/loadavg)"
done; done; done; done

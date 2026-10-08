#!/usr/bin/env bash
# interleave-batch.sh: item 4 against the fast spawn (NEW-CORE-SPAWN-1), 5 interleaved rounds.
D=$(cd "$(dirname "$0")" && pwd)
EDA=/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore
declare -A C=([batch]=$HOME/.cache/mylang/batch-wip/bin/mylang [spawn]=$HOME/.cache/mylang/spawn-wip/bin/mylang)
for c in batch spawn; do
  MYLANG=${C[$c]} PROBE=$EDA/.cache/probe-b-$c JOBS=all $D/probe.sh warm > /dev/null 2>&1
  echo "warm $c: $(MYLANG=${C[$c]} PROBE=$EDA/.cache/probe-b-$c JOBS=all $D/probe.sh warm 2>&1 | tail -2 | paste - -)"
done
for r in 1 2 3 4 5; do for j in all 4; do for k in hub leaf iface comment; do for c in batch spawn; do
  out=$(MYLANG=${C[$c]} PROBE=$EDA/.cache/probe-b-$c JOBS=$j $D/probe.sh edit $k 2>&1)
  echo "$c jobs=$j $k r$r wall=$(echo "$out" | sed -n 3p | awk '{print $2}') ran=$(echo "$out" | sed -n 2p | awk '{print $1}') load=$(cut -d' ' -f1 /proc/loadavg)"
done; done; done; done

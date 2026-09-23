#!/usr/bin/env bash
# Build time of the S-expression parser (project) and raytrace: cold object
# cache, then a relink to a new output path with every object cached.
W=/home/epentland/ai/canopy/mylang/.claude/worktrees/agent-a7fe8727a075af7ba
export TMPDIR=$HOME/.cache/mylang-tmp
PARSER=/home/epentland/ai/canopy/mylang/.tmp/perf-plan-20260922/work/sexpr-port-mut/main.my
RAY=$W/experiments/perf-parity-plan-20260922/suite/raytrace.my
D=$W/.tmp/exp/buildtime
rm -rf $D; mkdir -p $D
for arm in before:$W/.tmp/install-base/bin/mylang my:$W/.tmp/install/bin/mylang; do
  name=${arm%%:*}; mc=${arm#*:}
  for prog in parser:$PARSER:--project ray:$RAY:; do
    p=${prog%%:*}; rest=${prog#*:}; src=${rest%%:*}; flag=${rest#*:}
    s=$(date +%s.%N); taskset -c 2-19 $mc build $src $flag -o $D/$p-$name-1 --cache-dir $D/cache-$name-$p >/dev/null 2>&1 || echo FAIL; e=$(date +%s.%N)
    s2=$(date +%s.%N); taskset -c 2-19 $mc build $src $flag -o $D/$p-$name-2 --cache-dir $D/cache-$name-$p >/dev/null 2>&1 || echo FAIL; e2=$(date +%s.%N)
    echo "$p $name cold=$(echo "$e - $s" | bc) relink=$(echo "$e2 - $s2" | bc) size=$(stat -c %s $D/$p-$name-1)"
  done
done

#!/usr/bin/env bash
# CE-X Part 1 items 4-8 and Part 2: Lox, EDA, parity and rows with the final ReleaseFast compiler,
# counting on/off, and final against base. Builds through the build slot; runs off CPUs 2,3,10,11.
set -u
WT=/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure
source $WT/experiments/fu-x-20261009/tools/env.sh
cd $WT
X=experiments/fu-x-20261009; T=$X/tools/ce.py
C=/home/epentland/.cache/mylang/fu-final-x/bin/mylang
B=/home/epentland/.cache/mylang/main-ab85c16c/bin/mylang
SLOT=$WT/scripts/build-slot.sh
CPUS=0,1,4-9,12-19
echo "final $(sha256sum < $C | cut -c1-16) base $(sha256sum < $B | cut -c1-16) start $(date -u +%T)"
python3 $T --compiler $C --tag final build all > $X/logs/build-final.log 2>&1; echo "build final=$? $(date -u +%T)"
python3 $T --compiler $B --tag base build all > $X/logs/build-base.log 2>&1; echo "build base=$? $(date -u +%T)"
# Lox conformance, both engines, normal and gc-stress
(cd .mylang-cache/lox && taskset -c $CPUS python3 harness/lox_bench.py conformance --binary $WT/.mylang-cache/cex/ce/bin/final/lox-plain --engine both --stress -j 4) > $X/logs/lox-conformance.log 2>&1; echo "lox conformance=$?"; grep conformance $X/logs/lox-conformance.log
# Lox port tests
(cd .mylang-cache/lox/ports/mylang && $SLOT build -- $C test . --max-steps=100000000 --cache-dir $WT/.mylang-cache/cex/lox-test) > $X/logs/lox-port-tests.log 2>&1; echo "lox port tests=$?"; tail -n 1 $X/logs/lox-port-tests.log
# EDA tests
(cd .mylang-cache/cex/eda-src && $SLOT build -- $C test src --jobs 4 --max-frames 30000 --max-steps 4000000000 --max-memory 2G --cache-dir $WT/.mylang-cache/cex/eda-test) > $X/logs/eda-tests.log 2>&1; echo "eda tests=$?"; tail -n 1 $X/logs/eda-tests.log
# Counting on and off, goldens, parity .expected, counters (Part 2)
python3 $T --compiler $C --tag final run all > $X/logs/run-final.log 2>&1; echo "run final=$? $(date -u +%T)"; cat $X/logs/run-final.log
# Final against base
python3 $X/tools/identity.py $X/results/identity.json > $X/logs/identity.log 2>&1; echo "identity=$? $(date -u +%T)"; cat $X/logs/identity.log
echo "part1b done $(date -u +%T)"

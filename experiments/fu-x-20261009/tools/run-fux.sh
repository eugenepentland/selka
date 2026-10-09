#!/usr/bin/env bash
# FU-X driver (coordinator, 2026-10-09): the ReleaseFast compiler of the F/U integration (lanes F2
# and U1) at ~/.cache/mylang/fu-final-x, then Part 1 (part1a beside timing-prep + part1b), a strict
# check of every Part 1 line, and Part 3 one step at a time on CPU 10. No timing if a check fails.
# Base is main ab85c16c2 (~/.cache/mylang/main-ab85c16c). All 26 Lox cells are timed: both lanes
# change the Lox VM.
set -u
WT=/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure
X=$WT/experiments/fu-x-20261009
T=$X/tools
source $T/env.sh
cd $WT
echo "STEP start $(git rev-parse --short HEAD) $(date -u +%T) load $(cut -d' ' -f1-3 /proc/loadavg)"
scripts/build-slot.sh build -- zig build -Doptimize=ReleaseFast --prefix /home/epentland/.cache/mylang/fu-final-x --summary all > $X/logs/releasefast-build.log 2>&1
echo "STEP releasefast=$? $(date -u +%T)"
bash $T/part1a.sh > $X/logs/part1a.log 2>&1 &
A=$!
( bash $T/timing-prep.sh > $X/logs/timing-prep.log 2>&1; bash $T/part1b.sh > $X/logs/part1b.log 2>&1 ) &
P=$!
wait $A; echo "STEP part1a finished $(date -u +%T)"
wait $P; echo "STEP part1b and prep finished $(date -u +%T)"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
L1=$X/logs/part1a.log; F=$X/logs/fuzz200.out; B1=$X/logs/part1b.log; R=$X/logs/timing-prep.log
check "gate exit 0" "grep -q '^gate=0' $L1"
check "gate all steps" "bash $T/gate_ok.sh $L1"
check "fmt exit 0" "grep -q '^fmt=0' $L1"
check "qualify exit 0" "grep -q '^qualify=0' $L1"
check "conformance debug 1518/0/0" "grep -q 'debug    matching 1518, mismatching 0, unsupported 0' $L1"
check "conformance release 1518/0/0" "grep -q 'release  matching 1518, mismatching 0, unsupported 0' $L1"
check "fuzz200 exit 0" "grep -q '^fuzz200=0' $L1"
check "fuzz200 nine kinds PASS" "[ \$(grep -cE '^[a-z0-9]+: PASS;' $F) -eq 9 ]"
check "fuzz200 no FAIL or STOP" "! grep -qE 'FAIL|STOP' $F"
check "build final" "grep -q '^build final=0' $B1"
check "build base" "grep -q '^build base=0' $B1"
check "lox conformance exit 0" "grep -q '^lox conformance=0' $B1"
check "lox vm normal 246/246" "grep -q 'engine=vm gc=normal: 246/246 passed' $B1"
check "lox vm gc-stress 246/246" "grep -q 'engine=vm gc=gc-stress: 246/246 passed' $B1"
check "lox tree normal 241/241" "grep -q 'engine=tree gc=normal: 241/241 passed' $B1"
check "lox tree gc-stress 241/241" "grep -q 'engine=tree gc=gc-stress: 241/241 passed' $B1"
check "lox port tests exit 0" "grep -q '^lox port tests=0' $B1"
check "lox port tests 65 passed" "grep -qE '^65 passed, .* 0 failed' $B1"
check "eda tests exit 0" "grep -q '^eda tests=0' $B1"
check "eda tests 310 passed" "grep -qE '^310 passed, .* 0 failed' $B1"
check "run final exit 0" "grep -q '^run final=0' $B1"
for g in 'lox: 48' 'eda: 34' 'parity: 4' 'rows: 46'; do
  check "run final $g, 0 not identical" "grep -q '^$g cells, 0 not identical or uncounted' $B1"
done
check "identity exit 0" "grep -q '^identity=0' $B1"
for g in 'lox: 48 cells, 48' 'eda: 34 cells, 34' 'parity: 4 cells, 4' 'rows: 46 cells, 46'; do
  check "identity $g identical" "grep -q '^$g identical, differing: \[\]' $B1"
done
check "part1b done" "grep -q '^part1b done' $B1"
check "timing-prep lox builds" "[ \$(grep -cE '^lox build .*=0$' $R) -eq 6 ]"
check "timing-prep rows build" "grep -q '^rows build=0' $R"
if [ $fail -ne 0 ]; then echo "STEP STOPPED: a Part 1 check failed, no timing $(date -u +%T)"; exit 1; fi
echo "STEP part1 green $(date -u +%T)"
LOX_SKIP= bash $T/part3.sh lox; echo "STEP lox done $(date -u +%T)"
bash $T/part3.sh eda; echo "STEP eda done $(date -u +%T)"
bash $T/part3.sh parity; echo "STEP parity done $(date -u +%T)"
for n in 1 2 3; do bash $T/part3.sh rows $n; echo "STEP rows $n done $(date -u +%T)"; done
echo "STEP part3 done $(date -u +%T)"

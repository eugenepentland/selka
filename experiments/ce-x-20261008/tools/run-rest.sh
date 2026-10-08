#!/usr/bin/env bash
# CE-X, coordinator (2026-10-08): wait for part1a.sh, part1b.sh and timing-prep.sh, check every
# Part 1 line, run Part 2's tables, then Part 3 one step at a time. No timing if a check fails.
# Cuts approved by the user: the base compiler skips the six Lox cells it could not finish this
# morning (feasible.py), and the base parity run times only the mylang arms (part3.sh).
set -u
WT=/home/epentland/ai/canopy/mylang-worktrees/claude-copy-elim
X=$WT/experiments/ce-x-20261008
P3=$X/tools/part3.sh
for p in 4076557 112041 118596; do
  while kill -0 $p 2>/dev/null; do sleep 15; done
done
echo "STEP part1 and prep finished $(date -u +%T)"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
A=$X/logs/part1a.log; F=$X/logs/fuzz200.out; B1=$X/logs/part1b.log; R=$X/logs/timing-prep.log
check "fuzz200 exit 0" "grep -q '^fuzz200=0' $A"
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
python3 $X/tools/tables.py > $X/logs/tables.out 2>&1; echo "STEP tables=$? $(date -u +%T)"
bash $P3 feasible; echo "STEP feasible done $(date -u +%T)"
LOX_SKIP=binary_trees/tree,binary_trees/vm,trees/tree,trees/vm,instantiation/vm,method_call/tree bash $P3 lox
echo "STEP lox done $(date -u +%T)"
bash $P3 eda; echo "STEP eda done $(date -u +%T)"
bash $P3 parity; echo "STEP parity done $(date -u +%T)"
for n in 1 2 3; do bash $P3 rows $n; echo "STEP rows $n done $(date -u +%T)"; done
echo "STEP part3 done $(date -u +%T)"

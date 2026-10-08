#!/usr/bin/env bash
# CE2-X run 2, stage 2 (coordinator): run 1's qualify left .mylang-cache/s5/integration-qualify/qualify,
# so run 2's qualify (same evidence name) crashed on mkdir before testing anything. Wait for the
# driver to stop, run conformance under a fresh name, run every Part 1 check again, then Part 2/3.
set -u
WT=/home/epentland/ai/canopy/mylang-worktrees/claude-main-ce
X=$WT/experiments/ce2-x-20261008
T=$X/tools
source $T/env.sh
cd $WT
while kill -0 874645 2>/dev/null; do sleep 15; done
echo "STEP stage2b start $(date -u +%T)"
python3 experiments/new-core-s5-20261007/tools/qualify_merge.py --shards 64 --compiler zig-out/bin/mylang --install install --evidence $X/qualify-run2 > $X/logs/qualify-run2.out 2>&1
q=$?
{ echo "qualify=$q $(date -u +%T)"; grep -E '"qualified"' $X/qualify-run2/summary.json; grep -E "^  (debug|release) " $X/qualify-run2/full-conformance.log; } > $X/logs/part1a-qualify2.log 2>&1
echo "STEP qualify-run2=$q $(date -u +%T)"; cat $X/logs/part1a-qualify2.log
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
L1=$X/logs/part1a.log; Q=$X/logs/part1a-qualify2.log; F=$X/logs/fuzz200.out; B1=$X/logs/part1b.log; R=$X/logs/timing-prep.log
check "gate exit 0" "grep -q '^gate=0' $L1"
check "gate 88/88" "grep -q '^Build Summary: 88/88 steps succeeded' $L1"
check "fmt exit 0" "grep -q '^fmt=0' $L1"
check "qualify exit 0 (qualify-run2)" "grep -q '^qualify=0' $Q"
check "conformance debug 1518/0/0" "grep -q 'debug    matching 1518, mismatching 0, unsupported 0' $Q"
check "conformance release 1518/0/0" "grep -q 'release  matching 1518, mismatching 0, unsupported 0' $Q"
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
python3 $T/tables.py > $X/logs/tables.out 2>&1; echo "STEP tables=$? $(date -u +%T)"
LOX_SKIP= bash $T/part3.sh lox; echo "STEP lox done $(date -u +%T)"
bash $T/part3.sh eda; echo "STEP eda done $(date -u +%T)"
bash $T/part3.sh parity; echo "STEP parity done $(date -u +%T)"
for n in 1 2 3; do bash $T/part3.sh rows $n; echo "STEP rows $n done $(date -u +%T)"; done
echo "STEP part3 done $(date -u +%T)"

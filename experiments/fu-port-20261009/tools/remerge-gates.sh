#!/usr/bin/env bash
# FU-PORT re-merge gates (coordinator, 2026-10-09): every gate again after merging main 8a2fccd2f
# (the frontend follow-through) into claude/fu-port, with the same tools the port used.
set -u
WT=/home/epentland/ai/canopy/mylang-worktrees/claude-main-ce
X=$WT/experiments/fu-port-20261009
source $X/tools/env.sh
cd $WT
L=$X/logs/remerge
mkdir -p $L
CPUS=0,1,4-9,12-19
echo "commit $(git rev-parse --short HEAD) start $(date -u +%T)"
scripts/build-slot.sh gate -- zig build test --summary all > $L/gate.log 2>&1; echo "gate=$? $(date -u +%T)"; grep -E '^Build Summary' $L/gate.log
scripts/build-slot.sh build -- zig build fmt-check > $L/fmt.log 2>&1; echo "fmt=$?"
RF=$WT/.mylang-cache/compilers/port-remerge
scripts/build-slot.sh build -- zig build -Doptimize=ReleaseFast --prefix $RF > $L/releasefast.log 2>&1; echo "releasefast=$? $(date -u +%T)"
python3 experiments/new-core-s5-20261007/tools/qualify_merge.py --shards 64 --compiler zig-out/bin/mylang --install install --evidence $X/qualify-remerge > $L/qualify.out 2>&1; echo "qualify=$? $(date -u +%T)"
grep -hE "^  (debug|release) " $X/qualify-remerge/full-conformance.log
python3 $X/tools/outputs.py --compiler $RF/bin/mylang --tag remerge build > $L/outputs-build.log 2>&1; echo "outputs build=$?"
python3 $X/tools/outputs.py --compiler $RF/bin/mylang --tag remerge eda > $L/outputs-eda.log 2>&1; echo "outputs eda=$?"; tail -n 2 $L/outputs-eda.log
python3 $X/tools/outputs.py --compiler $RF/bin/mylang --tag remerge parity > $L/outputs-parity.log 2>&1; echo "outputs parity=$?"; tail -n 2 $L/outputs-parity.log
(cd .mylang-cache/lox && taskset -c $CPUS python3 harness/lox_bench.py conformance --binary $WT/.mylang-cache/fuport/bin/remerge/lox-plain --engine both --stress -j 4) > $L/lox-conformance.log 2>&1; echo "lox conformance=$?"; grep conformance $L/lox-conformance.log
(cd .mylang-cache/lox/ports/mylang && $WT/scripts/build-slot.sh build -- $RF/bin/mylang test . --max-steps=100000000 --cache-dir $WT/.mylang-cache/fuport/lox-test-remerge) > $L/lox-port-tests.log 2>&1; echo "lox port tests=$?"; tail -n 1 $L/lox-port-tests.log
(cd .mylang-cache/eda-src && $WT/scripts/build-slot.sh build -- $RF/bin/mylang test src --jobs 4 --max-frames 30000 --max-steps 4000000000 --max-memory 2G --cache-dir $WT/.mylang-cache/fuport/eda-test-remerge) > $L/eda-tests.log 2>&1; echo "eda tests=$?"; tail -n 1 $L/eda-tests.log
cp zig-out/bin/mylang .mylang-cache/fuport/mylang-debug-remerge
FU_PORT_REAL=$WT/.mylang-cache/fuport/mylang-debug-remerge FU_PORT_LOG=$L/fuzz-migrations.log \
  python3 experiments/new-core-s5-20261007/tools/fuzz_matrix.py --references experiments/new-core-s5-20261007/references/fuzz-v1.json.gz \
  --new $X/tools/mylang-migrating --cases 50 --evidence $X/fuzz50-remerge --jobs 3 > $L/fuzz.out 2>&1; echo "fuzz=$? $(date -u +%T)"
grep -E "PASS|STOP|FAIL" $L/fuzz.out | tr '\n' ' '; echo
echo "done $(date -u +%T)"

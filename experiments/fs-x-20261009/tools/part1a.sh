#!/usr/bin/env bash
# CE-X Part 1, first half: full gate, fmt-check, conformance qualification, frozen fuzz 9x200.
set -u
WT=/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure
source $WT/experiments/fs-x-20261009/tools/env.sh
cd $WT
X=experiments/fs-x-20261009
echo "commit $(git rev-parse HEAD) start $(date -u +%T) load $(cut -d' ' -f1-3 /proc/loadavg)"
/usr/bin/time -f "gate wall %e s" scripts/build-slot.sh gate -- zig build test --summary all > $X/logs/gate.log 2>&1; echo "gate=$? $(date -u +%T)"
tail -n 3 $X/logs/gate.log; grep -E "^Build Summary" $X/logs/gate.log
scripts/build-slot.sh build -- zig build fmt-check --summary none > $X/logs/fmt-check.log 2>&1; echo "fmt=$?"
python3 experiments/new-core-s5-20261007/tools/qualify_merge.py --shards 64 --compiler zig-out/bin/mylang --install install --evidence $WT/$X/qualify-fsx2 > $X/logs/qualify.out 2>&1; echo "qualify=$? $(date -u +%T)"
grep -E '"qualified"' $X/qualify-fsx2/summary.json; grep -E "^  (debug|release) " $X/qualify-fsx2/full-conformance.log
mkdir -p .mylang-cache/cex; cp zig-out/bin/mylang .mylang-cache/cex/mylang-debug
python3 experiments/new-core-s5-20261007/tools/fuzz_matrix.py --references experiments/new-core-s5-20261007/references/fuzz-v1.json.gz --new .mylang-cache/cex/mylang-debug --cases 200 --evidence $WT/$X/fuzz200-2 --jobs 3 > $X/logs/fuzz200.out 2>&1; echo "fuzz200=$? $(date -u +%T)"
grep -E "PASS|STOP|FAIL" $X/logs/fuzz200.out | tr '\n' ' '; echo
echo "part1a done $(date -u +%T)"

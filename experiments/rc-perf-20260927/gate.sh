#!/bin/bash
# Integration gate: harness rows (43 programs x QBE/LLVM), the full zig gate, tests/lang in nine
# runtime modes, and the Lox port under both runtimes. Run from any worktree after
# `python3 experiments/rc-perf-20260927/quick.py setup`:  experiments/rc-perf-20260927/gate.sh TAG
# Results: .tmp-gate/TAG/summary.txt (one line per step, exit status first). About 2 hours on the
# shared i7-12700H. Keep ZIG_GLOBAL_CACHE_DIR warm, or two CLI tests fail on zig's `ar rcs` stderr.
set -uo pipefail
cd "$(dirname "$0")/../.."
TAG=${1:?tag}
export TMPDIR="$PWD/.tmp-gate/tmp"
L=.tmp-gate/$TAG; mkdir -p "$L" "$TMPDIR"
echo "commit $(git rev-parse --short HEAD)" > $L/summary.txt
git diff --quiet HEAD || { echo "dirty tree" >> $L/summary.txt; exit 2; }
scripts/build-slot.sh build zig build --prefix .tmp-rc-quick/compilers/$TAG > $L/build-prefix.log 2>&1 || { echo "prefix build FAIL" >> $L/summary.txt; exit 1; }
scripts/build-slot.sh build zig build > $L/build.log 2>&1; echo "build $?" >> $L/summary.txt
Q="python3 $PWD/experiments/rc-perf-20260927/quick.py"
(cd .tmp-rc-quick && $Q build --compiler compilers/$TAG/bin/mylang --tag $TAG --jobs 3) > $L/corpus-build.log 2>&1; echo "corpus-build $?" >> $L/summary.txt
for size in dev smoke; do (cd .tmp-rc-quick && $Q measure --tag $TAG --size $size --jobs 12) > $L/measure-$size.log 2>&1; echo "measure-$size $?" >> $L/summary.txt; done
for step in test test-qbe test-qbe-build fmt-check test-native-memory test-native-heap; do scripts/build-slot.sh gate zig build $step --summary all > $L/$step.log 2>&1; echo "$step $?" >> $L/summary.txt; done
M=$PWD/.tmp-rc-quick/compilers/$TAG/bin/mylang
SLOT=$PWD/scripts/build-slot.sh
for mode in "--rc-runtime=stats" "--rc-runtime" "--gc-runtime" ""; do for rel in "" "--release"; do
  n="sweep${mode:-=default}${rel:+-release}"
  scripts/build-slot.sh build $M test tests/lang $mode --force --json --jobs 6 $rel > $L/$n.json 2> $L/$n.log; echo "$n $? $(tail -1 $L/$n.log)" >> $L/summary.txt
done; done
scripts/build-slot.sh build $M test tests/lang --gc-runtime --gc-stress --force --json --jobs 6 > $L/sweep-gc-stress.json 2> $L/sweep-gc-stress.log; echo "sweep-gc-stress $?" >> $L/summary.txt
P=$PWD/.tmp-gate/$TAG/lox-port
mkdir -p "$P" || exit 1
cp -a .tmp-rc-quick/lox/benchmarks/lox/ports/mylang/. "$P/" || exit 1
for rel in "" "--release"; do
  for rt in "" "--gc-runtime"; do
  (cd "$P" && "$SLOT" build "$M" test . $rt --force --max-steps=100000000 $rel) > $L/lox-tests$rt$rel.log 2>&1; echo "lox-tests$rt$rel $? $(tail -1 $L/lox-tests$rt$rel.log)" >> $L/summary.txt
  (cd "$P" && "$SLOT" build "$M" test driver_tests.my --force --cases driver_cases.json --max-steps=100000000 $rt $rel) > $L/lox-driver$rt$rel.log 2>&1; echo "lox-driver$rt$rel $? $(tail -1 $L/lox-driver$rt$rel.log)" >> $L/summary.txt
  done
done
test "$(git rev-parse --short HEAD)" = "$(head -1 $L/summary.txt | cut -d' ' -f2)" || echo "HEAD moved during gate" >> $L/summary.txt
echo done >> $L/summary.txt
# Inspect every recorded status; the last echo must not hide an earlier failure.
awk '
  NR == 1 { next }
  $0 == "done" { next }
  NF < 2 || $2 != "0" { failed = 1; print "gate failure: " $0 > "/dev/stderr" }
  END { exit failed }
' "$L/summary.txt"

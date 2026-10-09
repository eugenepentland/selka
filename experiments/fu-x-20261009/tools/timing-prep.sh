#!/usr/bin/env bash
# CE-X Part 3 preparation (untimed, no lock): every binary the timed runs use, built through
# the build slot (off CPUs 2,3,10,11). Lox: the harness's release builds of every port, plus
# `mylang-base` (the same port built by the base compiler). EDA: Zig/Rust/Go release binaries
# are the morning's ($EDA/.cache/release, read only); mylang's are ce.py's eda-plain.
# Rows: measure_all46.py --build-only, base as "old", final as "new".
set -u
WT=/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure
source $WT/experiments/fu-x-20261009/tools/env.sh
X=$WT/experiments/fu-x-20261009
C=/home/epentland/.cache/mylang/fu-final-x/bin/mylang
B=/home/epentland/.cache/mylang/main-35df839b/bin/mylang
SLOT=$WT/scripts/build-slot.sh
L=$WT/.mylang-cache/lox
cd $L
export LOX_BENCH_MYLANG=$C XDG_CACHE_HOME=$L/.tmp/xdg PYTHONDONTWRITEBYTECODE=1 PATH=$HOME/.cargo/bin:$PATH
export TMPDIR=$L/.tmp/lox-bench/tmp
for pp in mylang:release mylang-base:release zig:release zig:release-safe rust:release go:release; do
  "$SLOT" build -- python3 harness/lox_bench.py build --port "${pp%%:*}" --profile "${pp#*:}"; echo "lox build $pp=$?"
done
source $WT/experiments/fu-x-20261009/tools/env.sh
cd $WT
"$SLOT" build -- python3 experiments/new-core-s4-20261006/integration/measure_all46.py --build-only --mylang $B --core $C --bin $WT/.mylang-cache/cex/all46 > $X/logs/all46-build.log 2>&1; echo "rows build=$?"
echo "prep done $(date -u +%T)"

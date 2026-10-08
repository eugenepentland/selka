#!/usr/bin/env bash
# EDA benchmark stage 1 (eda-sch) rerun on mylang's new core, 2026-10-08.
#
#   run.sh prep      untimed: equiv (debug + release mylang-new, zig, go, rust) and each port's tests
#   run.sh time      bench.py time --stage 1 --repeat 3 for zig, go, rust, mylang-new, back to back,
#                    each under flock bench-compile.lock and the build-slot wrapper (keeps CPUs 2,3,10,11 free)
#   run.sh runtime   release binaries of every port, then runtime.py under flock cpu10.lock, pinned to CPU 10
#   run.sh supplement  mylang-new cold/clean only, 5 repetitions (same lock and wrapper), plus an untimed
#                    breakdown of the mylang cold build by which cache layer is empty
#
# EDA is the eda-bench worktree on branch claude/eda-bench-newcore (harness entries mylang-new,
# mylang-new-release); every cache and TMPDIR stays under $EDA/.cache.
set -euo pipefail
EDA=${EDA:-/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore}
HERE=$(cd "$(dirname "$0")" && pwd)
SLOT=/home/epentland/ai/canopy/mylang-worktrees/claude-bench-newcore/scripts/build-slot.sh
LOCKS=/run/user/1000/mylang-slots
MYLANG=$HOME/.cache/mylang/bench-newcore-5a6b501d/bin/mylang
export TMPDIR=$EDA/.cache/tmp
mkdir -p "$TMPDIR" "$HERE/logs"
cd "$EDA"

load() { echo "$(date -Is) $1 loadavg $(cut -d' ' -f1-3 /proc/loadavg)" | tee -a "$HERE/logs/load.log"; }

case ${1:-} in
prep)
  for l in mylang-new mylang-new-release zig go rust; do
    "$SLOT" build -- python3 harness/bench.py equiv "$l" > "$HERE/logs/equiv-$l.log" 2>&1
    tail -1 "$HERE/logs/equiv-$l.log"
  done
  for l in mylang-new zig go rust; do
    "$SLOT" build -- python3 harness/bench.py test "$l" > "$HERE/logs/test-$l.log" 2>&1
    tail -1 "$HERE/logs/test-$l.log"
  done
  ;;
time)
  for l in ${LANGS:-zig go rust mylang-new}; do
    load "before time $l"
    flock "$LOCKS/bench-compile.lock" "$SLOT" build -- \
      python3 harness/bench.py time "$l" --stage 1 --repeat "${REPEAT:-3}" 2>&1 | tee "$HERE/logs/time-$l.log"
    load "after time $l"
  done
  mkdir -p "$HERE/results"
  cp harness/results/time-stage1-*.json "$HERE/results/"
  ;;
runtime)
  R=$EDA/.cache/release
  mkdir -p "$R" "$R/mylang"   # mylang build does not create the -o directory
  # Untimed release builds of each port (outside the timed CPU).
  ( cd zig && ZIG_LOCAL_CACHE_DIR=$R/zig-local ZIG_GLOBAL_CACHE_DIR=$R/zig-global \
      "$SLOT" build -- zig build -Doptimize=ReleaseFast -p "$R/zig-fast" )
  ( cd zig && ZIG_LOCAL_CACHE_DIR=$R/zig-local ZIG_GLOBAL_CACHE_DIR=$R/zig-global \
      "$SLOT" build -- zig build -Doptimize=ReleaseSafe -p "$R/zig-safe" )
  ( cd rust && CARGO_TARGET_DIR=$R/rust-target PATH=$HOME/.cargo/bin:$PATH \
      "$SLOT" build -- cargo build --offline --release )
  ( cd go && GOCACHE=$R/gocache GOPATH=$R/gopath GOTOOLCHAIN=local \
      "$SLOT" build -- go build -o "$R/go/eda-sch" ./cmd/eda-sch )
  ( cd mylang && XDG_CACHE_HOME=$R/mylang-xdg ZIG_GLOBAL_CACHE_DIR=$R/mylang-zig-global \
      ZIG_LOCAL_CACHE_DIR=$R/mylang-zig-local \
      "$SLOT" build -- "$MYLANG" build src/main.my -o "$R/mylang/eda-sch" --release --cache-dir="$R/mylang-cache" )
  load "before runtime"
  flock "$LOCKS/cpu10.lock" python3 "$HERE/runtime.py" --repo "$EDA" --rounds "${ROUNDS:-7}" --cpu 10 \
    --work "$EDA/.cache/runtime-out" --out "$HERE/results/runtime.json" \
    zig-fast="$R/zig-fast/bin/eda-sch" zig-safe="$R/zig-safe/bin/eda-sch" \
    rust="$R/rust-target/release/eda-sch" go="$R/go/eda-sch" mylang="$R/mylang/eda-sch" \
    2>&1 | tee "$HERE/logs/runtime.log"
  load "after runtime"
  ;;
supplement)
  load "before supplementary cold mylang-new"
  flock "$LOCKS/bench-compile.lock" "$SLOT" build -- \
    python3 harness/bench.py time mylang-new --only cold,clean --repeat 5 2>&1 | tee "$HERE/logs/time-mylang-new-cold-supplement.log"
  load "after supplementary cold mylang-new"
  # Breakdown (absolute cache paths: a relative XDG_CACHE_HOME is ignored and ~/.cache is used).
  B=$EDA/.cache/diag-abs
  run() { mkdir -p "$B/tmp" "$B/bin"; ( cd mylang && XDG_CACHE_HOME=$B/xdg ZIG_GLOBAL_CACHE_DIR=$B/zig-global \
      ZIG_LOCAL_CACHE_DIR=$B/zig-local TMPDIR=$B/tmp /usr/bin/time -f "$1 %e s %M KB" "$SLOT" build -- \
      "$MYLANG" build src/main.my -o "$B/bin/eda-sch" --cache-dir="$B/mylang" ) 2>&1 | tail -1; }
  for i in 1 2; do
    rm -rf "$B"; run all-empty
    rm -rf "$B/mylang" "$B/xdg"; run zig-caches-warm
    rm -rf "$B/mylang" "$B/zig-global" "$B/zig-local"; run runtime-warm
    rm -rf "$B/mylang"; run project-only
  done | tee "$HERE/logs/cold-breakdown.log"
  ;;
*) echo "usage: run.sh prep|time|runtime|supplement" >&2; exit 2 ;;
esac

#!/usr/bin/env bash
# EDA benchmark stage 1 (eda-sch) rerun on mylang `main` fc31e55bb, 2026-10-08: the new core
# with copy elimination and the whole test loop (items 1-5) merged. The protocol is
# experiments/bench-newcore-20261008/eda/run.sh's, with the compiler re-pinned.
#
#   run.sh prep      untimed: equiv (debug + release mylang-new) and mylang-new's tests
#   run.sh time      bench.py time --stage 1 --repeat 3 for zig, go, rust, mylang-new, back to back,
#                    each under flock bench-compile.lock and the build-slot wrapper (keeps CPUs 2,3,10,11 free)
#   run.sh runtime   release binaries of every port, then runtime.py under flock cpu10.lock, pinned to CPU 10
#
# EDA is the eda-bench worktree on branch claude/eda-bench-newcore (harness entries mylang-new and
# mylang-new-release pinned to $MYLANG's directory); every cache and TMPDIR stays under $EDA/.cache.
set -euo pipefail
EDA=${EDA:-/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore}
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
SLOT=$REPO/scripts/build-slot.sh
LOCKS=/run/user/1000/mylang-slots
MYLANG=$HOME/.cache/mylang/bench-main-352d9396/bin/mylang
export TMPDIR=$EDA/.cache/tmp
mkdir -p "$TMPDIR" "$HERE/logs"
cd "$EDA"

load() { echo "$(date -Is) $1 loadavg $(cut -d' ' -f1-3 /proc/loadavg)" | tee -a "$HERE/logs/load.log"; }

case ${1:-} in
prep)
  for l in mylang-new mylang-new-release; do
    "$SLOT" build -- python3 harness/bench.py equiv "$l" > "$HERE/logs/equiv-$l.log" 2>&1
    tail -1 "$HERE/logs/equiv-$l.log"
  done
  "$SLOT" build -- python3 harness/bench.py test mylang-new > "$HERE/logs/test-mylang-new.log" 2>&1
  tail -1 "$HERE/logs/test-mylang-new.log"
  ;;
time)
  mkdir -p "$HERE/results"
  touch "$HERE/logs/.time-start"
  for l in ${LANGS:-zig go rust mylang-new}; do
    load "before time $l"
    flock "$LOCKS/bench-compile.lock" "$SLOT" build -- \
      python3 harness/bench.py time "$l" --stage 1 --repeat "${REPEAT:-3}" 2>&1 | tee "$HERE/logs/time-$l.log"
    load "after time $l"
  done
  find harness/results -name 'time-stage1-*.json' -newer "$HERE/logs/.time-start" -exec cp {} "$HERE/results/" \;
  rm -f "$HERE/logs/.time-start"
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
  rm -f "$R/mylang/eda-sch"
  ( cd mylang && XDG_CACHE_HOME=$R/mylang-xdg ZIG_GLOBAL_CACHE_DIR=$R/mylang-zig-global \
      ZIG_LOCAL_CACHE_DIR=$R/mylang-zig-local \
      "$SLOT" build -- "$MYLANG" build src/main.my -o "$R/mylang/eda-sch" --release --cache-dir="$R/mylang-cache" )
  mkdir -p "$HERE/results"
  load "before runtime"
  flock "$LOCKS/cpu10.lock" python3 "$REPO/experiments/bench-newcore-20261008/eda/runtime.py" --repo "$EDA" \
    --rounds "${ROUNDS:-10}" --cpu 10 --work "$EDA/.cache/runtime-out" --out "$HERE/results/runtime.json" \
    zig-fast="$R/zig-fast/bin/eda-sch" zig-safe="$R/zig-safe/bin/eda-sch" \
    rust="$R/rust-target/release/eda-sch" go="$R/go/eda-sch" mylang="$R/mylang/eda-sch" \
    2>&1 | tee "$HERE/logs/runtime.log"
  load "after runtime"
  ;;
*) echo "usage: run.sh prep|time|runtime" >&2; exit 2 ;;
esac

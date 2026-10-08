#!/usr/bin/env bash
# Reproduce the 2026-10-08 new-core Lox benchmark attempt.
#
# Stage A (done 2026-10-08): copy the tree, switch the mylang profiles to the new CLI,
# build every port, run the correctness check, the smoke-size probe and the repros.
# The check did not finish: the new-core mylang binary is quadratic in the heap size
# (REPORT.md), so Stage B (runtime, compile ladder, unit tests) was not run.
# Stage B's commands are below, behind RUN_STAGE_B=1, for when the blocker is fixed.
set -euo pipefail

SRC=/home/epentland/ai/canopy/mylang-worktrees/codex-s4-lox-value-semantics/benchmarks/lox
TREE=/home/epentland/ai/canopy/mylang-worktrees/claude-bench-newcore
HERE=$TREE/experiments/bench-newcore-20261008/lox
export WORK=$TREE/.mylang-cache/bench/lox
export LOX_BENCH_MYLANG=$HOME/.cache/mylang/bench-newcore-5a6b501d/bin/mylang   # ReleaseFast, main 5a6b501d
OLD_CORE=$HOME/.cache/mylang/s4-wave0-20261006/mylang-s4-pin/bin/mylang          # S4 old-core pin a16a324e (diagnosis only)
export TMPDIR=$WORK/.tmp/lox-bench/tmp XDG_CACHE_HOME=$WORK/.tmp/xdg PYTHONDONTWRITEBYTECODE=1
export PATH=$HOME/.cargo/bin:$PATH
SLOT=$TREE/scripts/build-slot.sh
LOCKS=/run/user/1000/mylang-slots

# --- Stage A: setup -------------------------------------------------------------
if [ ! -d "$WORK" ]; then
  mkdir -p "$(dirname "$WORK")"
  cp -r "$SRC" "$WORK"
  rm -rf "$WORK/ports/mylang/.mylang-cache"
fi
mkdir -p "$WORK/.tmp/lox-bench/tmp"          # lox_bench.repo_root() finds .tmp/lox-bench under the tree
cp "$HERE/bench.json" "$WORK/ports/mylang/bench.json"
cp "$HERE/prime-mylang.json" "$WORK/harness/prime/mylang/prime.json"
cd "$WORK"

# Untimed builds of every profile (no lock; slot wrapper keeps them off CPUs 2,3,10,11).
for pp in mylang:release mylang:debug zig:release zig:release-safe zig:debug rust:release rust:debug go:release go:debug; do
  "$SLOT" build -- python3 harness/lox_bench.py build --port "${pp%%:*}" --profile "${pp#*:}"
done
C=$WORK/.tmp/lox-bench/cache

# Correctness: 13 scripts x (smoke both engines + gc-stress, tree tier, vm tier) = 78 runs per binary.
# On 2026-10-08 this did not finish: mylang tree binary_trees (N=10) ran >10 min (Zig: 0.16 s).
"$SLOT" build -- python3 harness/lox_bench.py check --tier smoke --tier tree --tier vm -j 6 \
  --binary mylang="$C/mylang-release/lox-release" --binary mylang-debug="$C/mylang-debug/lox-debug" \
  --binary zig="$C/zig-release/out-release/bin/lox" --binary zig-safe="$C/zig-release-safe/out-release-safe/bin/lox" \
  --binary rust="$C/rust-release/target/release/lox" --binary go="$C/go-release/bin/lox" || true

# Diagnosis: the port built by the S4 old-core pin, the smoke probe, the profile, the repros.
mkdir -p "$WORK/.tmp/oldcore"
(cd ports/mylang && "$SLOT" build -- "$OLD_CORE" build main.my --project -o "$WORK/.tmp/oldcore/lox-old" --cache-dir "$WORK/.tmp/oldcore/mylang")
"$SLOT" build -- python3 "$HERE/probe/probe.py" "$WORK" "$WORK/.tmp/probe/smoke.json" 600 \
  newcore="$C/mylang-release/lox-release" oldcore="$WORK/.tmp/oldcore/lox-old" \
  zig="$C/zig-release/out-release/bin/lox" rust="$C/rust-release/target/release/lox"
S=$WORK/.tmp/scripts; mkdir -p "$S"
for n in 4 5 6 8; do
  (echo "var N = $n;"; tail -n +2 bench/scripts/binary_trees.lox) > "$S/bt$n.lox"
  for b in "$C/mylang-release/lox-release" "$WORK/.tmp/oldcore/lox-old" "$C/zig-release/out-release/bin/lox"; do
    /usr/bin/time -f "$(basename "$b") N=$n %e s %M KiB" taskset -c 0,1 timeout 120 "$b" --engine=tree --stats "$S/bt$n.lox" >/dev/null || true
  done
done
R=$WORK/.tmp/repro; mkdir -p "$R"
for f in field_append param_append lox_shape; do
  mkdir -p "$R/$f"; cp "$HERE/repro/$f.my" "$R/$f/main.my"
  "$SLOT" build -- "$LOX_BENCH_MYLANG" build "$R/$f/main.my" --release -o "$R/$f/new" --cache-dir "$R/cache-new"
  "$SLOT" build -- "$OLD_CORE" build "$R/$f/main.my" --project -o "$R/$f/old" --cache-dir "$R/cache-old"
  for n in 10000 40000; do
    /usr/bin/time -f "$f new N=$n %e s" taskset -c 4 "$R/$f/new" $n
    /usr/bin/time -f "$f old N=$n %e s" taskset -c 4 "$R/$f/old" $n
  done
done

# --- Stage B: the measurement proper (not run on 2026-10-08) ---------------------
if [ "${RUN_STAGE_B:-0}" = 1 ]; then
  CPUS=0-1,4-9,12-19   # every CPU except the timing CPUs 2,3,10,11
  # Runtime: CPU 10 (its SMT sibling 11 is watched by the quiet gate), 5 rounds, held lock.
  flock "$LOCKS/cpu10.lock" python3 harness/measure.py runtime \
    --ports mylang,zig,rust,go --profiles release,zig:release-safe --rounds 5 --cpu 10
  # Compile ladder and unit tests: under the shared compile lock and a build slot.
  flock "$LOCKS/bench-compile.lock" "$SLOT" build -- python3 harness/measure.py compile \
    --ports mylang,zig,rust,go --profiles release,debug --rounds 3 --cpus "$CPUS"
  flock "$LOCKS/bench-compile.lock" "$SLOT" build -- python3 harness/measure.py tests \
    --ports mylang,zig,rust,go --rounds 3 --cpus "$CPUS"
  # Then: python3 "$HERE/summarize.py" results/<stamp>-runtime/runtime.json
fi

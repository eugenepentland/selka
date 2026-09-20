#!/usr/bin/env bash
# Reproduce the LLVM-arm qualification end to end, against one pinned compiler.
#
#   experiments/llvm-backend/qualify_all.sh [WORKDIR]
#
# Every stage writes its raw evidence under
# experiments/llvm-backend/evidence/qualification-20260920/ and records the
# compiler binary hash plus the `src/qbe.zig` hash at the start and the end of
# its own run, because more than one writer was editing the emitter while this
# qualification ran.  A stage whose compiler hash moved is void.
#
# Stages 1-5 are correctness and cost.  Stage 6 is the load-sensitive paired
# measurement and is run last, alone, on a pinned CPU.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="${1:-/tmp/llvm-qual-run}"
MYLANG="${MYLANG:-$REPO/zig-out/bin/mylang}"
ADAPTER="$REPO/experiments/llvm-backend/qbe_llvm.py"
DIR="$REPO/experiments/llvm-backend"
EVIDENCE="$REPO/experiments/llvm-backend/evidence/qualification-20260920"
JOBS="${JOBS:-10}"

mkdir -p "$WORK" "$EVIDENCE"
cd "$REPO"
echo "compiler  $(sha256sum "$MYLANG")"
echo "emitter   $(sha256sum src/qbe.zig)"

# 1. Build coverage: every .my entry under the language tree, both arms.
python3 -B "$DIR/qualify_sweep.py" --mylang "$MYLANG" --work "$WORK/sweep" --jobs "$JOBS" \
  --json "$EVIDENCE/build-sweep-fixed.json"

# 2. Byte-equality for the entries the as-found sweep could not build.
python3 -B "$DIR/qualify_affected.py" --mylang "$MYLANG" --work "$WORK/affected" --jobs 5 \
  --json "$EVIDENCE/affected-byte-equality.json"

# 3. Guest suites, both arms, separate caches, verdicts compared by name.
#    --inner-jobs 1: concurrent test children lose the driver's cache-staging race
#    and silently drop tests (see the report's limitations).
python3 -B "$DIR/qualify_equiv.py" --mylang "$MYLANG" --work "$WORK/equiv" --jobs 1 \
  --inner-jobs 1 --json "$EVIDENCE/equivalence-fixed.json"

# 4. Traps, ceilings, GC stress and exit status, both arms.
python3 -B "$DIR/qualify_traps.py" --mylang "$MYLANG" --work "$WORK/traps" --jobs 8 \
  --json "$EVIDENCE/trap-matrix-fixed.json"
python3 -B "$DIR/verify_traps.py" --work "$WORK/historical-traps" --jobs 8 \
  --json "$EVIDENCE/historical-trapdiff.json"

# 4b. The port's own differential checks, run through each arm in turn: these
#     hardcode ./zig-out/bin/mylang, so the arm is selected by MYLANG_QBE.
python3 -B experiments/sexpr-port/golden_compare.py > "$EVIDENCE/golden-compare-qbe.txt" 2>&1 || true
python3 -B experiments/sexpr-port/compare.py > "$EVIDENCE/compare-qbe.txt" 2>&1 || true
#    doctest writes its report to a file and runs one child at a time for the
#    QBE baseline, because of the same staging race.
"$MYLANG" doctest . --jobs 1 --report "$EVIDENCE/doctest-qbe-serial.json" \
  > "$EVIDENCE/doctest-qbe-serial.txt" 2>&1 || true
MYLANG_QBE="$ADAPTER" python3 -B experiments/sexpr-port/golden_compare.py \
  > "$EVIDENCE/golden-compare-llvm.txt" 2>&1 || true
MYLANG_QBE="$ADAPTER" python3 -B experiments/sexpr-port/compare.py \
  > "$EVIDENCE/compare-llvm.txt" 2>&1 || true

# 5. Cold-cache build cost and binary size, both arms.
python3 -B "$DIR/qualify_cost.py" --mylang "$MYLANG" --work "$WORK/cost" --rounds 3 \
  --json "$EVIDENCE/cost.json"

# 6. Paired wall-clock and counter measurement, one compiler, both arms.
"$MYLANG" build experiments/sexpr-port/main.my -o "$WORK/arm-qbe" \
  --mode=ReleaseFast --keep-symbols --cache-dir="$WORK/cache-arm-qbe"
"$MYLANG" build experiments/sexpr-port/main.my -o "$WORK/arm-llvm" \
  --mode=ReleaseFast --keep-symbols --cache-dir="$WORK/cache-arm-llvm" --qbe="$ADAPTER"
python3 -B "$DIR/measure.py" --work "$WORK/measure" --rounds 31 --skip-zig --cpu 6 \
  --arms qbe,llvm-o2 --binary "qbe=$WORK/arm-qbe" --binary "llvm-o2=$WORK/arm-llvm" \
  --json "$EVIDENCE/measure.json"

echo "done: $(sha256sum "$MYLANG")"
echo "done: $(sha256sum src/qbe.zig)"

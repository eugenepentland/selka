#!/bin/sh
# Runs the fuzz matrix (Lox port and synthetic, seeds 1-3, RC and --gc-runtime) through the
# shared-box build slots; up to three run at once. usage: run_matrix.sh COMPILER OUTDIR [STEPS]
set -u
COMPILER=$1; OUT=$2; STEPS=${3:-60}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
mkdir -p "$OUT"
for kind in lox synthetic; do
  for seed in 1 2 3; do
    for runtime in rc gc; do
      extra=""; [ "$runtime" = gc ] && extra="--gc-runtime"
      name="$kind-$seed-$runtime"
      "$ROOT/scripts/build-slot.sh" build python3 "$HERE/edit_fuzz.py" --compiler "$COMPILER" \
        --work "$OUT/work-$name" --project-kind "$kind" --seed "$seed" --steps "$STEPS" $extra \
        --json "$OUT/$name.json" > "$OUT/$name.out" 2>&1 &
    done
  done
done
wait

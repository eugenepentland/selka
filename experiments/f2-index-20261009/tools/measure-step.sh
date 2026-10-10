#!/usr/bin/env bash
# Lane F2: build and measure one compiler against the base on every corpus (CPU 8, perf counts).
# usage: measure-step.sh TAG COMPILER
#   parity: all 45 programs, .expected checked, base vs TAG with Zig ReleaseSafe as reference;
#   Lox (7 cells) and EDA (2 designs): counting on/off identical, EDA goldens, perf;
#   rows: all 46 at both sizes (rows_perf.py).
# Outputs land in .tmp/f2/<TAG>-*.{log,json} (copied into the evidence directory by hand).
set -u
root=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$root" || exit 2
tag=$1; compiler=$2
base=${F2_BASE:-$HOME/.cache/mylang/main-35df839b/bin/mylang}
bt=${F2_BASETAG:-base}   # the base arm's tag (lane binaries, parity directory)
tools=experiments/f2-index-20261009/tools
export TMPDIR=$root/.tmp/tmp
mkdir -p .tmp/f2 "$TMPDIR"
out=.tmp/f2/$tag
[ -d .tmp/f2/parity/$bt ] || scripts/build-slot.sh build python3 $tools/parity.py build --mylang "$base" --out .tmp/f2/parity/$bt > $out-parity-base-build.log 2>&1
scripts/build-slot.sh build python3 $tools/parity.py build --mylang "$compiler" --out .tmp/f2/parity/$tag > $out-parity-build.log 2>&1; tail -1 $out-parity-build.log
python3 $tools/parity.py measure --arm base=.tmp/f2/parity/$bt --arm $tag=.tmp/f2/parity/$tag --ref zig-safe --out $out-parity.json --rounds 5 > $out-parity.log 2>&1
python3 $tools/lane.py build --compiler "$compiler" --tag $tag > $out-lane-build.log 2>&1; cat $out-lane-build.log | grep '^build'
python3 $tools/lane.py check --tag $tag --out $out-check.json > $out-check.log 2>&1; tail -2 $out-check.log
[ -d .tmp/f2/lane/bin/$bt ] || python3 $tools/lane.py build --compiler "$base" --tag $bt > $out-lane-base-build.log 2>&1
python3 $tools/lane.py measure --tags $bt,$tag --out $out-lane.json --rounds 5 > $out-lane.log 2>&1
rm -rf .tmp/f2/rows-$tag; mkdir -p .tmp/f2/rows-$tag
scripts/build-slot.sh build python3 experiments/new-core-s4-20261006/integration/measure_all46.py --build-only --mylang "$base" --core "$compiler" --bin $root/.tmp/f2/rows-$tag > $out-rows-build.log 2>&1
echo "rows built: $(grep -c 'status=0' $out-rows-build.log) ok, $(grep 'status=' $out-rows-build.log | grep -vc 'status=0') failed"
python3 /home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/experiments/parity-confirm-20261009/tools/rows_perf.py --bin $root/.tmp/f2/rows-$tag --worktree $root --cpu 8 --json $out-rows.json > $out-rows.log 2>&1
tail -1 $out-rows.log
echo "== parity (instructions or cycles above 1.02 vs base)"
python3 - "$out-parity.json" "$tag" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); tag = sys.argv[2]
for name, row in d["programs"].items():
    m = row["median"]; i = m[tag]["instructions"] / m["base"]["instructions"]; c = m[tag]["cycles"] / m["base"]["cycles"]
    z = f" zig-safe {m[tag]['cycles'] / m['zig-safe']['cycles']:.3f}" if "zig-safe" in m else ""
    if i > 1.02 or c > 1.02 or z: print(f"  {name}: instr {i:.3f} cycles {c:.3f}{z}")
PY
echo "== lox/eda"; cat $out-lane.log

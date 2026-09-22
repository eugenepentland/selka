#!/usr/bin/env bash
# Build the whole-o3 (and optionally compact-o3) arena arm for one guest source tree.
#   probe.sh <name> <srcdir> [arms]
set -euo pipefail
cd /home/epentland/ai/canopy/mylang
NAME="$1"; SRC="$2"; ARMS="${3:-whole-o3}"
S=/tmp/claude-1000/-home-epentland-ai-canopy-mylang/6108061e-40b0-485a-852b-53c35cd1760e/scratchpad
ROOT="$PWD"; WORK="$S/probes/build-$NAME"
mkdir -p "$WORK"; rm -rf "$WORK/cache" "$WORK/maxperf"
START=$(date +%s.%N)
./zig-out/bin/mylang build "$SRC/main.my" -o "$WORK/llvm-o2.bin" \
  --mode=ReleaseFast --keep-symbols --cache-dir="$WORK/cache" \
  --qbe=experiments/llvm-backend/qbe_llvm.py > "$WORK/llvm-o2-build.log" 2>&1
./zig-out/bin/mylang emit-project-qbe "$SRC/main.my" \
  --drop-debug --drop-step-checks --drop-frame-checks > "$WORK/il-manifest.json" 2>>"$WORK/llvm-o2-build.log"
python3 - "$WORK" <<'PY'
import json, os, sys, glob, subprocess
work = sys.argv[1]
built = json.load(open(os.path.join(work, "llvm-o2.bin.qbe-manifest.json")))
emit = json.load(open(os.path.join(work, "il-manifest.json")))
by_symbol = {f["symbol"]: f for f in emit["functions"]}
functions = [dict(by_symbol[f["symbol"]], object=f["object"]) for f in built["functions"]]
json.dump({"version":"qbe-manifest-v1","abi":built["abi"],"entry":built["entry"],
           "functions":functions,"runtime_object":built["runtime_object"]},
          open(os.path.join(work,"manifest.json"),"w"))
sources = None
for root, _d, files in os.walk(os.path.join(work,"cache")):
    if "native_format.zig" in files and "qbe_runtime.c" in files:
        sources = root; break
assert sources
json.dump({"runtime_sources":sources}, open(os.path.join(work,"bench-inputs.json"),"w"))
PY
FORMATTER="$(python3 - "$WORK" "$ROOT" <<'PY'
import glob, json, os, subprocess, sys
work, root = sys.argv[1], sys.argv[2]
manifest = json.load(open(os.path.join(work, "manifest.json")))
def symbols(path, undefined=False):
    out = subprocess.run(["nm", "-u" if undefined else "--defined-only", path], capture_output=True, text=True).stdout
    return {l.split()[-1] for l in out.splitlines() if l.split()}
needed = set()
for entry in manifest["functions"]:
    needed |= {s for s in symbols(entry["object"], undefined=True) if s.startswith("myl_native_")}
candidates = []
for unit in glob.glob(os.path.join(root, "zig-out/lib/mylang-runtime/*.o")):
    defined = symbols(unit)
    if "myl_native_number_parse" not in defined: continue
    candidates.append((len(defined & needed), os.path.getmtime(unit), unit))
score, _, best = max(candidates)
print(best)
PY
)"
python3 experiments/llvm-backend/maxperf/build.py \
  --manifest "$WORK/manifest.json" --receipt "$WORK/manifest.json" \
  --formatter "$FORMATTER" \
  --runtime-sources "$(python3 -c "import json;print(json.load(open('$WORK/bench-inputs.json'))['runtime_sources'])")" \
  --work "$WORK/maxperf" --arms "$ARMS" > "$WORK/maxperf.log" 2>&1
echo "built $NAME [$ARMS] in $(echo "$(date +%s.%N) - $START" | bc) s"
ls "$WORK"/maxperf/*.bin

#!/usr/bin/env bash
# usage: kn_pstat.sh OUT.json ROUNDS NAME=BINARY... : interleaved perf stat on CPU 6 with zig-safe
set -e
W=/home/epentland/ai/canopy/mylang-worktrees/claude-vk-vp3
out=$1; rounds=$2; shift 2
python3 - "$out.arms" "$@" <<'PY'
import json, sys
arms=[]
for spec in sys.argv[2:]:
    name, path = spec.split("=", 1)
    prog = name.split(":")[0] if ":" in name else "knucleotide"
    arm = name.split(":")[-1]
    arms.append({"program": prog, "arm": arm, "argv": [path]})
json.dump(arms, open(sys.argv[1], "w"))
PY
python3 $W/experiments/parity-measure-20261008/tools/pstat.py "$out.arms" --out "$out" --rounds "$rounds" --cpu 6
python3 - "$out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for a in d["arms"]:
    m = a["median"]
    print(f'{a["program"]:14} {a["arm"]:12} status={set(a["status"])} instr={m["instructions"]/1e6:9.1f}M cycles={m["cycles"]/1e6:8.1f}M')
PY

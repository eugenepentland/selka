#!/usr/bin/env bash
# S5-X phase 2: the CPU-10 measurements, run on a quiet machine after phase 1.
# 1. All 46 rows: the final mylang against the archived old core (interleaved) and Zig.
# 2. Lox and EDA build/test times, three runs each, medians (ReleaseFast mylang).
# 3. The dev-loop table on the synthetic projects (48k and 192k lines, debug and release).
# 4. The check after a one-function edit at 96k lines.
# Usage: phase2.sh FINAL_MYLANG RELEASEFAST_MYLANG
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
final=$1
fast=$2
oracle=$HOME/.cache/mylang/oracles/old-core-d36658db
lock=/run/user/1000/mylang-slots/cpu10.lock
work=$root/.mylang-cache/s5/x2
mkdir -p "$work/tmp"
export TMPDIR=$work/tmp MYLANG_QBE=$oracle/qbe
cd "$root" || exit 2

echo "== 46 rows"
rows=$work/all46
"$root/scripts/build-slot.sh" build -- python3 experiments/new-core-s4-20261006/integration/measure_all46.py --build-only \
    --mylang "$oracle/mylang" --core "$final" --bin "$rows" > "$here/all46-01-build.log" 2>&1
echo "rows build exit=$?"
flock "$lock" python3 experiments/new-core-s4-20261006/integration/measure_all46.py \
    --mylang "$oracle/mylang" --core "$final" --bin "$rows" --json "$here/all46-01.json" > "$here/all46-01.log" 2>&1
echo "rows exit=$?"
python3 -c "
import json; d = json.load(open('$here/all46-01.json'))
print({k: d[k] for k in ('valid', 'all_within_old_limit', 'all_within_zig_limit', 'speed_gate_misses')})"

echo "== ports (warm runtime from the ReleaseFast binary, then 3 runs)"
warm=$work/warm-runtime
rm -rf "$warm"; mkdir -p "$warm/p"
printf 'def main(out: Stream) -> int:\n    out.print(2.5)\n    return 0\n' > "$warm/p/app.my"
XDG_CACHE_HOME=$warm/xdg "$fast" build "$warm/p/app.my" -o "$warm/p/app" --cache-dir "$warm/p/cache" > /dev/null 2>&1
for i in 1 2 3; do
    rm -rf "$work/ports-$i"
    flock "$lock" python3 "$here/measure_ports.py" --core "$fast" --area "$work/ports-$i" \
        --json "$here/ports-0$i.json" --runtime "$warm/xdg/mylang/core-runtime" > "$here/ports-0$i.log" 2>&1
    echo "ports run $i exit=$?"
done
python3 - "$here" <<'EOF'
import json, statistics, sys
here = sys.argv[1]
runs = [json.load(open(f"{here}/ports-0{i}.json")) for i in (1, 2, 3)]
base = runs[0]["baselines"]
rows = [("lox", "build", ["build"], base["lox"]["build"]),
        ("lox", "tests", ["tests-directory", "tests-driver"], [sum(x) for x in zip(base["lox"]["tests-directory"], base["lox"]["tests-driver"])]),
        ("eda", "build", ["build"], base["eda"]["build"]), ("eda", "test", ["test"], base["eda"]["test"])]
out = {}
for port, name, kinds, old in rows:
    for j, state in enumerate(("cold", "unchanged", "one-function-edit")):
        values = [sum(r[port][k][state] for k in kinds) for r in runs]
        median = statistics.median(values)
        out[f"{port} {name} {state}"] = {"old": old[j], "runs": [round(v, 4) for v in values], "median": round(median, 4), "ratio": round(median / old[j], 3)}
        print(f"{port:4} {name:6} {state:18} old {old[j]:9.4f} median {median:8.4f} ratio {median / old[j]:.3f}")
json.dump(out, open(f"{here}/ports-median.json", "w"), indent=1)
EOF

echo "== dev loop (synthetic projects)"
for spec in "1200 debug" "4800 debug" "1200 release" "4800 release"; do
    set -- $spec
    name="devloop-$2-$1"
    python3 "$here/measure_devloop.py" "$fast" "$work/$name" "$1" "$2" > "$here/$name.json" 2> "$here/$name.err"
    echo "$name exit=$?"
done

echo "== check after an edit, 96k lines"
flock "$lock" python3 "$here/measure_check.py" "$fast" "$work/check-96k" > "$here/check-96k.json" 2> "$here/check-96k.err"
echo "check exit=$?"
echo "phase 2 done"

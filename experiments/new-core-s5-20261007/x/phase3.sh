#!/usr/bin/env bash
# S5-X final run on the final source: qualification, frozen fuzz 9x200, the full gate,
# then on CPU 10 the 46 rows, three port runs and the 96k check (the dev-loop numbers of
# phase 2 stand: the changes since affect run time, not compile time).
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd); cd "$root" || exit 2
D=experiments/new-core-s5-20261007; X=$D/x; oracle=$HOME/.cache/mylang/oracles/old-core-d36658db
work=$root/.mylang-cache/s5/x3; mkdir -p "$work/tmp"; export TMPDIR=$work/tmp
lock=/run/user/1000/mylang-slots/cpu10.lock
scripts/build-slot.sh build -- zig build --summary none > "$work/prebuild.log" 2>&1; echo "prebuild=$?"
python3 $D/tools/qualify_merge.py --evidence $X/qualify-final-03 --shards 64 --compiler zig-out/bin/mylang --install install > "$work/qualify.out" 2>&1; echo "qualify=$?"
grep -E '"qualified"' $X/qualify-final-03/summary.json; grep -E "^  (debug|release) " $X/qualify-final-03/full-conformance.log
cp zig-out/bin/mylang "$work/mylang-final"
python3 $D/tools/fuzz_matrix.py --references $D/references/fuzz-v1.json.gz --new "$work/mylang-final" --cases 200 --evidence "$root/$X/fuzz200-final" --jobs 3 > "$work/fuzz.out" 2>&1; echo "fuzz200=$?"; grep -E "PASS|STOP" "$work/fuzz.out" | tr '\n' ' '; echo
/usr/bin/time -f "gate wall %e s" scripts/build-slot.sh gate -- zig build test --summary all > "$work/gate.log" 2>&1; echo "gate=$?"; tail -1 "$work/gate.log"; grep -E "^Build Summary" "$work/gate.log"
scripts/build-slot.sh build -- zig build fmt-check --summary none > /dev/null 2>&1; echo "fmt=$?"
scripts/build-slot.sh build -- zig build -Doptimize=ReleaseFast --prefix "$work/rf" --summary none > "$work/rf.log" 2>&1; echo "rf=$?"
export MYLANG_QBE=$oracle/qbe
scripts/build-slot.sh build -- python3 experiments/new-core-s4-20261006/integration/measure_all46.py --build-only --mylang "$oracle/mylang" --core "$work/mylang-final" --bin "$work/all46" > "$X/all46-03-build.log" 2>&1; echo "rows build=$?"
flock "$lock" python3 experiments/new-core-s4-20261006/integration/measure_all46.py --mylang "$oracle/mylang" --core "$work/mylang-final" --bin "$work/all46" --json "$X/all46-03.json" > "$X/all46-03.log" 2>&1; echo "rows=$?"
python3 -c "import json; d=json.load(open('$X/all46-03.json')); print({k: d[k] for k in ('valid','all_within_old_limit','all_within_zig_limit','speed_gate_misses')})"
warm=$work/warm-runtime; rm -rf "$warm"; mkdir -p "$warm/p"; printf 'def main(out: Stream) -> int:\n    out.print(2.5)\n    return 0\n' > "$warm/p/app.my"
XDG_CACHE_HOME=$warm/xdg "$work/rf/bin/mylang" build "$warm/p/app.my" -o "$warm/p/app" --cache-dir "$warm/p/cache" > /dev/null 2>&1
for i in 1 2 3; do rm -rf "$work/ports-$i"; flock "$lock" python3 "$X/measure_ports.py" --core "$work/rf/bin/mylang" --area "$work/ports-$i" --json "$X/ports-final-$i.json" --runtime "$warm/xdg/mylang/core-runtime" > "$X/ports-final-$i.log" 2>&1; echo "ports $i=$?"; done
python3 - "$X" <<'PY'
import json, statistics, sys
X = sys.argv[1]; runs = [json.load(open(f"{X}/ports-final-{i}.json")) for i in (1, 2, 3)]; base = runs[0]["baselines"]
rows = [("lox", "build", ["build"], base["lox"]["build"]), ("lox", "tests", ["tests-directory", "tests-driver"], [sum(x) for x in zip(base["lox"]["tests-directory"], base["lox"]["tests-driver"])]), ("eda", "build", ["build"], base["eda"]["build"]), ("eda", "test", ["test"], base["eda"]["test"])]
out = {}
for port, name, kinds, old in rows:
    for j, state in enumerate(("cold", "unchanged", "one-function-edit")):
        values = [sum(r[port][k][state] for k in kinds) for r in runs]; median = statistics.median(values)
        out[f"{port} {name} {state}"] = {"old": old[j], "runs": [round(v, 4) for v in values], "median": round(median, 4), "ratio": round(median / old[j], 3)}
        print(f"{port:4} {name:6} {state:18} old {old[j]:9.4f} median {median:8.4f} ratio {median / old[j]:.3f}")
json.dump(out, open(f"{X}/ports-final-median.json", "w"), indent=1)
PY
flock "$lock" python3 "$X/measure_check.py" "$work/rf/bin/mylang" "$work/check-96k" > "$X/check-96k-final.json" 2> "$X/check-96k-final.err"; echo "check=$?"
python3 -c "import json; d=json.load(open('$X/check-96k-final.json')); print('check 96k edit median', d['edit_median_s'])"
echo "phase 3 done"

#!/usr/bin/env bash
# cost-check.sh [--pairs N] [--ignore-busy] BASE_COMPILER NEW_COMPILER [KIT] : the cost of a warm check of the port, base
# against new, back to back, N pairs (default 3): user-mode instructions (perf stat --no-scale, pinned to the P cores) and CPU
# seconds. Each pair appends a new function to src/main.selka of a fresh copy of the old-prepared port, then times
# `check src --warnings` (SELKA_ENGINE_VERIFY=0, stores of its own). One summary line: the median instruction ratio and
# whether it is within 1.02. Refuses to start while a gate or a compiler build is running (--ignore-busy for a dry run: its
# numbers are not evidence). Both compilers should be Debug builds of the same kind (an optimised pin only times the compiler
# itself). For an exclusive window run it inside `scripts/build-slot.sh timing scripts/lane/cost-check.sh ...`.
# COST_CPUS names the cores (default 0-11, the P cores of this machine). Exit 0 when within 1.02, 1 when not, 3 when refused.
set -u
. "$(dirname "$0")/lib.sh"
pairs=3; ignore=0; args=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    --pairs) pairs=$2; shift 2;;
    --ignore-busy) ignore=1; shift;;
    *) args+=("$1"); shift;;
  esac
done
[ ${#args[@]} -ge 2 ] || die "usage: cost-check.sh [--pairs N] [--ignore-busy] BASE_COMPILER NEW_COMPILER [KIT]"
base=$(realpath "${args[0]}"); new=$(realpath "${args[1]}"); compiler_check "$base"; compiler_check "$new"
KIT=$(resolve_kit "${args[2]:-}")
cpus=${COST_CPUS:-0-11}
busy=$(busy_machine)
if [ -n "$busy" ] && [ $ignore = 0 ]; then
  echo "cost-check: not starting: a gate or a compiler build is running on the machine, which would blur the count:"
  echo "$busy" | head -4 | sed 's/^/  /'
  echo "  wait for it, or run inside scripts/build-slot.sh timing (an exclusive window); --ignore-busy only for a dry run"
  exit 3
fi
command -v perf > /dev/null || die "perf is not installed"
W=$KIT/cost; rm -rf "$W"; mkdir -p "$W"
tag=$(date +%H%M%S)
measure() {  # measure SIDE COMPILER LABEL [APPEND_N] : one check of the side's copy of the port; prints "instr user sys wall"
  local side=$1 c=$2 label=$3 n=${4:-} d=$W/$1
  if [ -n "$n" ]; then printf '\n\nfunc kit_cost_%s_%s() -> int:\n    return %s\n' "$tag" "$n" "$n" >> "$d/port/src/main.selka"; fi
  ( cd "$d/port" || exit 2
    # shellcheck disable=SC2046
    "$LANE_DIR/with-stores.sh" "$d/stores" env $(compiler_env "$c") SELKA_ENGINE_VERIFY=0 \
      taskset -c "$cpus" perf stat --no-scale -e cpu_core/instructions/u -o "$d/perf.txt" -- \
      /usr/bin/time -f '%U %S %e' -o "$d/time.txt" prlimit --as=17179869184 "$c" check src --warnings > "$d/$label.out" 2>&1
    echo $? > "$d/$label.rc" )
  local ins; ins=$(grep -a instructions "$d/perf.txt" | awk '{gsub(",","",$1); print $1}')
  echo "$label $ins $(tail -1 "$d/time.txt")" >> "$d/results.txt"
}
for side in base new; do
  mkdir -p "$W/$side"; cp -a "$KIT/proj/netlisp-selka-redo" "$W/$side/port"; rm -rf "$W/$side/port/.selka-cache"
  : > "$W/$side/results.txt"
done
t0=$SECONDS
measure base "$base" cold; measure new "$new" cold          # a cold check each fills the work directory and the stores
for r in $(seq 1 "$pairs"); do measure base "$base" "warm$r" "$r"; measure new "$new" "warm$r" "$r"; done
python3 - "$W" "$pairs" "$(basename "$KIT")" "$(elapsed "$t0")" <<'EOF'
import statistics, sys
from pathlib import Path
W, pairs, kit, took = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
def load(side):
    r = {}
    for line in open(f"{W}/{side}/results.txt"):
        label, ins, u, s, wall = line.split()
        r[label] = (int(ins) if ins.isdigit() else 0, float(u) + float(s))
    return r
b, n = load("base"), load("new")
rows, ratios, cpu = [], [], []
for i in range(1, pairs + 1):
    bi, bc = b[f"warm{i}"]; ni, nc = n[f"warm{i}"]
    ratio = ni / bi if bi else float("nan")
    ratios.append(ratio); cpu.append(nc / bc if bc else float("nan"))
    rows.append(f"  pair {i}: {bi/1e9:.3f} G vs {ni/1e9:.3f} G instructions, ratio {ratio:.3f}; CPU {bc:.2f} s vs {nc:.2f} s")
print(f"cost-check: warm check of the port (kit {kit}), base against new, {pairs} pairs, {took}")
odd = [f"{side}/{r.name}" for side in ("base", "new") for r in Path(f"{W}/{side}").glob("*.rc") if r.read_text().strip() != "0"]
if odd:
    print("  WARNING: a check ended with a status other than 0 (" + ", ".join(sorted(odd)[:4]) + "): the counts are not comparable")
print("\n".join(rows))
med = statistics.median(ratios)
ok = med == med and med <= 1.02
print(f"median instruction ratio {med:.3f} (CPU seconds median ratio {statistics.median(cpu):.3f}): {'WITHIN' if ok else 'OVER'} 1.02; details {W}/")
sys.exit(0 if ok else 1)
EOF

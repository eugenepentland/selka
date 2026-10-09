#!/usr/bin/env bash
# build-slot.sh — run one build or gate command without overloading a shared machine.
#
# usage: scripts/build-slot.sh KIND [--] CMD...
#        scripts/build-slot.sh status
#
# KIND is `build` (any `zig build` compile or install, a focused `test-units`/
# `test-cli`, `selka test <dir>`, a guest benchmark build) or `gate` (a full gate
# step: `zig build test`, `test-qbe`, `test-qbe-build`, `test-schematic`,
# `test-byte-io`). A job is admitted only when both hold:
#   * a slot of its kind is free (flock on a per-slot lock file), and
#   * MemAvailable is at least the kind's threshold.
# Otherwise it waits, polling, and reports how long it waited. An admitted job
# runs under `taskset` with the reserved timing CPUs removed from its affinity,
# so benchmarks pinned to those CPUs are not disturbed by builds.
#
# Environment (defaults measured on the i7-12700H / 30 GB development box,
# docs/tooling/many-agents.md):
#   SELKA_BUILD_SLOTS=3          concurrent `build` jobs
#   SELKA_GATE_SLOTS=1           concurrent `gate` jobs
#   SELKA_BUILD_MEM=4G           MemAvailable needed to admit a build
#   SELKA_GATE_MEM=6G            MemAvailable needed to admit a gate
#   SELKA_TIMING_CPUS=2,3,10,11  CPUs kept free of admitted jobs ("" keeps none)
#   SELKA_SLOT_POLL=5            seconds between admission attempts
#   SELKA_SLOT_SETTLE=5          seconds an admitted job delays the next admission,
#                                 so its memory shows up in MemAvailable first
#   SELKA_SLOT_DIR               lock directory (default $XDG_RUNTIME_DIR/selka-slots,
#                                 else ~/.cache/selka/slots)
# Memory sizes take a K/M/G suffix or plain bytes.
#
# The wrapper does not cap memory itself; combine it with a cgroup cap when you
# want one, e.g. `scripts/build-slot.sh gate systemd-run --user --scope -p MemoryMax=16G zig build test`.
set -u

die() { echo "build-slot: $*" >&2; exit 2; }

bytes() {
  local text=$1 number unit
  number=${text%[KkMmGg]}
  unit=${text#"$number"}
  [[ $number =~ ^[0-9]+$ ]] || die "not a size: '$text' (use bytes or a K/M/G suffix)"
  case $unit in
    "") echo "$number" ;;
    K|k) echo $((number << 10)) ;;
    M|m) echo $((number << 20)) ;;
    G|g) echo $((number << 30)) ;;
  esac
}

available() { awk '$1 == "MemAvailable:" { print $2 * 1024; exit }' /proc/meminfo; }

human() { awk -v b="$1" 'BEGIN { printf "%.1f GiB", b / 1073741824 }'; }

slot_dir() {
  if [ -n "${SELKA_SLOT_DIR:-}" ]; then echo "$SELKA_SLOT_DIR"
  elif [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "${XDG_RUNTIME_DIR}" ]; then echo "$XDG_RUNTIME_DIR/selka-slots"
  else echo "$HOME/.cache/selka/slots"; fi
}

# The CPUs this process may use, minus the reserved timing CPUs, as a taskset list.
allowed_cpus() {
  local reserved=${SELKA_TIMING_CPUS-2,3,10,11} list cpu keep=() skipped usable
  list=$(awk '/^Cpus_allowed_list:/ { print $2 }' /proc/self/status)
  skipped=$(expand "$reserved") || exit 2
  usable=$(expand "$list") || exit 2
  declare -A skip=()
  for cpu in $skipped; do skip[$cpu]=1; done
  for cpu in $usable; do [ -z "${skip[$cpu]:-}" ] && keep+=("$cpu"); done
  [ ${#keep[@]} -gt 0 ] || die "SELKA_TIMING_CPUS=$reserved leaves no CPU for builds"
  local IFS=,; echo "${keep[*]}"
}

# Expand a CPU list such as 0-3,8,10-11 into one number per line.
expand() {
  local part low high
  local IFS=,
  for part in $1; do
    [ -n "$part" ] || continue
    low=${part%-*}; high=${part#*-}
    [[ $low =~ ^[0-9]+$ && $high =~ ^[0-9]+$ ]] || die "not a CPU list: '$1'"
    seq "$low" "$high"
  done
}

status() {
  local dir kind n i
  dir=$(slot_dir)
  echo "slot dir: $dir"
  echo "MemAvailable: $(human "$(available)")"
  echo "timing CPUs kept free: ${SELKA_TIMING_CPUS-2,3,10,11}; builds run on: $(allowed_cpus)"
  for kind in build gate; do
    if [ $kind = build ]; then n=${SELKA_BUILD_SLOTS:-3}; else n=${SELKA_GATE_SLOTS:-1}; fi
    for i in $(seq 1 "$n"); do
      if [ -e "$dir/$kind$i.lock" ] && ! flock -n "$dir/$kind$i.lock" true; then
        echo "$kind$i: busy"
      else
        echo "$kind$i: free"
      fi
    done
  done
}

[ $# -ge 1 ] || die "usage: build-slot.sh build|gate [--] CMD...  |  build-slot.sh status"
kind=$1; shift
case $kind in
  status) status; exit 0 ;;
  build) slots=${SELKA_BUILD_SLOTS:-3}; need=$(bytes "${SELKA_BUILD_MEM:-4G}") || exit 2 ;;
  gate) slots=${SELKA_GATE_SLOTS:-1}; need=$(bytes "${SELKA_GATE_MEM:-6G}") || exit 2 ;;
  *) die "kind must be build, gate or status, not '$kind'" ;;
esac
[ "${1:-}" = "--" ] && shift
[ $# -ge 1 ] || die "no command given"
[[ $slots =~ ^[1-9][0-9]*$ ]] || die "slot count must be a positive integer, not '$slots'"
poll=${SELKA_SLOT_POLL:-5}
[[ $poll =~ ^[1-9][0-9]*$ ]] || die "SELKA_SLOT_POLL must be a positive integer"
cpus=$(allowed_cpus) || exit 2
dir=$(slot_dir)
mkdir -p "$dir" || die "cannot create $dir"

settle=${SELKA_SLOT_SETTLE:-5}
[[ $settle =~ ^[0-9]+$ ]] || die "SELKA_SLOT_SETTLE must be a non-negative integer"

waited=0
reason=""
started=$(date +%s)
while :; do
  for i in $(seq 1 "$slots"); do
    exec 9>"$dir/$kind$i.lock"
    if flock -n 9; then
      # Admissions are serialized, and each admitted job keeps the admission
      # lock for SELKA_SLOT_SETTLE seconds, so the next job's memory check sees
      # this one's footprint instead of the idle moment before it grew.
      exec 8>"$dir/admit.lock"
      flock 8
      free=$(available)
      if [ "$free" -ge "$need" ]; then
        if [ $waited -gt 0 ]; then
          echo "build-slot: $kind slot $i after ${waited}s ($reason)" >&2
        fi
        if [ "$settle" -gt 0 ]; then sleep "$settle" 9>&- & fi
        exec 8>&-
        # Hold the slot lock (fd 9, inherited) for the job's lifetime; exec keeps
        # the job's exit status and signals exactly as if it ran directly.
        exec taskset -c "$cpus" "$@"
      fi
      exec 8>&-
      reason="waiting for memory: $(human "$free") available, $kind needs $(human "$need")"
      exec 9>&-
      break
    fi
    exec 9>&-
    reason="all $slots $kind slot(s) busy"
  done
  if [ $waited -eq 0 ] || [ $((waited % 60)) -lt "$poll" ]; then
    echo "build-slot: $reason; waiting (${waited}s so far)" >&2
  fi
  sleep "$poll"
  waited=$(( $(date +%s) - started ))
done

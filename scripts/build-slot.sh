#!/usr/bin/env bash
# build-slot.sh — admit parallel work or an exclusive measurement window.
#
# usage: scripts/build-slot.sh KIND [--] CMD...
#        scripts/build-slot.sh status
#
# KIND is `build` (any `zig build` compile or install, a focused `test-units`/
# `test-cli`, `mylang test <dir>`, a guest benchmark build) or `gate` (a full gate
# step: `zig build test`), or `timing` (runtime/compiler measurements).
# A build or gate is admitted only when all hold:
#   * a slot of its kind is free (flock on a per-slot lock file), and
#   * MemAvailable is at least the kind's threshold, and
#   * no timing request is queued or running.
# Waiters receive FIFO tickets per kind; later tickets cannot overtake a live
# earlier waiter, even when it polls less often. Dead/cancelled tickets are reaped.
# Otherwise it waits, polling, and reports its position and how long it waited.
# Timing requests stop new admissions, drain active builds/gates, and run one at
# a time. They hold admit.lock through measurement, also excluding older wrappers
# that use that lock. Unwrapped work is outside this cooperative protocol.
# Ordinary jobs use all allowed CPUs unless MYLANG_TIMING_CPUS is explicitly set.
#
# Environment (defaults measured on the i7-12700H / 30 GB development box,
# docs/tooling/many-agents.md):
#   MYLANG_BUILD_SLOTS=3          concurrent `build` jobs
#   MYLANG_GATE_SLOTS=1           concurrent `gate` jobs
#   MYLANG_BUILD_MEM=4G           MemAvailable needed to admit a build
#   MYLANG_GATE_MEM=6G            MemAvailable needed to admit a gate
#   MYLANG_TIMING_MEM=4G          MemAvailable needed to start a measurement
#   MYLANG_TIMING_CPUS=           optional CPUs excluded from builds/gates
#                                 (timing inherits the caller's affinity)
#   MYLANG_SLOT_POLL=5            seconds between admission attempts
#   MYLANG_SLOT_SETTLE=5          seconds an admitted job delays the next admission,
#                                 so its memory shows up in MemAvailable first
#   MYLANG_SLOT_DIR               lock directory (default $XDG_RUNTIME_DIR/mylang-slots,
#                                 else ~/.cache/mylang/slots)
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

# PID plus /proc start time distinguishes a waiter from a reused PID. The boot
# identity also covers persistent slot directories surviving a reboot.
process_start() {
  local stat rest
  local -a fields
  { IFS= read -r stat <"/proc/$1/stat"; } 2>/dev/null || return 1
  rest=${stat##*) }
  read -r -a fields <<<"$rest"
  [ ${#fields[@]} -ge 20 ] || return 1
  [[ ${fields[0]} != Z && ${fields[0]} != X ]] || return 1
  proc_start=${fields[19]}
}

# Caller holds queue.lock. Glob order is numeric because tickets are padded.
reap_queue() {
  local entry pid birth boot enqueued LC_COLLATE=C
  for entry in "$queue_dir"/[0-9]*.wait; do
    [ -f "$entry" ] || continue
    if ! read -r pid birth boot enqueued <"$entry" ||
       [[ ! $pid =~ ^[1-9][0-9]*$ || ! $birth =~ ^[0-9]+$ ||
          ! $enqueued =~ ^[0-9]+$ || $boot != "$boot_id" ]] ||
       ! process_start "$pid" || [ "$proc_start" != "$birth" ]; then
      rm -f -- "$entry" || die "cannot remove stale FIFO ticket"
    fi
  done
}

queue_lock() {
  exec 7>"$queue_dir/queue.lock" || die "cannot open FIFO queue lock"
  flock 7 || die "cannot lock FIFO queue"
}

cleanup_ticket() {
  [ -z "${ticket:-}" ] || rm -f -- "$ticket"
  rm -f -- "$queue_dir/sequence.tmp.$$"
}

enqueue() {
  local last=0
  mkdir -p "$queue_dir" || die "cannot create FIFO queue"
  trap cleanup_ticket EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  queue_lock
  reap_queue
  if [ -e "$queue_dir/sequence" ]; then
    read -r last <"$queue_dir/sequence" || die "cannot read FIFO sequence"
    [[ $last =~ ^[0-9]{1,18}$ ]] || die "invalid FIFO sequence"
  fi
  ticket_number=$((10#$last + 1))
  printf '%s\n' "$ticket_number" >"$queue_dir/sequence.tmp.$$" &&
    mv -f -- "$queue_dir/sequence.tmp.$$" "$queue_dir/sequence" || die "cannot save FIFO sequence"
  printf -v ticket '%s/%020d.wait' "$queue_dir" "$ticket_number"
  process_start "$$" || die "cannot identify waiter process"
  printf '%s %s %s %s\n' "$$" "$proc_start" "$boot_id" "$started" >"$ticket" || die "cannot create FIFO ticket"
  exec 7>&-
}

queue_position() {
  local entry LC_COLLATE=C
  position=0
  for entry in "$queue_dir"/[0-9]*.wait; do
    [ -f "$entry" ] || continue
    position=$((position + 1))
    [ "$entry" != "$ticket" ] || return 0
  done
  die "FIFO ticket disappeared"
}

queue_status() {
  local queue_dir=$1 entry pid birth boot enqueued position=0 now LC_COLLATE=C
  [ -d "$queue_dir" ] || return 0
  queue_lock
  reap_queue
  now=$(date +%s)
  for entry in "$queue_dir"/[0-9]*.wait; do
    [ -f "$entry" ] || continue
    read -r pid birth boot enqueued <"$entry" || continue
    position=$((position + 1))
    echo "$kind queue $position: pid $pid, waiting $((now - enqueued))s"
  done
  exec 7>&-
}

slot_dir() {
  if [ -n "${MYLANG_SLOT_DIR:-}" ]; then echo "$MYLANG_SLOT_DIR"
  elif [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "${XDG_RUNTIME_DIR}" ]; then echo "$XDG_RUNTIME_DIR/mylang-slots"
  else echo "$HOME/.cache/mylang/slots"; fi
}

# The CPUs this process may use, minus the reserved timing CPUs, as a taskset list.
allowed_cpus() {
  local reserved=${MYLANG_TIMING_CPUS-} list cpu keep=() skipped usable
  list=$(awk '/^Cpus_allowed_list:/ { print $2 }' /proc/self/status)
  skipped=$(expand "$reserved") || exit 2
  usable=$(expand "$list") || exit 2
  declare -A skip=()
  for cpu in $skipped; do skip[$cpu]=1; done
  for cpu in $usable; do [ -z "${skip[$cpu]:-}" ] && keep+=("$cpu"); done
  [ ${#keep[@]} -gt 0 ] || die "MYLANG_TIMING_CPUS=$reserved leaves no CPU for builds"
  local IFS=,; echo "${keep[*]}"
}

# Expand a CPU list such as 0-3,8,10-11 into one number per line.
expand() {
  local part low high
  local IFS=,
  for part in $1; do
    [ -n "$part" ] || continue
    low=${part%-*}; high=${part#*-}
    [[ $low =~ ^[0-9]+$ && $high =~ ^[0-9]+$ ]] && [ "$low" -le "$high" ] || die "not a CPU list: '$1'"
    seq "$low" "$high"
  done
}

status() {
  local dir kind n i
  dir=$(slot_dir)
  echo "slot dir: $dir"
  echo "MemAvailable: $(human "$(available)")"
  echo "optional reserved CPUs: ${MYLANG_TIMING_CPUS:-none}; builds run on: $(allowed_cpus)"
  echo "timing policy: queued measurements stop admissions and drain active work"
  for kind in build gate timing; do
    case $kind in
      build) n=${MYLANG_BUILD_SLOTS:-3} ;;
      gate) n=${MYLANG_GATE_SLOTS:-1} ;;
      timing) n=1 ;;
    esac
    for i in $(seq 1 "$n"); do
      if [ -e "$dir/$kind$i.lock" ] && ! flock -n "$dir/$kind$i.lock" true; then
        echo "$kind$i: busy"
      else
        echo "$kind$i: free"
      fi
    done
    queue_status "$dir/queue-$kind"
  done
}

# Caller holds admit.lock and its own queue lock (fd 7). Timing's queue needs
# a separate descriptor; timing never waits on admit.lock while holding its queue.
timing_pending() {
  local queue_dir="$dir/queue-timing" entry pending=1
  [ -d "$queue_dir" ] || return 1
  exec 6>"$queue_dir/queue.lock" || die "cannot open timing queue lock"
  flock 6 || die "cannot lock timing queue"
  reap_queue
  for entry in "$queue_dir"/[0-9]*.wait; do
    if [ -f "$entry" ]; then pending=0; break; fi
  done
  exec 6>&-
  return "$pending"
}

# Holding admit.lock prevents every cooperating wrapper from starting work.
# Inspect existing slot files, including slots above this caller's configured
# count: another worktree may have admitted more jobs before timing was requested.
work_drained() {
  local lock
  for lock in "$dir"/build[0-9]*.lock "$dir"/gate[0-9]*.lock; do
    [ -e "$lock" ] || continue
    if ! flock -n "$lock" true; then
      reason="draining active work (${lock##*/})"
      return 1
    fi
  done
}

run_job() {
  echo "build-slot: $kind slot $i, FIFO ticket $ticket_number after ${waited}s" >&2
  rm -f -- "$ticket" || die "cannot retire FIFO ticket"
  ticket=""
  exec 7>&-
  export MYLANG_ADMISSION_DIR="$dir" MYLANG_ADMISSION_KIND="$kind"
  # Timing holds fd 8 for its entire lifetime; ordinary jobs keep only fd 9.
  if [ "$kind" != timing ]; then
    if [ "$settle" -gt 0 ]; then
      # The accounting timer owns only admission fd 8. Detach it before
      # exec so cancellation of the worker cannot release the delay or
      # inherit a worker pipe/lease/handshake descriptor into the timer.
      command -v setsid >/dev/null || die "setsid is required for the admission timer"
      (
        for settle_path in /proc/$BASHPID/fd/*; do
          settle_fd=${settle_path##*/}
          if [[ $settle_fd =~ ^[0-9]+$ ]] && [ "$settle_fd" -gt 2 ] && [ "$settle_fd" -ne 8 ]; then
            eval "exec ${settle_fd}>&-"
          fi
        done
        exec setsid sleep "$settle"
      ) </dev/null >/dev/null 2>&1 &
      settle_pid=$!
      # setsid has no fork here: its caller is not a process-group leader.
      # Wait until detachment is observable before exposing the worker.
      settle_detached=false
      settle_deadline=$((SECONDS + 5))
      while IFS= read -r settle_stat 2>/dev/null <"/proc/$settle_pid/stat"; do
        settle_rest=${settle_stat##*) }
        read -r -a settle_fields <<<"$settle_rest"
        [ "${settle_fields[0]}" = Z ] && break
        if [ "${settle_fields[3]}" = "$settle_pid" ]; then
          settle_detached=true
          break
        fi
        if [ "$SECONDS" -ge "$settle_deadline" ]; then
          kill -KILL "$settle_pid" 2>/dev/null || true
          wait "$settle_pid" 2>/dev/null || true
          die "admission timer did not detach"
        fi
        sleep .001
      done
      if [ "$settle_detached" = false ]; then
        wait "$settle_pid" || die "admission timer failed before detaching"
      fi
    fi
    exec 8>&-
  fi
  exec taskset -c "$cpus" "$@"
}

[ -r /proc/sys/kernel/random/boot_id ] || die "Linux /proc is required"
read -r boot_id </proc/sys/kernel/random/boot_id
[ $# -ge 1 ] || die "usage: build-slot.sh build|gate|timing [--] CMD...  |  build-slot.sh status"
kind=$1; shift
case $kind in
  status) status; exit 0 ;;
  build) slots=${MYLANG_BUILD_SLOTS:-3}; need=$(bytes "${MYLANG_BUILD_MEM:-4G}") || exit 2 ;;
  gate) slots=${MYLANG_GATE_SLOTS:-1}; need=$(bytes "${MYLANG_GATE_MEM:-6G}") || exit 2 ;;
  timing) slots=1; need=$(bytes "${MYLANG_TIMING_MEM:-4G}") || exit 2 ;;
  *) die "kind must be build, gate, timing or status, not '$kind'" ;;
esac
[ "${1:-}" = "--" ] && shift
[ $# -ge 1 ] || die "no command given"
[[ $slots =~ ^[1-9][0-9]*$ ]] || die "slot count must be a positive integer, not '$slots'"
poll=${MYLANG_SLOT_POLL:-5}
[[ $poll =~ ^[1-9][0-9]*$ ]] || die "MYLANG_SLOT_POLL must be a positive integer"
if [ "$kind" = timing ]; then
  cpus=$(awk '/^Cpus_allowed_list:/ { print $2 }' /proc/self/status)
else
  cpus=$(allowed_cpus) || exit 2
fi
dir=$(slot_dir)
mkdir -p "$dir" || die "cannot create $dir"
dir=$(cd "$dir" && pwd -P) || die "cannot resolve slot directory"
[ "${MYLANG_ADMISSION_DIR:-}" != "$dir" ] || die "nested admission inside ${MYLANG_ADMISSION_KIND:-unknown} would deadlock; run the coordinator directly, and prepare builds before requesting timing"

settle=${MYLANG_SLOT_SETTLE:-5}
[[ $settle =~ ^[0-9]+$ ]] || die "MYLANG_SLOT_SETTLE must be a non-negative integer"

waited=0
reason=""
started=$(date +%s)
queue_dir="$dir/queue-$kind"
ticket=""
draining=0
enqueue
while :; do
  # Python phase holders supply a parent identity while waiting. A killed
  # coordinator cannot leave its still-live wrapper blocking the timing queue.
  if [ -n "${MYLANG_ADMISSION_PARENT_PID:-}" ]; then
    if ! process_start "$MYLANG_ADMISSION_PARENT_PID" ||
       [ "$proc_start" != "${MYLANG_ADMISSION_PARENT_START:-}" ]; then
      exit 143
    fi
  fi
  queue_lock
  reap_queue
  queue_position
  if [ "$position" -eq 1 ] && [ "$kind" = timing ]; then
    if [ "$draining" -eq 0 ]; then
      exec 8>"$dir/admit.lock" || die "cannot open admission lock"
      if flock -n 8; then
        exec 9>"$dir/timing1.lock" || die "cannot open timing lock"
        flock -n 9 || die "timing lock held without admission lock"
        draining=1
      else
        exec 8>&-
        reason="waiting for memory-accounting settle delay or another measurement"
      fi
    fi
    if [ "$draining" -eq 1 ] && work_drained; then
      free=$(available)
      if [ "$free" -ge "$need" ]; then
        i=1
        run_job "$@"
      fi
      reason="waiting for memory: $(human "$free") available, timing needs $(human "$need")"
    fi
  elif [ "$position" -eq 1 ]; then
    for i in $(seq 1 "$slots"); do
      exec 9>"$dir/$kind$i.lock"
      if flock -n 9; then
        # Admissions are serialized, and each admitted job keeps the admission
        # lock for MYLANG_SLOT_SETTLE seconds, so the next job's memory check sees
        # this one's footprint instead of the idle moment before it grew.
        exec 8>"$dir/admit.lock"
        if ! flock -n 8; then
          exec 8>&-
          exec 9>&-
          reason="waiting for measurement or memory-accounting settle delay"
          break
        fi
        if timing_pending; then
          exec 8>&-
          exec 9>&-
          reason="timing request queued; pausing new work"
          break
        fi
        free=$(available)
        if [ "$free" -ge "$need" ]; then
          run_job "$@"
        fi
        exec 8>&-
        reason="waiting for memory: $(human "$free") available, $kind needs $(human "$need")"
        exec 9>&-
        break
      fi
      exec 9>&-
      reason="all $slots $kind slot(s) busy"
    done
  else
    reason="earlier $kind tickets must run first"
  fi
  exec 7>&-
  if [ $waited -eq 0 ] || [ $((waited % 60)) -lt "$poll" ]; then
    echo "build-slot: FIFO ticket $ticket_number, position $position; $reason; waiting (${waited}s so far)" >&2
  fi
  sleep "$poll"
  waited=$(( $(date +%s) - started ))
done

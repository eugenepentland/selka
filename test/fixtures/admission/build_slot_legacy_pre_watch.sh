#!/usr/bin/env bash
# build-slot.sh — admit parallel work or an exclusive measurement window.
#
# usage: scripts/build-slot.sh KIND [--] CMD...
#        scripts/build-slot.sh status
#
# KIND is `build` (any `zig build` compile or install, a focused `test-units`/
# `test-cli`, `selka test <dir>`, a guest benchmark build) or `gate` (a full gate
# step: `zig build test`), or `timing` (runtime/compiler measurements).
# A build or gate is admitted only when all hold:
#   * a slot of its kind is free (flock on a per-slot lock file), and
#   * MemAvailable is at least the kind's threshold, and
#   * no timing request is queued or running.
# Waiters receive FIFO tickets per kind; later tickets cannot overtake a live
# earlier waiter, even when it polls less often. Dead/cancelled tickets are reaped.
# Otherwise it waits and reports its position and how long it waited. A waiter whose
# admission is held up by a lock (every slot busy, the settle window, a timing
# window) blocks on that lock for at most SELKA_SLOT_POLL seconds, so it starts the
# moment the lock is released; the other reasons (memory, an earlier ticket) are
# re-checked every SELKA_SLOT_POLL seconds.
# Timing requests stop new admissions, drain active builds/gates, and run one at
# a time. They hold admit.lock through measurement, also excluding older wrappers
# that use that lock. Unwrapped work is outside this cooperative protocol.
# Ordinary jobs use all allowed CPUs unless SELKA_TIMING_CPUS is explicitly set.
#
# Environment (defaults measured on the i7-12700H / 30 GB development box,
# docs/tooling/many-agents.md):
#   SELKA_BUILD_SLOTS=3          concurrent `build` jobs
#   SELKA_GATE_SLOTS=1           concurrent `gate` jobs
#   SELKA_BUILD_MEM=4G           MemAvailable needed to admit a build
#   SELKA_GATE_MEM=6G            MemAvailable needed to admit a gate
#   SELKA_TIMING_MEM=4G          MemAvailable needed to start a measurement
#   SELKA_TIMING_CPUS=           optional CPUs excluded from builds/gates
#                                 (timing inherits the caller's affinity)
#   SELKA_SLOT_POLL=0.25         seconds a waiter waits (on a lock, or asleep) between
#                                 admission attempts; a decimal is accepted
#   SELKA_SLOT_SETTLE=5          at most this many seconds an admitted job delays the
#                                 next admission, so its memory shows up in MemAvailable
#                                 first; the delay ends at once when the job has exited,
#                                 because a job that is gone has no footprint to wait for
#   SELKA_SLOT_DIR               lock directory (default $XDG_RUNTIME_DIR/selka-slots,
#                                 else ~/.cache/selka/slots)
#   SELKA_ZIG_CACHE_CAP_GB=30    bound this worktree's .zig-cache before a build/gate
#                                 (0 turns it off)
#   SELKA_CACHE_TIERS_CAP_GB=10  bound its regenerable .selka-cache/core tiers the
#                                 same way (0 turns it off)
#   SELKA_TEST_CACHES_CAP_GB=8   bound its test suites' caches together, least recently
#                                 used work directory first (0 turns it off)
# Memory sizes take a K/M/G suffix or plain bytes.
#
# The admitted command's environment carries SELKA_ADMISSION_WAIT_S, the seconds (with
# milliseconds) the job waited from its request (the start of build-slot.sh, before its
# interpreter starts) to the moment the command is started, the queue, the cache trim and
# the settle hand-off included. It is what a wrapper such as a lane's build-telemetry tool
# records, since its own clock starts after the queue, and it is the figure the
# "build-slot: ... after Ns" line prints.
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

# The same figures without a process, for the retry loop, which asks four times a second: `read_free` sets `free` to
# MemAvailable in bytes (what `available` prints), `gib` sets `gib_text` to a size as `human` prints it (truncated to
# a tenth).
read_free() {
  local key value rest
  free=0
  while read -r key value rest; do
    if [ "$key" = "MemAvailable:" ]; then
      free=$((value * 1024))
      break
    fi
  done </proc/meminfo
}

gib() {
  printf -v gib_text '%d.%d GiB' $(($1 / 1073741824)) $(($1 % 1073741824 * 10 / 1073741824))
}

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

slot_dir() { echo "$SELKA_SLOT_DIR"; }

# The CPUs this process may use, minus the reserved timing CPUs, as a taskset list.
allowed_cpus() {
  local reserved=${SELKA_TIMING_CPUS-} list cpu keep=() skipped usable
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
    [[ $low =~ ^[0-9]+$ && $high =~ ^[0-9]+$ ]] && [ "$low" -le "$high" ] || die "not a CPU list: '$1'"
    seq "$low" "$high"
  done
}

# One line describing a slot's holder: pid, age, worktree and command.
holder_line() {
  local lock=$1 pid age command worktree
  pid=$(fuser "$lock" 2>/dev/null | tr -s ' ' '\n' | sed '/^$/d' | head -1)
  [ -n "$pid" ] && [ -r "/proc/$pid/cmdline" ] || { echo "holder unknown"; return; }
  age=$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ')
  command=$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null)
  worktree=$(readlink "/proc/$pid/cwd" 2>/dev/null || echo '?')
  printf 'holder %s (age %s, worktree %s): %s' "$pid" "${age:-?}" "$worktree" "${command% }"
}

status() {
  local dir kind n i
  dir=$(slot_dir)
  echo "slot dir: $dir"
  echo "MemAvailable: $(human "$(available)")"
  echo "optional reserved CPUs: ${SELKA_TIMING_CPUS:-none}; builds run on: $(allowed_cpus)"
  if [ "${SELKA_ADMISSION_BACKEND:-shadow}" = scheduler ]; then
    echo "timing policy: disjoint reserved CPUs; exclusive drain when none are reserved"
  else
    echo "timing policy: queued measurements stop admissions and drain active work"
  fi
  for kind in build gate timing; do
    case $kind in
      build) n=${SELKA_BUILD_SLOTS:-3} ;;
      gate) n=${SELKA_GATE_SLOTS:-1} ;;
      timing) n=1 ;;
    esac
    for i in $(seq 1 "$n"); do
      if [ -e "$dir/$kind$i.lock" ] && ! flock -n "$dir/$kind$i.lock" true; then
        echo "$kind$i: busy; $(holder_line "$dir/$kind$i.lock")"
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
      wake=$lock
      wake_wait=$long_wait
      return 1
    fi
  done
}

# Sets SELKA_ADMISSION_WAIT_S to the seconds from the request to now, as SECONDS.MILLIS. No process is
# started for it: EPOCHREALTIME is a shell variable.
admission_wait() {
  local now_us elapsed
  now_us=${EPOCHREALTIME/[.,]/}
  elapsed=$(( (now_us - started_us) / 1000 ))
  [ "$elapsed" -ge 0 ] || elapsed=0
  printf -v SELKA_ADMISSION_WAIT_S '%d.%03d' $((elapsed / 1000)) $((elapsed % 1000))
}

# Sleep `nap_wait` seconds (the poll, unless the reason lasts) without starting a process: `read` with a timeout on a FIFO nobody writes. A `sleep` per poll
# cost a fork and an exec four times a second for every waiter, most of what waiting cost. The FIFO is opened for
# reading and writing (so it never reports end of file) and unlinked at once, so nothing is left behind; where that
# is not possible the wrapper sleeps as before.
nap() {
  if [ -z "$nap_fd" ]; then
    local fifo="$dir/.nap.$$"
    nap_fd=none
    if mkfifo "$fifo" 2>/dev/null; then
      exec {nap_fd}<>"$fifo" || nap_fd=none
      rm -f -- "$fifo"
    fi
  fi
  if [ "$nap_fd" = none ]; then
    sleep "$nap_wait"
  else
    read -r -t "$nap_wait" -u "$nap_fd" || true
  fi
}

# Wait for something to change: block on the lock whose release the caller waits for (the caller set `wake`), for
# at most `wake_wait` seconds, or nap `poll` seconds. A lock is released the moment it is, so the bound only limits
# how soon a waiter notices that its parent has gone (and how long a signal to the wrapper alone waits).
wait_for_change() {
  if [ -n "$wake" ]; then
    flock -w "$wake_wait" "$wake" true 2>/dev/null || true
  else
    nap
  fi
}

run_job() {
  rm -f -- "$ticket" || die "cannot retire FIFO ticket"
  ticket=""
  exec 7>&-
  if [ -n "$nap_fd" ] && [ "$nap_fd" != none ]; then
    exec {nap_fd}>&-
  fi
  export SELKA_ADMISSION_DIR="$dir" SELKA_ADMISSION_KIND="$kind"
  # Record the slot owner so a cache trim can prove which worktree is active.
  process_start "$$" || die "cannot identify the admission owner"
  printf '%s %s %s %s\n' "$$" "$proc_start" "$boot_id" "$worktree" >"$dir/$kind$i.owner" ||
    die "cannot record the admission owner"
  marker_pid=""
  if [ "${SELKA_ADMISSION_BACKEND:-shadow}" = shadow ] && [ -n "${SELKA_SHADOW_ADMITTED_MARKER:-}" ]; then
    # Persist even a sub-poll-period command's transition for its observer. The interpreter starts beside the
    # cache trim's, and the job starts only once both have ended.
    python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/build_admission.py" --shadow-admitted "$SELKA_SHADOW_ADMITTED_MARKER" &
    marker_pid=$!
    unset SELKA_SHADOW_ADMITTED_MARKER
  fi
  # Timing holds fd 8 for its entire lifetime; ordinary jobs keep only fd 9.
  if [ "$kind" != timing ]; then
    # Bound this worktree's own caches before the job starts. The admission lock
    # (fd 8) is still held, so no other admission can race this check; another
    # admitted job of the same worktree (a --watch, say) makes the helper rename
    # nothing. The helper reads recorded sizes and walks no cache: the walk runs
    # in a background process it starts at most once in ten minutes
    # (worktree_cache_trim.py). With every cap at 0 there is nothing to decide.
    if [ "${SELKA_ZIG_CACHE_CAP_GB:-30}" != 0 ] || [ "${SELKA_CACHE_TIERS_CAP_GB:-10}" != 0 ] ||
       [ "${SELKA_TEST_CACHES_CAP_GB:-8}" != 0 ]; then
      python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/worktree_cache_trim.py" \
        --worktree "$worktree" --slot-dir "$dir" --own-slot "$kind$i" \
        --sizes "${common:-$worktree}/prune-caches.sizes" \
        --zig-cap-gb "${SELKA_ZIG_CACHE_CAP_GB:-30}" \
        --tiers-cap-gb "${SELKA_CACHE_TIERS_CAP_GB:-10}" \
        --tests-cap-gb "${SELKA_TEST_CACHES_CAP_GB:-8}" ||
        echo "build-slot: cache trim failed" >&2
    fi
    if [ -n "$marker_pid" ]; then
      wait "$marker_pid" || echo "build-slot: cannot record shadow admission" >&2
      marker_pid=""
    fi
    if [ "$settle" -gt 0 ]; then
      # The accounting timer owns only admission fd 8. Detach it before
      # exec so cancellation of the worker cannot release the delay or
      # inherit a worker pipe/lease/handshake descriptor into the timer.
      # It waits for the slot lock this job holds, for at most `settle`
      # seconds: the delay exists so the next job's memory check sees this
      # job's footprint, and a job that has exited (its last holder of the
      # lock gone) has none, so the delay ends the moment it does.
      command -v setsid >/dev/null || die "setsid is required for the admission timer"
      (
        for settle_path in /proc/$BASHPID/fd/*; do
          settle_fd=${settle_path##*/}
          if [[ $settle_fd =~ ^[0-9]+$ ]] && [ "$settle_fd" -gt 2 ] && [ "$settle_fd" -ne 8 ]; then
            eval "exec ${settle_fd}>&-"
          fi
        done
        exec setsid flock -w "$settle" "$dir/$kind$i.lock" true
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
  if [ -n "$marker_pid" ]; then
    wait "$marker_pid" || echo "build-slot: cannot record shadow admission" >&2
  fi
  admission_wait
  export SELKA_ADMISSION_WAIT_S
  echo "build-slot: $kind slot $i, FIFO ticket $ticket_number after ${SELKA_ADMISSION_WAIT_S}s" >&2
  exec taskset -c "$cpus" "$@"
}

[ -r /proc/sys/kernel/random/boot_id ] || die "Linux /proc is required"
read -r boot_id </proc/sys/kernel/random/boot_id
[ $# -ge 1 ] || die "usage: build-slot.sh build|gate|timing [--] CMD...  |  build-slot.sh status"
kind=$1; shift
case $kind in
  status) status; exit 0 ;;
  build) slots=${SELKA_BUILD_SLOTS:-3}; need=$(bytes "${SELKA_BUILD_MEM:-4G}") || exit 2 ;;
  gate) slots=${SELKA_GATE_SLOTS:-1}; need=$(bytes "${SELKA_GATE_MEM:-6G}") || exit 2 ;;
  timing) slots=1; need=$(bytes "${SELKA_TIMING_MEM:-4G}") || exit 2 ;;
  *) die "kind must be build, gate, timing or status, not '$kind'" ;;
esac
[ "${1:-}" = "--" ] && shift
[ $# -ge 1 ] || die "no command given"
[[ $slots =~ ^[1-9][0-9]*$ ]] || die "slot count must be a positive integer, not '$slots'"
poll=${SELKA_SLOT_POLL:-0.25}
[[ $poll =~ ^([0-9]+\.?[0-9]*|\.[0-9]+)$ ]] && [[ $poll =~ [1-9] ]] || die "SELKA_SLOT_POLL must be a positive number of seconds"
# How long a waiter blocks on a lock that is the only way forward: the poll, but at least 5 s (the poll it replaced).
long_wait=5
if [ "${poll%%.*}" ] && [ "${poll%%.*}" -ge 5 ]; then long_wait=$poll; fi
# How long a waiter whose reason is not a lock that frees at once (memory short, every one of several slots busy) waits
# between attempts: the poll, but at least a second. Each attempt starts processes, and these are the waits that
# last, exactly when the machine is short of memory.
slow_wait=1
if [ "${poll%%.*}" ] && [ "${poll%%.*}" -ge 1 ]; then slow_wait=$poll; fi
gib "$need"
need_text=$gib_text
if [ "$kind" = timing ]; then
  cpus=$(awk '/^Cpus_allowed_list:/ { print $2 }' /proc/self/status)
else
  cpus=$(allowed_cpus) || exit 2
fi
dir=$(slot_dir)
mkdir -p "$dir" || die "cannot create $dir"
dir=$(cd "$dir" && pwd -P) || die "cannot resolve slot directory"
worktree=$(pwd -P) || die "cannot resolve the worktree"
common=$(git -C "$worktree" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
[ "${SELKA_ADMISSION_DIR:-}" != "$dir" ] || die "nested admission inside ${SELKA_ADMISSION_KIND:-unknown} would deadlock; run the coordinator directly, and prepare builds before requesting timing"

settle=${SELKA_SLOT_SETTLE:-5}
[[ $settle =~ ^[0-9]+$ ]] || die "SELKA_SLOT_SETTLE must be a non-negative integer"

# The request's start in microseconds since the epoch: build-slot.sh took it before it started its interpreter, so
# the wait this wrapper reports counts everything the caller waited for. Started without it (an older build-slot.sh
# in front), the wrapper's own start stands.
if [[ ${SELKA_ADMISSION_STARTED_US:-} =~ ^[0-9]{16}$ ]]; then
  started_us=$SELKA_ADMISSION_STARTED_US
else
  started_us=${EPOCHREALTIME/[.,]/}
fi
unset SELKA_ADMISSION_STARTED_US
started=$((started_us / 1000000))
waited=0
reason=""
wake=""
nap_fd=""
behind=0
behind_at=0
reported=""
queue_dir="$dir/queue-$kind"
ticket=""
draining=0
enqueue
# One attempt to admit this request: sets `reason` (and `wake`, the lock whose release would let it through) when
# the job did not start, and does not return when it did. `behind` says the ticket was last found behind an earlier
# one, and `behind_at` when (the shell's SECONDS), so that a waiter at the back looks cheaply (queue_front) except
# once in each second: the full attempt is the one that reaps a dead ticket ahead of it, and a killed waiter's must
# not hold the one behind it up for a number of polls (a poll may be many seconds).
attempt() {
  behind=0
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
        wake="$dir/admit.lock"
        wake_wait=$long_wait
      fi
    fi
    if [ "$draining" -eq 1 ] && work_drained; then
      read_free
      if [ "$free" -ge "$need" ]; then
        i=1
        run_job "$@"
      fi
      gib "$free"
      reason="waiting for memory: $gib_text available, timing needs $need_text"
      nap_wait=$slow_wait
    fi
  elif [ "$position" -eq 1 ]; then
    for ((i = 1; i <= slots; i++)); do
      exec 9>"$dir/$kind$i.lock"
      if flock -n 9; then
        # Admissions are serialized, and each admitted job keeps the admission
        # lock for SELKA_SLOT_SETTLE seconds, so the next job's memory check sees
        # this one's footprint instead of the idle moment before it grew.
        exec 8>"$dir/admit.lock"
        if ! flock -n 8; then
          exec 8>&-
          exec 9>&-
          reason="waiting for measurement or memory-accounting settle delay"
          wake="$dir/admit.lock"
          wake_wait=$long_wait
          break
        fi
        if timing_pending; then
          exec 8>&-
          exec 9>&-
          reason="timing request queued; pausing new work"
          break
        fi
        read_free
        if [ "$free" -ge "$need" ]; then
          run_job "$@"
        fi
        exec 8>&-
        gib "$free"
        reason="waiting for memory: $gib_text available, $kind needs $need_text"
        nap_wait=$slow_wait
        exec 9>&-
        break
      fi
      exec 9>&-
      reason="all $slots $kind slot(s) busy"
      wake="$dir/${kind}1.lock"
      # With one slot its release is the only way forward; with several, any of the others may free first.
      if [ "$slots" -eq 1 ]; then wake_wait=$long_wait; else wake_wait=$slow_wait; fi
    done
  else
    reason="earlier $kind tickets must run first"
    behind=1
    behind_at=$SECONDS
  fi
  exec 7>&-
}

# Whether this ticket is the oldest of its kind, looked at without the queue lock: a waiter that is not at the front
# has nothing to decide until it is. A dead ticket ahead of it is reaped by whoever looks properly (attempt).
queue_front() {
  local entry LC_COLLATE=C
  for entry in "$queue_dir"/[0-9]*.wait; do
    [ -f "$entry" ] || continue
    [ "$entry" = "$ticket" ]
    return
  done
  return 1
}

while :; do
  wake=""
  wake_wait=$poll
  nap_wait=$poll
  # Python phase holders supply a parent identity while waiting. A killed
  # coordinator cannot leave its still-live wrapper blocking the timing queue.
  if [ -n "${SELKA_ADMISSION_PARENT_PID:-}" ]; then
    if ! process_start "$SELKA_ADMISSION_PARENT_PID" ||
       [ "$proc_start" != "${SELKA_ADMISSION_PARENT_START:-}" ]; then
      exit 143
    fi
  fi
  if [ "$behind" -gt 0 ] && [ "$SECONDS" -le "$behind_at" ] && ! queue_front; then
    :
  else
    attempt "$@"
  fi
  if [ -z "$reported" ] || [ $((SECONDS - reported)) -ge 60 ]; then
    echo "build-slot: FIFO ticket $ticket_number, position $position; $reason; waiting (${waited}s so far)" >&2
    reported=$SECONDS
  fi
  wait_for_change
  waited=$(( ${EPOCHREALTIME/[.,]/} / 1000000 - started ))
done

#!/usr/bin/env bash
# Keep the build caches of this repository's worktrees bounded.
#
# Zig never evicts its build cache: every edit adds a new Debug compiler (about
# 200 MB), the side tools and the test binaries to a worktree's `.zig-cache`,
# and agent worktrees are rarely removed. This script, run by hand or from a
# timer, deletes only output a build regenerates:
#
#   idle  A worktree nobody has built in, committed in or written scratch to
#         for --idle-days loses `.zig-cache`, `zig-out`, any
#         per-worktree `.zig-*-cache`, and, inside its `.tmp*` scratch folders,
#         nested cache folders, `zig-out` folders, ELF binaries and `.o`/`.a`/
#         `.so` files. Logs, JSON, sources and notes in scratch are kept.
#   cap   Any other worktree whose `.zig-cache` exceeds --cap-gb loses that
#         cache as a whole (Zig cannot drop single entries: a manifest naming a
#         deleted artifact fails the next build).
#
#   store The new core's per-user object store ($SELKA_CORE_RUNTIME_CACHE, else
#         $XDG_CACHE_HOME/selka/core-runtime, else ~/.cache/selka/core-runtime)
#         keeps flat and `units-v1/ab/<key>.o` hardlink aliases for every retained
#         object, restoring missing aliases in bounded batches. A size ledger inventories
#         object/checksum bytes under shared leases; bounded LRU eviction alone
#         takes exclusive leases, skipping an active store. Verified unit hits
#         refresh mtime (legacy objects use access time too). Unread entries over
#         --store-days, excess bytes over --store-cap-gb and day-old partials are
#         candidates. If over cap, paired eviction continues to 90% of the cap;
#         young objects can be capacity victims, but a retained object never loses
#         only its flat alias. JSON reports include physical inode-deduplicated
#         bytes, operational IO/CPU costs, changed ledger rows and unmet caps.
#   evidence Versioned evidence stores have leases and retention pins. They are
#         collected explicitly with scripts/cache_retention.py. Never remove a
#         worktree's whole .selka-cache: it can contain protected evidence.
#   shared The optional shared compiler-artifact and native test-receipt stores
#         ($SELKA_COMPILER_SHARED_CACHE and $SELKA_TEST_SHARED_CACHE when set,
#         else the defaults $XDG_CACHE_HOME/selka/compiler-artifacts and
#         .../native-tests, else the same under ~/.cache/selka) are collected
#         only by their own collector, `selka cache gc --kind compiler|tests`,
#         which honours their leases and LRU budgets and skips a busy store. This
#         script runs it (a preview unless --apply) for each root holding an
#         initialized v2 namespace, using --selka PATH or the `selka` on PATH,
#         and touches nothing else in those stores.
#   core  In every worktree that is not idle, `.selka-cache/core` loses linked
#         programs (`programs-v2`, `programs-v1`), `--link` objects (`foreign-v1`) and replay
#         records (`replay-v1`) unread for --store-days, and staging directories
#         (`native-link-*`, and the `program-*` ones older drivers left behind)
#         older than --quiet-minutes.
#
# A worktree is skipped while any process has its working directory inside it
# or its caches changed in the last --quiet-minutes. Checkouts, branches,
# commits and uncommitted files are never touched, and neither is the primary
# worktree (the main checkout) unless --include-primary is given, nor a
# worktree marked to keep (a pinned compiler install, say): a `prune-keep` file
# in its git directory (`$(git rev-parse --git-dir)/prune-keep`, invisible to
# `git status`) or a `.prune-keep` file in the worktree.
#
# Default is a dry run that prints what would go; --apply deletes. A cache is
# renamed aside before it is removed, so a build that starts meanwhile sees
# no cache rather than half of one.
set -uo pipefail

usage() {
    cat <<'USAGE'
usage: scripts/prune-caches.sh [--apply] [--repo DIR] [--idle-days N] [--cap-gb N]
                               [--quiet-minutes N] [--exclude GLOB]... [--include-primary]
                               [--list-kept]
  --apply            delete (default: dry run)
  --repo DIR         any checkout of the repository (default: this script's)
  --idle-days N      idle rule threshold in days (default 3)
  --cap-gb N         per-worktree .zig-cache cap in GiB (default 15)
  --quiet-minutes N  skip a worktree whose caches changed this recently (default 30)
  --exclude GLOB     skip worktrees whose path matches GLOB (repeatable)
  --include-primary  also prune the primary worktree
  --list-kept        list every prune-keep marker with owner, reason, expiry and
                     cache size; report empty, partial and expired markers (never delete)
  --store-days N     store/core rules: unread for N days (default 14)
  --store-cap-gb N   store rule: per-user object store cap in GiB (default 10)
  --selka PATH      shared rule: the compiler whose `cache gc` collects the
                     shared stores (default: `selka` on PATH; skipped if none)
USAGE
}

apply=0
repo="$(cd "$(dirname "$0")/.." && pwd)"
idle_days=3
cap_gb=15
quiet_minutes=30
include_primary=0
list_kept=0
store_days=14
store_cap_gb=10
excludes=()
selka_bin="$(command -v selka 2>/dev/null || true)"
while [ $# -gt 0 ]; do
    case "$1" in
        --apply) apply=1 ;;
        --repo) repo="$2"; shift ;;
        --idle-days) idle_days="$2"; shift ;;
        --cap-gb) cap_gb="$2"; shift ;;
        --quiet-minutes) quiet_minutes="$2"; shift ;;
        --exclude) excludes+=("$2"); shift ;;
        --include-primary) include_primary=1 ;;
        --list-kept) list_kept=1 ;;
        --store-days) store_days="$2"; shift ;;
        --store-cap-gb) store_cap_gb="$2"; shift ;;
        --selka) selka_bin="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
    shift
done

common="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)"
exec 9>"$common/prune-caches.lock"
flock -n 9 || { echo "prune-caches: another run holds $common/prune-caches.lock" >&2; exit 0; }

# `du` over a large `.zig-cache` takes about a minute, so the cap rule
# remembers each cache's size with the modification time of its `o/` folder,
# which changes whenever Zig adds an artifact, and measures again only then.
# Admission records the same entries (keyed by the worktree) while it enforces
# the active-run caps, and --list-kept reads them instead of walking every kept
# worktree.
sizes_file="$common/prune-caches.sizes"
declare -A sizes=() measured=()
if [ -f "$sizes_file" ]; then
    while IFS=$'\t' read -r path stamp kib; do sizes["$path"]="$stamp $kib"; done < "$sizes_file"
fi

now=$(date +%s)
idle_seconds=$((idle_days * 86400))
quiet_seconds=$((quiet_minutes * 60))
cap_kib=$((cap_gb * 1024 * 1024))
total_kib=0

# Working directories of every process this user can see, one per line.
cwds="$(for link in /proc/[0-9]*/cwd; do readlink "$link" 2>/dev/null || true; done | sort -u)"

busy() {
    grep -qxF -e "$1" <<<"$cwds" && return 0
    grep -qF -e "$1/" <<<"$cwds"
}

# The newest modification time among the places a build, commit or agent
# writes: cache and output directories one level deep, scratch folders, the
# worktree's git index and HEAD, and its last commit. Not the reflog: `git gc`
# rewrites every worktree's `logs/HEAD` when it expires entries.
last_activity() {
    local tree="$1" gitdir newest
    gitdir="$(git -C "$tree" rev-parse --path-format=absolute --git-dir 2>/dev/null || true)"
    newest=$(
        {
            find "$tree/.zig-cache" "$tree/.selka-cache" "$tree/zig-out" -maxdepth 1 -printf '%T@\n' 2>/dev/null || true
            find "$tree" -maxdepth 1 -name '.tmp*' -printf '%T@\n' 2>/dev/null || true
            find "$tree" -maxdepth 2 -path "$tree/.tmp*/*" -printf '%T@\n' 2>/dev/null || true
            if [ -n "$gitdir" ]; then stat -c '%Y' "$gitdir/index" "$gitdir/HEAD" 2>/dev/null; fi
            git -C "$tree" log -1 --format=%ct 2>/dev/null
        } | sort -rn | awk 'NR == 1'
    )
    echo "${newest%%.*}"
}

cache_changed_recently() {
    local newest
    newest=$(find "$1/.zig-cache" "$1/.selka-cache" -maxdepth 1 -printf '%T@\n' 2>/dev/null | sort -rn | awk 'NR == 1')
    [ -n "$newest" ] && [ $((now - ${newest%%.*})) -lt "$quiet_seconds" ]
}

# The prune-keep marker of a worktree, git-dir marker first when both exist.
keep_marker() {
    local tree="$1" gitdir="$2"
    if [ -n "$gitdir" ] && [ -e "$gitdir/prune-keep" ]; then
        printf '%s' "$gitdir/prune-keep"
    elif [ -e "$tree/.prune-keep" ]; then
        printf '%s' "$tree/.prune-keep"
    fi
}

# One marker's annotation as "owner=... reason=... until=..." or empty when unannotated.
keep_fields() {
    local marker="$1" owner reason until
    owner=$(sed -n 's/^owner=//p' "$marker" 2>/dev/null | head -1)
    reason=$(sed -n 's/^reason=//p' "$marker" 2>/dev/null | head -1)
    until=$(sed -n 's/^until=//p' "$marker" 2>/dev/null | head -1)
    printf 'owner=%s reason=%s until=%s' "${owner:-MISSING}" "${reason:-MISSING}" "${until:-MISSING}"
}

# Warnings for a marker: unannotated, malformed expiry, or past its expiry.
keep_warnings() {
    local marker="$1" owner reason until today
    owner=$(sed -n 's/^owner=//p' "$marker" 2>/dev/null | head -1)
    reason=$(sed -n 's/^reason=//p' "$marker" 2>/dev/null | head -1)
    until=$(sed -n 's/^until=//p' "$marker" 2>/dev/null | head -1)
    today=$(date +%F)
    if [ -z "$owner" ] || [ -z "$reason" ] || [ -z "$until" ]; then
        printf ' unannotated(missing owner/reason/until)'
    elif ! [[ "$until" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        printf ' malformed-until(%s)' "$until"
    elif [[ "$until" < "$today" ]]; then
        printf ' EXPIRED(%s)' "$until"
    fi
}

# `--list-kept`: every marker, its owner/reason/expiry, activity and cache size.
list_kept_markers() {
    local tree gitdir marker activity kib now_seconds age_days
    now_seconds=$(date +%s)
    while IFS= read -r line; do
        case "$line" in
            "worktree "*) tree="${line#worktree }" ;;
            *) continue ;;
        esac
        [ -d "$tree" ] || continue
        gitdir="$(git -C "$tree" rev-parse --path-format=absolute --git-dir 2>/dev/null || true)"
        marker="$(keep_marker "$tree" "$gitdir")"
        [ -n "$marker" ] || continue
        activity=$(last_activity "$tree")
        age_days=0
        [ -n "$activity" ] && age_days=$(((now_seconds - activity) / 86400))
        # The sizes file is keyed by the .zig-cache/o stamp, which admission and
        # the cap rule keep current; never walk every kept worktree with du.
        kib=""
        known="${sizes[$tree]:-}"
        stamp=$(stat -c %Y "$tree/.zig-cache/o" 2>/dev/null || echo 0)
        cache="unmeasured (no recorded admission size)"
        if [ -n "$known" ]; then
            kib="${known#* }"
            if [ "${known%% *}" = "$stamp" ]; then
                cache=$(human "$kib")
            else
                cache="~$(human "$kib") (o/ changed since it was measured)"
            fi
        fi
        echo "kept      $tree"
        echo "          marker $marker; activity ${age_days}d ago; zig-cache $cache"
        echo "          $(keep_fields "$marker")$(keep_warnings "$marker")"
    done < <(git -C "$repo" worktree list --porcelain)
    echo "kept markers are reported, never deleted; annotate with owner=, reason= and until=YYYY-MM-DD"
    store_last_report
}

# The store's last scheduled verdict, from the collector's own record.
store_last_report() {
    local scripts_dir root
    scripts_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
    if [ -n "${SELKA_CORE_RUNTIME_CACHE:-}" ]; then
        root="$SELKA_CORE_RUNTIME_CACHE"
    elif [ -n "${XDG_CACHE_HOME:-}" ]; then
        root="$XDG_CACHE_HOME/selka/core-runtime"
    else
        root="$HOME/.cache/selka/core-runtime"
    fi
    if [ ! -f "$root/.last-maintenance.json" ]; then
        echo "store: no recorded maintenance run at $root"
        return
    fi
    python3 - "$scripts_dir" "$root/.last-maintenance.json" <<'PY'
import json
import sys
sys.path.insert(0, sys.argv[1])
import core_store_gc
print(core_store_gc.store_status(json.load(open(sys.argv[2]))))
PY
}

size_kib() {
    local kib
    kib=$(du -sx --block-size=1K "$1" 2>/dev/null | cut -f1)
    echo "${kib:-0}"
}

human() { awk -v k="$1" 'BEGIN { if (k >= 1048576) printf "%.1f GiB", k / 1048576; else printf "%.0f MiB", k / 1024 }'; }

remove_dir() {
    local path="$1" reason="$2" kib
    kib=$(size_kib "$path")
    total_kib=$((total_kib + kib))
    if [ "$apply" = 1 ]; then
        local aside="$path.prune-$$"
        if mv -- "$path" "$aside"; then
            rm -rf -- "$aside"
            echo "deleted   $(human "$kib")  $path  ($reason)"
        else
            echo "failed    $path  (could not move it aside)" >&2
        fi
    else
        echo "would del $(human "$kib")  $path  ($reason)"
    fi
}

# Regenerable build output inside one scratch folder: nested caches and
# install trees, native binaries and objects. Everything else stays.
prune_scratch() {
    local scratch="$1" kib=0 bytes
    # Scratch can hold explicitly selected shared evidence too. Its permanent
    # lock is retained even after all payloads are evicted. The dedicated GC
    # owns cleanup; never walk through its leased or pinned blobs here.
    if [ -n "$(find "$scratch" \( -path '*/locks/retention.lock' -o -name .retention.lock \) -print -quit 2>/dev/null)" ]; then
        echo "kept      $scratch  (retention-managed cache; use its dedicated collector)"
        return
    fi
    while IFS= read -r -d '' dir; do
        remove_dir "$dir" "cache in scratch"
    done < <(find "$scratch" -mindepth 1 -type d \( -iname '*cache*' -o -name zig-out \) -prune -print0 2>/dev/null)
    while IFS= read -r -d '' file; do
        case "$file" in
            *.o|*.a|*.so) ;;
            *) if [ "$(head -c 4 -- "$file" 2>/dev/null | od -An -tx1 | tr -d ' \n')" != 7f454c46 ]; then continue; fi ;;
        esac
        bytes=$(stat -c %s -- "$file" 2>/dev/null || echo 0)
        kib=$((kib + bytes / 1024))
        if [ "$apply" = 1 ]; then rm -f -- "$file"; fi
    done < <(find "$scratch" -mindepth 1 -type d \( -iname '*cache*' -o -name zig-out \) -prune -o -type f \( -name '*.o' -o -name '*.a' -o -name '*.so' -o -size +64k \) -print0 2>/dev/null)
    if [ "$kib" -gt 0 ]; then
        total_kib=$((total_kib + kib))
        echo "$([ "$apply" = 1 ] && echo "deleted  " || echo "would del") $(human "$kib")  $scratch/**  (binaries and objects in scratch)"
    fi
}

# Delete one file (and say so in a dry run), counting its size.
remove_file() {
    local file="$1" bytes
    bytes=$(stat -c %s -- "$file" 2>/dev/null || echo 0)
    pruned_bytes=$((pruned_bytes + bytes))
    if [ "$apply" = 1 ]; then rm -f -- "$file"; fi
}

# Report what one rule removed (or would remove) under a directory.
report_bytes() {
    local where="$1" reason="$2" kib=$((pruned_bytes / 1024))
    if [ "$kib" -gt 0 ]; then
        total_kib=$((total_kib + kib))
        echo "$([ "$apply" = 1 ] && echo "deleted  " || echo "would del") $(human "$kib")  $where  ($reason)"
    fi
    pruned_bytes=0
}

# Take cooperative namespace leases without waiting for a running compiler.
# Lease locks are permanent; work locks are collectible only under these leases.
with_native_leases() {
    local operation="$1"; shift
    local root="$1" directory descriptor ready=1
    local descriptors=()
    [ -d "$root" ] || return 0
    for directory in "$@"; do
        if ! mkdir -p -- "$directory"; then ready=0; break; fi
        if [ -L "$directory/.retention.lock" ] ||
           { [ -e "$directory/.retention.lock" ] && [ ! -f "$directory/.retention.lock" ]; }; then
            ready=0; break
        fi
        if ! exec {descriptor}>>"$directory/.retention.lock"; then ready=0; break; fi
        descriptors+=("$descriptor")
        if ! flock -nx "$descriptor"; then ready=0; break; fi
    done
    if [ "$ready" = 1 ]; then
        "$operation" "$root"
    else
        echo "busy      $root  (native cache lease unavailable)"
    fi
    for descriptor in "${descriptors[@]}"; do exec {descriptor}>&-; done
}

# A store named by SELKA_STORE_GC_DENY (the retention tests deny the user's own) is refused by the collector, whatever this script is asked.
prune_store() {
    local args=(--store "$1" --max-bytes "$((store_cap_gb * 1024 * 1024 * 1024))" --max-age-days "$store_days")
    if [ "$apply" = 1 ]; then args+=(--apply); fi
    # The collector holds no lease that builds wait on: it reads the shards that are due
    # into its ledger and evicts what nothing has used within its grace period.
    python3 "$(dirname "${BASH_SOURCE[0]}")/core_store_gc.py" "${args[@]}" || return
}

# The Python collector removes idle store work claims in bounded batches under
# the same leases; the legacy per-file shell loop is gone.

# Every owner/waiter leases its namespace before opening a work-lock inode.
# The caller holds all named namespaces exclusively, so idle key locks can go.
prune_native_claims() {
    local namespace
    for namespace in "$@"; do
        [ -d "$namespace/work" ] || continue
        find "$namespace/work" -regextype posix-extended -mindepth 1 -maxdepth 1 \
            -type f -regex '.*/[0-9a-f]{64}\.lock' -delete 2>/dev/null || true
    done
}

if [ "$list_kept" = 1 ]; then
    list_kept_markers
    exit 0
fi

# One worktree's core cache directory: unread programs, foreign objects and
# replay records, and staging directories no build still owns.
prune_core() {
    with_native_leases prune_core_contents "$1" "$1/programs-v2" "$1/programs-v1" "$1/foreign-v1"
}

prune_core_contents() {
    local core="$1" dir
    [ -d "$core" ] || return 0
    pruned_bytes=0
    while IFS= read -r -d '' file; do
        remove_file "$file"
    done < <(find "$core/programs-v2" "$core/programs-v1" "$core/foreign-v1" "$core/replay-v1" \
        \( -name .retention.lock -o -name work \) -prune -o -type f -atime +"$store_days" -print0 2>/dev/null)
    report_bytes "$core" "core caches unread for ${store_days}d"
    while IFS= read -r -d '' dir; do
        remove_dir "$dir" "stale core staging"
    done < <(find "$core" -mindepth 1 -maxdepth 1 -type d \( -name 'native-link-*' -o -name 'program-*' -o -name 'unproved-tool-*' \) -mmin +"$quiet_minutes" -print0 2>/dev/null)
    prune_native_claims "$core" "$core/programs-v2" "$core/programs-v1" "$core/foreign-v1"
    report_bytes "$core" "idle native work claims"
}

pruned_bytes=0
store_root="${SELKA_CORE_RUNTIME_CACHE-}"
if [ -z "${SELKA_CORE_RUNTIME_CACHE+set}" ]; then
    case "${XDG_CACHE_HOME:-}" in
        /*) store_root="$XDG_CACHE_HOME/selka/core-runtime" ;;
        *) store_root="$HOME/.cache/selka/core-runtime" ;;
    esac
fi
if [ -n "$store_root" ]; then prune_store "$store_root"; fi

# One shared store, through its own lease-aware collector. An explicitly empty
# variable disables that store; an unset one names its default root.
collect_shared() {
    local kind="$1" variable="$2" leaf="$3" namespace="$4" root report
    root="${!variable-}"
    if [ -z "${!variable+set}" ]; then
        case "${XDG_CACHE_HOME:-}" in
            /*) root="$XDG_CACHE_HOME/selka/$leaf" ;;
            *) if [ -n "${HOME:-}" ]; then root="$HOME/.cache/selka/$leaf"; fi ;;
        esac
    fi
    if [ -z "$root" ] || [ ! -f "$root/$namespace/format" ]; then return 0; fi
    if [ -z "$selka_bin" ]; then
        echo "skipped   $root/$namespace  (shared store; pass --selka PATH to collect it)"
        return 0
    fi
    local args=(cache gc --shared-cache-dir "$root" --kind "$kind")
    if [ "$apply" = 1 ]; then args+=(--apply); fi
    report="$("$selka_bin" "${args[@]}" 2>&1 | tr '\n' ' ')"
    echo "shared    $root/$namespace  ($report)"
}
collect_shared compiler SELKA_COMPILER_SHARED_CACHE compiler-artifacts compiler-artifacts-v2
collect_shared tests SELKA_TEST_SHARED_CACHE native-tests native-tests-v3

primary=""
while IFS= read -r line; do
    case "$line" in
        "worktree "*) tree="${line#worktree }" ;;
        *) continue ;;
    esac
    if [ -z "$primary" ]; then
        primary="$tree"
        if [ "$include_primary" != 1 ]; then continue; fi
    fi
    if [ ! -d "$tree" ]; then continue; fi
    skip=0
    for glob in "${excludes[@]+"${excludes[@]}"}"; do
        # shellcheck disable=SC2053
        if [[ "$tree" == $glob ]]; then skip=1; fi
    done
    if [ "$skip" = 1 ]; then continue; fi
    gitdir="$(git -C "$tree" rev-parse --path-format=absolute --git-dir 2>/dev/null || true)"
    if [ -n "$gitdir" ] && [ -f "$gitdir/selka-service-worktree.json" ]; then
        echo "kept      $tree  (registered service checkout; never pruned)"
        continue
    fi
    marker="$(keep_marker "$tree" "$gitdir")"
    if [ -n "$marker" ]; then
        echo "kept      $tree  (marked prune-keep: $(keep_fields "$marker")$(keep_warnings "$marker"))"
        continue
    fi
    if busy "$tree"; then echo "busy      $tree  (a process is working in it)"; continue; fi
    if cache_changed_recently "$tree"; then echo "busy      $tree  (caches changed in the last $quiet_minutes min)"; continue; fi
    last=$(last_activity "$tree")
    if [ -n "$last" ] && [ $((now - last)) -ge "$idle_seconds" ]; then
        days=$(((now - last) / 86400))
        for dir in "$tree/.zig-cache" "$tree/zig-out" "$tree"/.zig-*-cache; do
            if [ -d "$dir" ]; then remove_dir "$dir" "idle ${days}d"; fi
        done
        for scratch in "$tree"/.tmp*; do
            if [ -d "$scratch" ]; then prune_scratch "$scratch"; fi
        done
    else
        prune_core "$tree/.selka-cache/core"
        if [ -d "$tree/.zig-cache" ]; then
            stamp=$(stat -c %Y "$tree/.zig-cache/o" 2>/dev/null || echo 0)
            known="${sizes[$tree]:-}"
            if [ -n "$known" ] && [ "${known%% *}" = "$stamp" ]; then kib="${known#* }"; else kib=$(size_kib "$tree/.zig-cache"); fi
            if [ "$kib" -gt "$cap_kib" ]; then
                remove_dir "$tree/.zig-cache" "over ${cap_gb} GiB cap"
            else
                measured["$tree"]="$stamp $kib"
            fi
        fi
    fi
done < <(git -C "$repo" worktree list --porcelain)

if [ "$apply" = 1 ]; then
    for path in "${!measured[@]}"; do
        printf '%s\t%s\t%s\n' "$path" "${measured[$path]% *}" "${measured[$path]#* }"
    done > "$sizes_file.tmp" && mv -f "$sizes_file.tmp" "$sizes_file"
fi
echo "total $([ "$apply" = 1 ] && echo "freed" || echo "would free"): $(human "$total_kib")"

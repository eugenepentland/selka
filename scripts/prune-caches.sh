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
#   store The new core's per-user object store ($MYLANG_CORE_RUNTIME_CACHE, else
#         $XDG_CACHE_HOME/mylang/core-runtime, else ~/.cache/mylang/core-runtime)
#         loses unit objects (`units-v1/<key>.o` with its `.sum`), runtime objects
#         and number-text objects nobody read for --store-days (by access time;
#         every build that uses an object reads it), then the least recently
#         read ones until it fits --store-cap-gb, and `.partial` files over a day
#         old. Entries are keyed by content, so a deleted one is only recompiled.
#   evidence Versioned evidence stores have leases and retention pins. They are
#         collected explicitly with scripts/cache_retention.py. Never remove a
#         worktree's whole .mylang-cache: it can contain protected evidence.
#   core  In every worktree that is not idle, `.mylang-cache/core` loses linked
#         programs (`programs-v1`), `--link` objects (`foreign-v1`) and replay
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
  --apply            delete (default: dry run)
  --repo DIR         any checkout of the repository (default: this script's)
  --idle-days N      idle rule threshold in days (default 3)
  --cap-gb N         per-worktree .zig-cache cap in GiB (default 15)
  --quiet-minutes N  skip a worktree whose caches changed this recently (default 30)
  --exclude GLOB     skip worktrees whose path matches GLOB (repeatable)
  --include-primary  also prune the primary worktree
  --store-days N     store/core rules: unread for N days (default 14)
  --store-cap-gb N   store rule: per-user object store cap in GiB (default 10)
USAGE
}

apply=0
repo="$(cd "$(dirname "$0")/.." && pwd)"
idle_days=3
cap_gb=15
quiet_minutes=30
include_primary=0
store_days=14
store_cap_gb=10
excludes=()
while [ $# -gt 0 ]; do
    case "$1" in
        --apply) apply=1 ;;
        --repo) repo="$2"; shift ;;
        --idle-days) idle_days="$2"; shift ;;
        --cap-gb) cap_gb="$2"; shift ;;
        --quiet-minutes) quiet_minutes="$2"; shift ;;
        --exclude) excludes+=("$2"); shift ;;
        --include-primary) include_primary=1 ;;
        --store-days) store_days="$2"; shift ;;
        --store-cap-gb) store_cap_gb="$2"; shift ;;
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
            find "$tree/.zig-cache" "$tree/.mylang-cache" "$tree/zig-out" -maxdepth 1 -printf '%T@\n' 2>/dev/null || true
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
    newest=$(find "$1/.zig-cache" "$1/.mylang-cache" -maxdepth 1 -printf '%T@\n' 2>/dev/null | sort -rn | awk 'NR == 1')
    [ -n "$newest" ] && [ $((now - ${newest%%.*})) -lt "$quiet_seconds" ]
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

# The new core's per-user object store: unread entries go, then the least
# recently read ones until the store fits its cap. A unit object and its
# `.sum` record go together.
prune_store() {
    local store="$1" days_ago=$((now - store_days * 86400)) kib atime file
    [ -d "$store" ] || return 0
    pruned_bytes=0
    while IFS= read -r -d '' file; do
        remove_file "$file"
    done < <(find "$store" -name '*.partial' -mmin +1440 -print0 2>/dev/null)
    while IFS=$'\t' read -r atime file; do
        [ "${atime%%.*}" -lt "$days_ago" ] || continue
        remove_file "$file"
        if [ "${file%.o}" != "$file" ] && [ -e "$file.sum" ]; then remove_file "$file.sum"; fi
    done < <(find "$store" \( -path "$store/units-v1/*.o" -o -name 'core_rt-*.o' -o -name 'core_rt-*.c' -o -name 'core_number_text-*.o' \) -printf '%A@\t%p\n' 2>/dev/null)
    report_bytes "$store" "unread for ${store_days}d"
    kib=$(size_kib "$store")
    if [ "$apply" = 1 ] && [ "$kib" -gt $((store_cap_gb * 1024 * 1024)) ]; then
        while IFS=$'\t' read -r atime file; do
            [ "$kib" -gt $((store_cap_gb * 1024 * 1024)) ] || break
            kib=$((kib - $(stat -c %s -- "$file" 2>/dev/null || echo 0) / 1024))
            remove_file "$file"
            if [ -e "$file.sum" ]; then remove_file "$file.sum"; fi
        done < <(find "$store/units-v1" -name '*.o' -printf '%A@\t%p\n' 2>/dev/null | sort -n)
        report_bytes "$store" "over ${store_cap_gb} GiB cap"
    fi
}

# One worktree's core cache directory: unread programs, foreign objects and
# replay records, and staging directories no build still owns.
prune_core() {
    local core="$1" dir
    [ -d "$core" ] || return 0
    pruned_bytes=0
    while IFS= read -r -d '' file; do
        remove_file "$file"
    done < <(find "$core/programs-v1" "$core/foreign-v1" "$core/replay-v1" -type f -atime +"$store_days" -print0 2>/dev/null)
    report_bytes "$core" "core caches unread for ${store_days}d"
    while IFS= read -r -d '' dir; do
        remove_dir "$dir" "stale core staging"
    done < <(find "$core" -mindepth 1 -maxdepth 1 -type d \( -name 'native-link-*' -o -name 'program-*' -o -name 'unproved-tool-*' \) -mmin +"$quiet_minutes" -print0 2>/dev/null)
}

pruned_bytes=0
store_root="${MYLANG_CORE_RUNTIME_CACHE-}"
if [ -z "${MYLANG_CORE_RUNTIME_CACHE+set}" ]; then
    case "${XDG_CACHE_HOME:-}" in
        /*) store_root="$XDG_CACHE_HOME/mylang/core-runtime" ;;
        *) store_root="$HOME/.cache/mylang/core-runtime" ;;
    esac
fi
if [ -n "$store_root" ]; then prune_store "$store_root"; fi

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
    if [ -e "$tree/.prune-keep" ] || { [ -n "$gitdir" ] && [ -e "$gitdir/prune-keep" ]; }; then
        echo "kept      $tree  (marked prune-keep)"
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
        prune_core "$tree/.mylang-cache/core"
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

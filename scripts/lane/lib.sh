#!/usr/bin/env bash
# Shared helpers of the lane kit (docs/tooling/lane-kit.md). Sourced by the other scripts; not run by itself.
# Nothing here is exported to the caller: every script sets the cache variables only on the command it runs.

LANE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
LANE_REPO=$(cd "$LANE_DIR/../.." && pwd -P)
KIT_ROOT=${KIT_ROOT:-$HOME/ai/.home-cache/aw/kit}
# The guardian checkout a base build of a commit from before GH-2 links beside it (kit-base.sh).
KIT_GUARDIAN=${KIT_GUARDIAN:-$HOME/ai/canopy/guardian-zig}
KIT_SOURCES=${KIT_SOURCES:-$HOME/ai/canopy}

# die MESSAGE: print to stderr and leave with status 2 (a usage or host failure).
die() { echo "$(basename "$0"): $*" >&2; exit 2; }

# short_rev REV: the ten-character commit name a kit directory is named after (main's head when REV is empty).
short_rev() { git -C "$LANE_REPO" rev-parse --verify --short=10 "${1:-main}^{commit}" 2>/dev/null || die "no such revision: ${1:-main}"; }

# resolve_kit [DIR]: DIR when it holds a READY kit, else the kit whose READY file is newest under $KIT_ROOT.
resolve_kit() {
  local k=${1:-}
  if [ -n "$k" ]; then
    [ -f "$k/READY" ] || die "no READY kit at $k (run: scripts/lane/kit.sh prepare)"
    (cd "$k" && pwd -P); return
  fi
  k=$(ls -t "$KIT_ROOT"/*/READY 2>/dev/null | head -1)
  [ -n "$k" ] || die "no READY kit under $KIT_ROOT (run: scripts/lane/kit.sh prepare)"
  (cd "$(dirname "$k")" && pwd -P)
}

# compiler_env COMPILER: the SELKA_COMPONENT_DIR assignment that belongs to a compiler (its libexec beside it), so that a
# caller's own exported component directory (the watcher's) never leaks into a base compiler. Prints "-u SELKA_COMPONENT_DIR"
# for `env` when the compiler has no libexec of its own.
compiler_env() {
  local c=$1 d
  d=$(cd "$(dirname "$c")/.." 2>/dev/null && pwd -P)/libexec/selka/components
  if [ -d "$d" ]; then echo "SELKA_COMPONENT_DIR=$d"; else echo "-u SELKA_COMPONENT_DIR"; fi
}

# compiler_check COMPILER: fail early on a compiler path that is not an executable.
compiler_check() { [ -x "$1" ] || die "not an executable compiler: $1"; }

# run_with STORES COMPILER ARGS...: the compiler with the three cache variables under STORES and its own component directory.
run_with() {
  local st=$1 c=$2; shift 2
  # shellcheck disable=SC2046
  "$LANE_DIR/with-stores.sh" "$st" env $(compiler_env "$c") SELKA_JOBS=3 "$c" "$@"
}

# busy_machine: print what is already gating or building the compiler on the machine (empty when calm). The patterns are
# anchored at the start of a command line, so another session's `until pgrep -f ...` wait loop does not count.
busy_machine() {
  pgrep -af '^(python3? [^ ]*verify_cache\.py|[^ ]*/zig (build|build-exe|build-obj|build-lib|test)( |$))' 2>/dev/null | cut -c1-150
}

# elapsed T0: the seconds since an earlier `t0=$SECONDS`, as "12s".
elapsed() { echo "$((SECONDS - $1))s"; }

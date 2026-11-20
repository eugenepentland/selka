#!/usr/bin/env bash
# The installed unit enters through service_worktree.py, whose common lease
# covers refresh and this complete run. Maintenance owns ordinary shared
# admission, including its exact metadata scan and incremental ledger updates.
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
cd -- "$repository"
source "$HOME/.config/selka/dev-env.sh"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/selka/core-store-maintenance"
mkdir -p -- "$state_root"
maintenance_root=$(mktemp -d "$state_root/run.XXXXXX")
export TMPDIR="$maintenance_root/tmp"
export ZIG_LOCAL_CACHE_DIR="$maintenance_root/zig"
mkdir -p -- "$TMPDIR" "$ZIG_LOCAL_CACHE_DIR"
trap 'rmdir -- "$TMPDIR" "$ZIG_LOCAL_CACHE_DIR" "$maintenance_root" || true' EXIT
cd -- "$maintenance_root"
"$repository/scripts/build-slot.sh" build python3 "$repository/scripts/core_store_gc.py" "$@"

#!/usr/bin/env bash
set -euo pipefail
source "$HOME/.config/selka/dev-env.sh"
export ZIG_LOCAL_CACHE_DIR="${LANGUAGE_WAVE1_CACHE_DIR:-$PWD/.zig-cache-wave1-l10}"
export TMPDIR="${LANGUAGE_WAVE1_TMPDIR:-$PWD/.tmp-wave1-l10}"
mkdir -p "$ZIG_LOCAL_CACHE_DIR" "$TMPDIR"
export LANGUAGE_WAVE1_ADMITTED=1
exec flock --shared "$HOME/ai/canopy/.caching-followup-20261014-control/activity.lock" scripts/build-slot.sh build python3 scripts/regenerate_language_wave1.py "$@"

#!/usr/bin/env bash
# Run a driver and keep a green step's standard error empty.
#
# The pinned Zig build runner prints a `failed command:` block for every step
# that wrote to standard error, even when the step passed. A Python driver's
# unittest progress is useful only when it fails, so this wrapper captures both
# streams in a temporary log and re-emits that log on a non-zero exit only. A
# green step therefore stays silent, and a failure keeps every diagnostic line.
# A failure also leaves a beacon for `verify_cache.py --fail-fast` (below).
#
# usage: sh scripts/quiet-driver.sh COMMAND [ARG...]
set -u
log=$(mktemp "${TMPDIR:-/tmp}/selka-driver.XXXXXX") || exit 2
cleanup() { rm -f -- "$log"; }
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
"$@" >"$log" 2>&1
status=$?
if [ "$status" -ne 0 ]; then
  # `verify_cache.py --fail-fast` ends the build when a step leaves a beacon in the gate's telemetry directory: the end of
  # this log and the failed command, written whole under a dotted name and moved into place. Nothing else reads it.
  beacons=${SELKA_VERIFICATION_TELEMETRY_DIR:-}
  if [ -n "$beacons" ] && [ -d "$beacons" ]; then
    beacon=$(mktemp "$beacons/.fail-fast.XXXXXX" 2>/dev/null) &&
      { tail -n 200 -- "$log"; printf 'failed command: sh scripts/quiet-driver.sh %s\n' "$*"; } >"$beacon" 2>/dev/null &&
      mv -f -- "$beacon" "$beacons/fail-fast.driver.$$.txt" 2>/dev/null || rm -f -- "${beacon:-}"
  fi
  cat -- "$log" >&2
fi
exit "$status"

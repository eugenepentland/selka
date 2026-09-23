#!/usr/bin/env bash
# A `zig` stand-in for `mylang build --zig=`: forwards everything to the real
# zig, and asks for the loop vectorizer's optimization remarks:
#   - the LTO link (`zig ld.lld ... --lto-emit-asm`) writes $REMARKS_OUT;
#   - each unit's compile (`zig cc -c ... unit.ll`) writes $REMARKS_DIR/<unit>.yaml.
real=${REAL_ZIG:-$(command -v zig)}
if [ "$1" = "ld.lld" ] && [ -n "${REMARKS_OUT:-}" ]; then
  shift
  exec "$real" ld.lld --opt-remarks-filename "$REMARKS_OUT" --opt-remarks-passes "${REMARKS_PASSES:-loop-vectorize}" "$@"
fi
if [ "$1" = "cc" ] && [ -n "${REMARKS_DIR:-}" ]; then
  unit=""
  for arg in "$@"; do case "$arg" in *.ll) unit=$(basename "$arg" .ll) ;; esac; done
  if [ -n "$unit" ]; then
    shift
    mkdir -p "$REMARKS_DIR"
    exec "$real" cc -fsave-optimization-record=yaml -foptimization-record-file="$REMARKS_DIR/$unit.$$.yaml" -foptimization-record-passes="${REMARKS_PASSES:-loop-vectorize}" "$@"
  fi
fi
exec "$real" "$@"

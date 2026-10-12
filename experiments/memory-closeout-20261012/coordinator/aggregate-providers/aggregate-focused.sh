#!/usr/bin/env bash
set -euo pipefail
"$ZIG" build core-test-binary -p .tmp/memory-closeout/coordinator/aggregate-tests -Dtest-filter='aggregate provider' -Dtest-filter='zero RC provider' -Dtest-filter='provider lifetime' -j"$MYLANG_DEV_JOBS" --maxrss "$MYLANG_DEV_MAXRSS"
export MYLANG_COMPONENT_DIR="$PWD/.tmp/memory-closeout/coordinator/support5-install/libexec/mylang/components"
.tmp/memory-closeout/coordinator/aggregate-tests/focus/core-tests --guardian-filter='aggregate provider' --guardian-filter='zero RC provider' --guardian-filter='provider lifetime' --cache-dir=.zig-cache

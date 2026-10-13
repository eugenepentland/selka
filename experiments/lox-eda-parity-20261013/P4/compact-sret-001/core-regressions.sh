#!/usr/bin/env bash
set -euo pipefail
source /home/epentland/.config/mylang/dev-env.sh
export TMPDIR="$PWD/.tmp/lox-eda-parity/P4/compact-sret-001/tmp"
export ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/lox-eda-parity/P4/compact-sret-001/zig-cache-tests"
export MYLANG_COMPONENT_DIR="$PWD/.tmp/lox-eda-parity/P4/compact-sret-001/install/libexec/mylang/components"
"$ZIG" build core-test-binary --prefix .tmp/lox-eda-parity/P4/compact-sret-001/core-test-install -Dtest-filter=in-out -Dtest-filter='compact internal sret' -j4 --maxrss 8589934592
.tmp/lox-eda-parity/P4/compact-sret-001/core-test-install/focus/core-tests

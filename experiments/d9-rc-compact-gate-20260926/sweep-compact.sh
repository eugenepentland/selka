#!/bin/bash
set -euo pipefail
export TMPDIR="$PWD/.tmp-rc/tmp"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc"
test "$(git rev-parse HEAD)" = 7998e84cf7dfd3b74f0f2ff596714034dfc4b4fa
.tmp-rc/install-compact/bin/mylang test tests/lang --rc-runtime=stats --force --json --jobs 6 > .tmp-rc/compact-sweep-qbe.json 2> .tmp-rc/compact-sweep-qbe.log
.tmp-rc/install-compact/bin/mylang test tests/lang --rc-runtime=stats --force --json --jobs 6 --release > .tmp-rc/compact-sweep-llvm.json 2> .tmp-rc/compact-sweep-llvm.log
test "$(git rev-parse HEAD)" = 7998e84cf7dfd3b74f0f2ff596714034dfc4b4fa

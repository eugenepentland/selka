#!/bin/bash
set -euo pipefail
export TMPDIR="$PWD/.tmp-rc/tmp"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc"
test "$(git rev-parse HEAD)" = 78ac051c1e20e2580c2f5b2a8fae18abe6b46e85
.tmp-rc/install-inert-checker/bin/mylang test tests/lang --rc-runtime=stats --force --json --jobs 6 > .tmp-rc/inert-checker-sweep-qbe.json 2> .tmp-rc/inert-checker-sweep-qbe.log
.tmp-rc/install-inert-checker/bin/mylang test tests/lang --rc-runtime=stats --force --json --jobs 6 --release > .tmp-rc/inert-checker-sweep-llvm.json 2> .tmp-rc/inert-checker-sweep-llvm.log
test "$(git rev-parse HEAD)" = 78ac051c1e20e2580c2f5b2a8fae18abe6b46e85

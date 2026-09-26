#!/bin/bash
set -euo pipefail
export TMPDIR="$PWD/.tmp-rc/tmp"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc"
test "$(git rev-parse HEAD)" = dab80d845760ed3282322925203b8f0afb487d23
.tmp-rc/install-correctness/bin/mylang test tests/lang --rc-runtime=stats --force --json --jobs 6 > .tmp-rc/correctness-sweep-qbe.json 2> .tmp-rc/correctness-sweep-qbe.log
.tmp-rc/install-correctness/bin/mylang test tests/lang --rc-runtime=stats --force --json --jobs 6 --release > .tmp-rc/correctness-sweep-llvm.json 2> .tmp-rc/correctness-sweep-llvm.log
test "$(git rev-parse HEAD)" = dab80d845760ed3282322925203b8f0afb487d23

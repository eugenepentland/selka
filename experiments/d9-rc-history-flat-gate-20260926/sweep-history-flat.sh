#!/bin/bash
set -uo pipefail
export TMPDIR="$PWD/.tmp-rc/tmp"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc"
test "$(git rev-parse HEAD)" = 19e16e1d96112e9ccc741fa0c430ea97173a1032 || exit 2
test -f .tmp-rc/history-flat-build-ready || exit 2
status=0
for backend in qbe llvm; do
 flags=()
 test "$backend" != llvm || flags+=(--release)
 .tmp-rc/install-history-flat/bin/mylang test tests/lang --rc-runtime=stats --force --json --jobs 6 "${flags[@]}" > ".tmp-rc/history-flat-sweep-$backend.json" 2> ".tmp-rc/history-flat-sweep-$backend.log"
 result=$?
 echo "$backend $result"
 test "$result" = 0 || status=1
done
test "$(git rev-parse HEAD)" = 19e16e1d96112e9ccc741fa0c430ea97173a1032 || exit 2
exit "$status"

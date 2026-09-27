#!/bin/bash
set -uo pipefail
git diff --quiet HEAD || exit 2
export TMPDIR="$PWD/.tmp-rc/tmp"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc"
test "$(git rev-parse HEAD)" = a9eae92edb41f845a1caa9e8562cddd364117897 || exit 2
test -f .tmp-rc/plain-loan-hoist-build-ready || exit 2
status=0
for backend in qbe llvm; do
 flags=()
 test "$backend" != llvm || flags+=(--release)
 scripts/build-slot.sh build .tmp-rc/install-plain-loan-hoist/bin/mylang test tests/lang --rc-runtime=stats --force --json --jobs 6 "${flags[@]}" > ".tmp-rc/plain-loan-hoist-sweep-$backend.json" 2> ".tmp-rc/plain-loan-hoist-sweep-$backend.log"
 result=$?
 echo "$backend $result"
 test "$result" = 0 || status=1
done
test "$(git rev-parse HEAD)" = a9eae92edb41f845a1caa9e8562cddd364117897 || exit 2
git diff --quiet HEAD || exit 2
exit "$status"

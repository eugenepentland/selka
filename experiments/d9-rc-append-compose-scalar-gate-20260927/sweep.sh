#!/bin/bash
set -uo pipefail
git diff --quiet HEAD || exit 2
export TMPDIR="$PWD/.tmp-rc/tmp"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc"
test "$(git rev-parse HEAD)" = 468bd8e536b0e088ff71291cb9a3c92db8ebf448 || exit 2
test -f .tmp-rc/append-compose-scalar-build-ready || exit 2
status=0
for backend in qbe llvm; do
 flags=()
 test "$backend" != llvm || flags+=(--release)
 scripts/build-slot.sh build .tmp-rc/install-append-compose-scalar/bin/mylang test tests/lang --rc-runtime=stats --force --json --jobs 6 "${flags[@]}" > ".tmp-rc/append-compose-scalar-sweep-$backend.json" 2> ".tmp-rc/append-compose-scalar-sweep-$backend.log"
 result=$?
 echo "$backend $result"
 test "$result" = 0 || status=1
done
test "$(git rev-parse HEAD)" = 468bd8e536b0e088ff71291cb9a3c92db8ebf448 || exit 2
git diff --quiet HEAD || exit 2
exit "$status"

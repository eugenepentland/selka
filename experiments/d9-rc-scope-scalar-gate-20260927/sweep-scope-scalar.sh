#!/bin/bash
set -uo pipefail
export TMPDIR="$PWD/.tmp-rc/tmp"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc"
test "$(git rev-parse HEAD)" = 7d68202d59cf834bf9649fd77df2000f548ffec9 || exit 2
test -f .tmp-rc/scope-scalar-build-ready || exit 2
status=0
for backend in qbe llvm; do
 flags=()
 test "$backend" != llvm || flags+=(--release)
 scripts/build-slot.sh build .tmp-rc/install-scope-scalar/bin/mylang test tests/lang --rc-runtime=stats --force --json --jobs 6 "${flags[@]}" > ".tmp-rc/scope-scalar-sweep-$backend.json" 2> ".tmp-rc/scope-scalar-sweep-$backend.log"
 result=$?
 echo "$backend $result"
 test "$result" = 0 || status=1
done
test "$(git rev-parse HEAD)" = 7d68202d59cf834bf9649fd77df2000f548ffec9 || exit 2
exit "$status"

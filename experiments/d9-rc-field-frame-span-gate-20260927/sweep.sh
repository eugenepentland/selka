#!/bin/bash
set -uo pipefail
export TMPDIR="$PWD/.tmp-rc/tmp"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc"
test "$(git rev-parse HEAD)" = e926d1e13bf61ae3125102b46309225ca963a38d || exit 2
test -f .tmp-rc/field-frame-span-build-ready || exit 2
status=0
for backend in qbe llvm; do
 flags=()
 test "$backend" != llvm || flags+=(--release)
 scripts/build-slot.sh build .tmp-rc/install-field-frame-span/bin/mylang test tests/lang --rc-runtime=stats --force --json --jobs 6 "${flags[@]}" > ".tmp-rc/field-frame-span-sweep-$backend.json" 2> ".tmp-rc/field-frame-span-sweep-$backend.log"
 result=$?
 echo "$backend $result"
 test "$result" = 0 || status=1
done
test "$(git rev-parse HEAD)" = e926d1e13bf61ae3125102b46309225ca963a38d || exit 2
exit "$status"

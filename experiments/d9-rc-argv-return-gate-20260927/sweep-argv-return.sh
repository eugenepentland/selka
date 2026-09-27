#!/bin/bash
set -uo pipefail
export TMPDIR="$PWD/.tmp-rc/tmp"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc"
test "$(git rev-parse HEAD)" = 89e79524ef15e102c5f76e644e9bb97fbab0f3f8 || exit 2
test -f .tmp-rc/argv-return-build-ready || exit 2
status=0
for backend in qbe llvm; do
 flags=()
 test "$backend" != llvm || flags+=(--release)
 scripts/build-slot.sh build .tmp-rc/install-argv-return/bin/mylang test tests/lang --rc-runtime=stats --force --json --jobs 6 "${flags[@]}" > ".tmp-rc/argv-return-sweep-$backend.json" 2> ".tmp-rc/argv-return-sweep-$backend.log"
 result=$?
 echo "$backend $result"
 test "$result" = 0 || status=1
done
test "$(git rev-parse HEAD)" = 89e79524ef15e102c5f76e644e9bb97fbab0f3f8 || exit 2
exit "$status"

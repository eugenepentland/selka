#!/bin/bash
set -uo pipefail
export TMPDIR="$PWD/.tmp-rc/tmp"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc"
test "$(git rev-parse HEAD)" = 685e26311935cea0697726614a3897baff4f286f || exit 2
test -f .tmp-rc/nbody-build-ready || exit 2
status=0
for backend in qbe llvm; do
 flags=()
 test "$backend" != llvm || flags+=(--release)
 scripts/build-slot.sh build .tmp-rc/install-nbody/bin/mylang test tests/lang --rc-runtime=stats --force --json --jobs 6 "${flags[@]}" > ".tmp-rc/nbody-sweep-$backend.json" 2> ".tmp-rc/nbody-sweep-$backend.log"
 result=$?
 echo "$backend $result"
 test "$result" = 0 || status=1
done
test "$(git rev-parse HEAD)" = 685e26311935cea0697726614a3897baff4f286f || exit 2
exit "$status"

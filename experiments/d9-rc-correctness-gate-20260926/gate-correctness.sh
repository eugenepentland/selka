#!/bin/bash
set -uo pipefail
export TMPDIR="$PWD/.tmp-rc/tmp"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc"
d9_source_commit=dab80d845760ed3282322925203b8f0afb487d23
test "$(git rev-parse HEAD)" = "$d9_source_commit" || exit 2
scripts/build-slot.sh build zig build --summary all > .tmp-rc/correctness-final-build.log 2>&1 || exit $?
sha256sum zig-out/bin/mylang > .tmp-rc/correctness-compiler.sha256
status=0
for step in test test-qbe test-qbe-build fmt-check; do
 scripts/build-slot.sh gate zig build "$step" --summary all > ".tmp-rc/correctness-$step.log" 2>&1
 result=$?
 echo "$step $result"
 test "$result" = 0 || status=1
done
test "$(git rev-parse HEAD)" = "$d9_source_commit" || exit 2
exit "$status"

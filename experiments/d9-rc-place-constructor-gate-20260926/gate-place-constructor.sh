#!/bin/bash
set -uo pipefail
export TMPDIR="$PWD/.tmp-rc/tmp"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc"
d9_source_commit=2b42a543c4245b3bfe5dff863ac69779f45dc2b9
test "$(git rev-parse HEAD)" = "$d9_source_commit" || exit 2
scripts/build-slot.sh build zig build --summary all > .tmp-rc/place-constructor-final-build.log 2>&1 || exit $?
sha256sum zig-out/bin/mylang > .tmp-rc/place-constructor-compiler.sha256
mkdir -p .tmp-rc/install-place-constructor/bin
cp zig-out/bin/mylang zig-out/bin/qbe .tmp-rc/install-place-constructor/bin/
touch .tmp-rc/place-constructor-build-ready
status=0
for step in test test-qbe test-qbe-build fmt-check; do
 scripts/build-slot.sh gate zig build "$step" --summary all > ".tmp-rc/place-constructor-$step.log" 2>&1
 result=$?
 echo "$step $result"
 test "$result" = 0 || status=1
done
test "$(git rev-parse HEAD)" = "$d9_source_commit" || exit 2
exit "$status"

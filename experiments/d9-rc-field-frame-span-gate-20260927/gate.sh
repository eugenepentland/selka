#!/bin/bash
set -uo pipefail
export TMPDIR="$PWD/.tmp-rc/tmp"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc"
d9_source_commit=e926d1e13bf61ae3125102b46309225ca963a38d
test "$(git rev-parse HEAD)" = "$d9_source_commit" || exit 2
scripts/build-slot.sh build zig build --summary all > .tmp-rc/field-frame-span-final-build.log 2>&1 || exit $?
sha256sum zig-out/bin/mylang > .tmp-rc/field-frame-span-compiler.sha256
mkdir -p .tmp-rc/install-field-frame-span/bin
cp zig-out/bin/mylang zig-out/bin/qbe .tmp-rc/install-field-frame-span/bin/
touch .tmp-rc/field-frame-span-build-ready
status=0
for step in test test-qbe test-qbe-build fmt-check; do
 scripts/build-slot.sh gate zig build "$step" --summary all > ".tmp-rc/field-frame-span-$step.log" 2>&1
 result=$?
 echo "$step $result"
 test "$result" = 0 || status=1
done
test "$(git rev-parse HEAD)" = "$d9_source_commit" || exit 2
exit "$status"

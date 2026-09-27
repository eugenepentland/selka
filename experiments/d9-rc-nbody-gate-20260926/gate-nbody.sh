#!/bin/bash
set -uo pipefail
export TMPDIR="$PWD/.tmp-rc/tmp"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc"
d9_source_commit=685e26311935cea0697726614a3897baff4f286f
test "$(git rev-parse HEAD)" = "$d9_source_commit" || exit 2
scripts/build-slot.sh build zig build --summary all > .tmp-rc/nbody-final-build.log 2>&1 || exit $?
sha256sum zig-out/bin/mylang > .tmp-rc/nbody-compiler.sha256
mkdir -p .tmp-rc/install-nbody/bin
cp zig-out/bin/mylang zig-out/bin/qbe .tmp-rc/install-nbody/bin/
touch .tmp-rc/nbody-build-ready
status=0
for step in test test-qbe test-qbe-build fmt-check; do
 scripts/build-slot.sh gate zig build "$step" --summary all > ".tmp-rc/nbody-$step.log" 2>&1
 result=$?
 echo "$step $result"
 test "$result" = 0 || status=1
done
test "$(git rev-parse HEAD)" = "$d9_source_commit" || exit 2
exit "$status"

#!/bin/bash
set -uo pipefail
git diff --quiet HEAD || exit 2
export TMPDIR="$PWD/.tmp-rc/tmp"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc"
d9_source_commit=468bd8e536b0e088ff71291cb9a3c92db8ebf448
test "$(git rev-parse HEAD)" = "$d9_source_commit" || exit 2
scripts/build-slot.sh build zig build --summary all > .tmp-rc/append-compose-scalar-final-build.log 2>&1 || exit $?
sha256sum zig-out/bin/mylang > .tmp-rc/append-compose-scalar-compiler.sha256
mkdir -p .tmp-rc/install-append-compose-scalar/bin
cp zig-out/bin/mylang zig-out/bin/qbe .tmp-rc/install-append-compose-scalar/bin/
touch .tmp-rc/append-compose-scalar-build-ready
status=0
for step in test test-qbe test-qbe-build fmt-check; do
 scripts/build-slot.sh gate zig build "$step" --summary all > ".tmp-rc/append-compose-scalar-$step.log" 2>&1
 result=$?
 echo "$step $result"
 test "$result" = 0 || status=1
done
test "$(git rev-parse HEAD)" = "$d9_source_commit" || exit 2
git diff --quiet HEAD || exit 2
exit "$status"

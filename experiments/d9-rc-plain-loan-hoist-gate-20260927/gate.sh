#!/bin/bash
set -uo pipefail
git diff --quiet HEAD || exit 2
export TMPDIR="$PWD/.tmp-rc/tmp"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc"
d9_source_commit=a9eae92edb41f845a1caa9e8562cddd364117897
test "$(git rev-parse HEAD)" = "$d9_source_commit" || exit 2
scripts/build-slot.sh build zig build --summary all > .tmp-rc/plain-loan-hoist-final-build.log 2>&1 || exit $?
sha256sum zig-out/bin/mylang > .tmp-rc/plain-loan-hoist-compiler.sha256
mkdir -p .tmp-rc/install-plain-loan-hoist/bin
cp zig-out/bin/mylang zig-out/bin/qbe .tmp-rc/install-plain-loan-hoist/bin/
touch .tmp-rc/plain-loan-hoist-build-ready
status=0
for step in test test-qbe test-qbe-build fmt-check; do
 scripts/build-slot.sh gate zig build "$step" --summary all > ".tmp-rc/plain-loan-hoist-$step.log" 2>&1
 result=$?
 echo "$step $result"
 test "$result" = 0 || status=1
done
test "$(git rev-parse HEAD)" = "$d9_source_commit" || exit 2
git diff --quiet HEAD || exit 2
exit "$status"

#!/bin/bash
set -uo pipefail
export TMPDIR="$PWD/.tmp-rc/tmp"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc"
test "$(git rev-parse HEAD)" = 2ca89942c797df18af5856ec55a76c34cc372127 || exit 2
git diff --quiet HEAD || exit 2
status=0
for step in test test-qbe test-qbe-build fmt-check; do
 scripts/build-slot.sh gate zig build "$step" --summary all > ".tmp-rc/runtime-docs-$step.log" 2>&1
 result=$?
 echo "$step $result"
 test "$result" = 0 || status=1
done
test "$(git rev-parse HEAD)" = 2ca89942c797df18af5856ec55a76c34cc372127 || exit 2
git diff --quiet HEAD || exit 2
exit "$status"

#!/bin/bash
set -uo pipefail
git diff --quiet HEAD || exit 2
export TMPDIR="$PWD/.tmp-rc/tmp"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc"
d9_source_commit="${1:?frozen source commit required}"
test "$(git rev-parse HEAD)" = "$d9_source_commit" || exit 2
test ! -e .tmp-rc/install-readers-joined/bin/mylang || exit 2
scripts/build-slot.sh build zig build --summary all > .tmp-rc/readers-joined-final-build.log 2>&1 || exit $?
sha256sum zig-out/bin/mylang > .tmp-rc/readers-joined-compiler.sha256
mkdir -p .tmp-rc/install-readers-joined/bin
cp zig-out/bin/mylang zig-out/bin/qbe .tmp-rc/install-readers-joined/bin/
touch .tmp-rc/readers-joined-build-ready
status=0
for step in test test-qbe test-qbe-build fmt-check; do
 scripts/build-slot.sh gate zig build "$step" --summary all > ".tmp-rc/readers-joined-$step.log" 2>&1
 result=$?
 echo "$step $result"
 test "$result" = 0 || status=1
done
test "$(git rev-parse HEAD)" = "$d9_source_commit" || exit 2
git diff --quiet HEAD || exit 2
exit "$status"

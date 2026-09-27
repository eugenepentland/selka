#!/bin/bash
set -uo pipefail
git diff --quiet HEAD || exit 2
export TMPDIR="$PWD/.tmp-rc/tmp"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc"
d9_source_commit=636524b81562e30285b15e297078fac24ffccb58
test "$(git rev-parse HEAD)" = "$d9_source_commit" || exit 2
scripts/build-slot.sh build zig build --summary all > .tmp-rc/flat-borrow-loops-final-build.log 2>&1 || exit $?
sha256sum zig-out/bin/mylang > .tmp-rc/flat-borrow-loops-compiler.sha256
mkdir -p .tmp-rc/install-flat-borrow-loops/bin
cp zig-out/bin/mylang zig-out/bin/qbe .tmp-rc/install-flat-borrow-loops/bin/
touch .tmp-rc/flat-borrow-loops-build-ready
status=0
for step in test test-qbe test-qbe-build fmt-check; do
 scripts/build-slot.sh gate zig build "$step" --summary all > ".tmp-rc/flat-borrow-loops-$step.log" 2>&1
 result=$?
 echo "$step $result"
 test "$result" = 0 || status=1
done
test "$(git rev-parse HEAD)" = "$d9_source_commit" || exit 2
git diff --quiet HEAD || exit 2
exit "$status"

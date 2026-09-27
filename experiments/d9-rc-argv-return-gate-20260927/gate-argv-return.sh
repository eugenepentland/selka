#!/bin/bash
set -uo pipefail
export TMPDIR="$PWD/.tmp-rc/tmp"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc"
d9_source_commit=89e79524ef15e102c5f76e644e9bb97fbab0f3f8
test "$(git rev-parse HEAD)" = "$d9_source_commit" || exit 2
scripts/build-slot.sh build zig build --summary all > .tmp-rc/argv-return-final-build.log 2>&1 || exit $?
sha256sum zig-out/bin/mylang > .tmp-rc/argv-return-compiler.sha256
mkdir -p .tmp-rc/install-argv-return/bin
cp zig-out/bin/mylang zig-out/bin/qbe .tmp-rc/install-argv-return/bin/
touch .tmp-rc/argv-return-build-ready
status=0
for step in test test-qbe test-qbe-build fmt-check; do
 scripts/build-slot.sh gate zig build "$step" --summary all > ".tmp-rc/argv-return-$step.log" 2>&1
 result=$?
 echo "$step $result"
 test "$result" = 0 || status=1
done
test "$(git rev-parse HEAD)" = "$d9_source_commit" || exit 2
exit "$status"

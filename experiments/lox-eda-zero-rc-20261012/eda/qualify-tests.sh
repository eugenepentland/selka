#!/usr/bin/env bash
set -euo pipefail
# Invoke through scripts/build-slot.sh build; this script does not take another lease.
compiler=${1:?frozen compiler path required}
root=$(cd "$(dirname "$0")/../../.." && pwd)
eda="$root/experiments/lox-eda-zero-rc-20261012/eda"
work="$root/.tmp/lox-eda-20261012/eda"
mkdir -p "$work" "$eda/evidence"
export TMPDIR="$work"
MYL_CORE_LEAKCHECK=1 "$compiler" test "$eda/original/src" --release --verify-facts --jobs 4 --max-steps 1000000000 --max-frames 40000 --max-memory 2G --timeout-ms 120000 --cache-dir "$work/test-original" --json > "$eda/evidence/test-original-release.json" 2> "$eda/evidence/test-original-release.stderr"
MYL_CORE_LEAKCHECK=1 "$compiler" test "$eda/source/src" --experimental-zero-rc --release --verify-facts --jobs 4 --max-steps 1000000000 --max-frames 40000 --max-memory 2G --timeout-ms 120000 --cache-dir "$work/test-zero-release" --json > "$eda/evidence/test-zero-release.json" 2> "$eda/evidence/test-zero-release.stderr"
MYL_CORE_LEAKCHECK=1 "$compiler" test "$eda/source/src" --experimental-zero-rc --jobs 4 --max-steps 1000000000 --max-frames 40000 --max-memory 2G --timeout-ms 120000 --cache-dir "$work/test-zero-debug" --json > "$eda/evidence/test-zero-debug.json" 2> "$eda/evidence/test-zero-debug.stderr"

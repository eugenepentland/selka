#!/usr/bin/env bash
set -euo pipefail
# Invoke inside one scripts/build-slot.sh build lease after source freeze.
compiler=${1:?frozen installed compiler path required}
eda=$(cd "$(dirname "$0")" && pwd)
workspace=$(cd "$eda/../../.." && pwd)
work="$workspace/.tmp/lox-eda-20261012/eda/final"
mkdir -p "$work" "$eda/evidence/final"
export TMPDIR="$work"
for arm in original-rc migrated-rc zero-rc; do
    entry="$eda/source/src/main.my"
    flags=()
    if [[ $arm == original-rc ]]; then entry="$eda/original/src/main.my"; fi
    if [[ $arm == zero-rc ]]; then flags=(--experimental-zero-rc); fi
    "$compiler" build "$entry" --release "${flags[@]}" --cache-dir "$work/cache-$arm" --emit-llvm "$work/$arm.ll" -o "$work/$arm" > "$eda/evidence/final/build-$arm.log" 2>&1
    "$compiler" build "$entry" --release "${flags[@]}" --counters --cache-dir "$work/cache-$arm-count" -o "$work/$arm-count" > "$eda/evidence/final/build-$arm-count.log" 2>&1
done
"$compiler" build "$eda/source/src/main.my" --experimental-zero-rc --release --verify-facts --cache-dir "$work/cache-zero-verified" -o "$work/zero-verified" > "$eda/evidence/final/build-zero-verified.log" 2>&1
"$compiler" build "$eda/source/src/main.my" --experimental-zero-rc --optimize-debug --cache-dir "$work/cache-zero-debug" -o "$work/zero-debug" > "$eda/evidence/final/build-zero-debug.log" 2>&1
sha256sum "$work"/{original-rc,migrated-rc,zero-rc,original-rc-count,migrated-rc-count,zero-rc-count,zero-verified,zero-debug} > "$eda/evidence/final/binary-sha256.txt"

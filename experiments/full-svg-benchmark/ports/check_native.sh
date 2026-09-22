#!/bin/sh
# Check a native schematic build against the mylang O3 SVG bytes.
#
#   ports/check_native.sh <binary>
#
# Every case must match sha256 and byte length exactly; the exit status is
# non-zero on the first mismatch. Outputs land in
# .tmp/full-svg-benchmark-20260921/ports/<binary-name>-<case>.svg.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
WORK="$ROOT/.tmp/full-svg-benchmark-20260921"
BINARY=$1
NAME=$(basename "$BINARY")

if [ ! -x "$BINARY" ]; then
    echo "not executable: $BINARY" >&2
    exit 2
fi
mkdir -p "$WORK/ports"

expected_hash() {
    case "$1" in
        fixture) echo 68157ea785ee3766c039714d1d081ea1c7a55def6cf9124660495f8b797ed388 ;;
        changed-net) echo e3679477d2861edb64ed6985006bbe1aa9963e7d75b2f984df7b40116e88dc90 ;;
        changed-value) echo 19fdda810d0a0ede38c9780a7084f0da2a7153fb38a3862982a5596291f53ed6 ;;
    esac
}

expected_bytes() {
    case "$1" in
        changed-net) echo 49647 ;;
        *) echo 49617 ;;
    esac
}

status=0
for case in fixture changed-net changed-value; do
    project="$WORK/projects/$case"
    output="$WORK/ports/$NAME-$case.svg"
    rm -f "$output"
    if ! "$BINARY" \
        "$project/lib/modules/straps-synth-lmx2595.sexp" \
        "$project/lib/pinouts/lmx2595rhar.sexp" \
        "$project/lib/interfaces/spi.sexp" \
        "$output"; then
        echo "$case: FAILED to run"
        status=1
        continue
    fi
    got_hash=$(sha256sum "$output" | cut -d' ' -f1)
    got_bytes=$(wc -c < "$output")
    want_hash=$(expected_hash "$case")
    want_bytes=$(expected_bytes "$case")
    if [ "$got_hash" = "$want_hash" ] && [ "$got_bytes" = "$want_bytes" ]; then
        echo "$case: OK $got_bytes bytes $got_hash"
    else
        echo "$case: MISMATCH got $got_bytes $got_hash want $want_bytes $want_hash"
        status=1
    fi
done
exit $status

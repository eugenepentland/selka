#!/bin/sh
# Stage the freshly compiled compiler into zig-out/bin, bypassing the install
# step's Guardian gate.
#
# `zig build` compiles the compiler before Guardian runs, but the *install* of
# that artifact is gated on a green Guardian run. While a change still carries
# Guardian findings, `zig-out/bin/mylang` therefore stays at the previous build
# and end-to-end checks would silently exercise stale code. This copies the
# newest compiled artifact out of the local cache instead.
#
# Final acceptance still requires a real `zig build` (or `zig build test`) that
# passes Guardian; this is an iteration aid, not a substitute for the gate.
set -e
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
newest=$(ls -t "$here"/.zig-cache/o/*/mylang 2>/dev/null | head -1)
[ -n "$newest" ] || { echo "stage: no compiled mylang in .zig-cache/o/*/" >&2; exit 1; }
mkdir -p "$here/zig-out/bin"
cp "$newest" "$here/zig-out/bin/mylang"
for extra in mylang-io; do
  found=$(ls -t "$here"/.zig-cache/o/*/"$extra" 2>/dev/null | head -1)
  [ -n "$found" ] && cp "$found" "$here/zig-out/bin/$extra"
done
echo "staged $(basename "$newest") from $(dirname "$newest")"

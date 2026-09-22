#!/usr/bin/env bash
# Rebuild one compact-o3 arm two ways from its already-translated guest module:
#   zlink: same objects, linked by `zig cc` (no LTO) — the linker/layout control
#   lto:   guest module + every runtime C unit as bitcode, one LTO unit at O3
# The arm's `--wrap` shim is replaced by renaming the seven wrapped callees in the
# guest IR to their `__wrap_` entry points and pointing `__real_` at the originals,
# because this toolchain's linker rejects --wrap.
#   lto.sh <arm-dir (maxperf/compact-o3)> <out-dir> <formatter.o> <common.o>...
set -euo pipefail
cd /home/epentland/ai/canopy/mylang
D="$1"; OUT="$2"; FORMATTER="$3"; shift 3; COMMON=("$@")
mkdir -p "$OUT"
UNITS="qbe_runtime.c arena_heap.c native_collections.c native_text.c native_dictionary.c qbe_stack.c qbe_providers.c qbe_resources.c native_equal.c native_bytes.c qbe_bytes.c native_regions.c qbe_arena.c native_print.c qbe_io.c native_scoped.c qbe_grants.c qbe_files.c native_text_methods.c"
WRAPPED='myl_native_list_append|myl_native_list_get|myl_native_text_at|myl_native_text_slice|myl_qbe_int_binary|myl_qbe_int_cast|myl_qbe_int_neg'
sed -E "s/@($WRAPPED)\(/@__wrap_\1(/g" "$D/000.ll" > "$OUT/guest.ll"
sed -E 's/__real_(myl_[A-Za-z0-9_]+)/\1/g' "$D/runtime/unchecked_runtime.c" > "$OUT/unchecked_runtime.c"
CFLAGS=(-std=c11 -O2 -fPIC -g0 -fno-ident -ffunction-sections -fdata-sections -DMYL_MAXPERF_ARENA_COMPACT -I "$D/runtime")
for mode in zlink lto; do
  M="$OUT/$mode"; mkdir -p "$M"
  LTO=(); [ "$mode" = lto ] && LTO=(-flto)
  zig cc "${LTO[@]}" -O3 -fPIC -g0 -c "$OUT/guest.ll" -o "$M/guest.o"
  zig cc "${LTO[@]}" "${CFLAGS[@]}" -c "$OUT/unchecked_runtime.c" -o "$M/unchecked.o"
  OBJS=("$M/guest.o" "$M/unchecked.o")
  for u in $UNITS; do
    zig cc "${LTO[@]}" "${CFLAGS[@]}" -c "$D/runtime/$u" -o "$M/rt-${u%.c}.o"
    OBJS+=("$M/rt-${u%.c}.o")
  done
  zig cc "${LTO[@]}" -O3 -no-pie "${OBJS[@]}" "${COMMON[@]}" "$FORMATTER" -lm -Wl,--gc-sections -o "$M/arm.bin"
  echo "built $mode: $M/arm.bin ($(stat -c %s "$M/arm.bin") bytes)"
done

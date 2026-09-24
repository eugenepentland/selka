#!/usr/bin/env bash
# zig wrapper: logs every invocation; injects LTO remark flags into ld.lld when ZW_REMARKS is set,
# and with ZW_SAVE copies the LTO temps (preopt/opt bitcode, final asm) into ZW_KEEP.
echo "$*" >> "${ZW_LOG:-/dev/null}"
if [ "$1" = "ld.lld" ] && [ -n "$ZW_REMARKS" ]; then
  shift
  extra=(--opt-remarks-filename "$ZW_REMARKS" --opt-remarks-passes "${ZW_PASSES:-loop-vectorize|licm|gvn|slp-vectorizer|loop-unroll}")
  [ -n "$ZW_SAVE" ] && extra+=(--save-temps)
  [ -n "$ZW_MLLVM" ] && for f in $ZW_MLLVM; do extra+=(-mllvm "$f"); done
  base=""; prev=""
  for a in "$@"; do [ "$prev" = "-o" ] && base=$a; prev=$a; done
  "${ZW_ZIG:-$(command -v zig)}" ld.lld "${extra[@]}" "$@"; rc=$?
  if [ -n "$ZW_SAVE" ] && [ -n "$ZW_KEEP" ] && [ -n "$base" ]; then
    mkdir -p "$ZW_KEEP"; cp "$base".* "$ZW_KEEP"/ 2>/dev/null
  fi
  exit $rc
fi
exec "${ZW_ZIG:-$(command -v zig)}" "$@"

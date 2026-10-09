#!/usr/bin/env bash
# PM-1 identity check: with counting off, the PM-1 compiler emits the same LLVM text
# (release and debug) and links the same release executable as the base compiler.
# usage: llvm_identity.sh BASE_MYLANG NEW_MYLANG WORKDIR PROGRAM.my...
set -u
base=$1 new=$2 work=$3; shift 3
mkdir -p "$work"
same=0 differ=0
for program in "$@"; do
  name=$(echo "$program" | sed 's#.*/\([^/]*\)/\([^/]*\)\.my$#\1_\2#')
  dir=$(dirname "$program")
  for mode in release debug; do
    flag=""; [ $mode = release ] && flag="--release"
    for side in base new; do
      compiler=$base; [ $side = new ] && compiler=$new
      (cd "$dir" && "$compiler" build "$program" -o "$work/$name.$mode.$side" $flag --emit-llvm "$work/$name.$mode.$side.ll" --cache-dir "$work/cache-$side" --no-cache >/dev/null 2>"$work/$name.$mode.$side.err") || echo "BUILD-FAIL $side $mode $program"
    done
    if cmp -s "$work/$name.$mode.base.ll" "$work/$name.$mode.new.ll"; then llvm=same; else llvm=DIFFER; fi
    if cmp -s "$work/$name.$mode.base" "$work/$name.$mode.new"; then exe=same; else exe=DIFFER; fi
    [ $llvm = same ] && same=$((same+1)) || differ=$((differ+1))
    echo "$mode $program llvm=$llvm bytes=$(wc -c < "$work/$name.$mode.new.ll") exe=$exe sha=$(sha256sum < "$work/$name.$mode.new" | cut -c1-16)"
  done
done
echo "SUMMARY llvm_same=$same llvm_differ=$differ"

#!/usr/bin/env bash
# census_build.sh TAG — build every suite + micro kernel with the worktree adapter into .tmp/census-TAG/<name>,
# keeping LTO remarks, temps and the disassembled post-LTO IR (opt.ll).
WT=$(cd "$(dirname "$0")/../.." && pwd)
tag=$1; shift
names=${NAMES:-"$(cd $WT/bench/parity && ls suite/*.my micro/*.my | grep -v -E '_(tuned|arena|class|flat|array|keyed|sorted|wrapping)\.my$')"}
one() {
  src=$1; shift; name=$(basename "$src" .my)
  out=$WT/.tmp/census-$tag/$name
  rm -rf "$out"; mkdir -p "$out"
  if "$WT/experiments/vectorizer-blockers-20260923/rbuild.sh" "$out" "bench/parity/$src" "$@" > "$out/build.log" 2>&1; then
    zig cc -S -emit-llvm -Xclang -disable-llvm-passes "$out/lto/program-lto.0.4.opt.bc" -o "$out/opt.ll" 2>/dev/null
    zig cc -S -emit-llvm -Xclang -disable-llvm-passes "$out/lto/program-lto.0.2.internalize.bc" -o "$out/pre.ll" 2>/dev/null
    rm -rf "$out/cache/runtime"
    echo "ok $name"
  else
    echo "FAIL $name"; tail -5 "$out/build.log"
  fi
}
export -f one; export WT tag
printf '%s\n' $names | xargs -P 4 -I{} bash -c 'one "$@"' _ {} "$@"

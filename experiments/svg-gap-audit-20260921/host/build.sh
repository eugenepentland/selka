#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
work="$root/.tmp/svg-gap-audit-20260921/host"
compiler="$root/.tmp/svg-gap-audit-20260921/mylang-audit-compiler"
adapter="$root/experiments/llvm-backend/qbe_llvm.py"
guest="$work/guest/main.my"
mkdir -p "$work"
for arm in control counts unchecked memory-output; do
  "$compiler" build "$guest" --project \
    --provider "$root/experiments/svg-gap-audit-20260921/host/native_${arm//-/_}.c" \
    --backend llvm --llvm-adapter "$adapter" --llvm-opt 3 --lto --keep-symbols \
    --cache-dir "$work/cache-$arm" --report -o "$work/$arm" \
    >"$work/$arm-build.json" 2>"$work/$arm-build.stderr"
done
python3 "$root/experiments/svg-gap-audit-20260921/host/record.py"
python3 "$root/experiments/svg-gap-audit-20260921/host/build_typed.py"

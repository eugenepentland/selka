#!/usr/bin/env bash
# Apply the value-AST migration to the pinned T2 calculator source.
# usage: apply-t2.sh ORIGINAL_CALC_MY OUTPUT_DIR
set -euo pipefail
source_file=${1:?pass the original T2 calc.my}
output_dir=${2:?pass an output directory}
expected=698c7bcd77b99431b24871f6ed6c8c325a024745619f380f0be51ddc9c044719
actual=$(sha256sum "$source_file" | cut -d' ' -f1)
[[ "$actual" == "$expected" ]] || { echo "T2 source hash differs from pinned input" >&2; exit 2; }
script_dir=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$output_dir"
cp "$source_file" "$output_dir/calc.my"
(cd "$output_dir" && patch -p1 < "$script_dir/t2-calc.patch")

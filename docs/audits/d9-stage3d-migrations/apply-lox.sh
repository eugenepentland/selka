#!/usr/bin/env bash
# Reconstruct the pinned P3 Lox port and migrate its heap carriers to values.
# usage: apply-lox.sh WORK_DIRECTORY [--optimized]
# Result: WORK_DIRECTORY/lox/benchmarks/lox/ports/mylang and WORK_DIRECTORY/lox/bench.
set -euo pipefail
work=${1:?pass an empty scratch work directory}
optimization=${2:-}
if [[ -n "$optimization" && "$optimization" != --optimized ]]; then
    echo "unknown option: $optimization" >&2
    exit 2
fi
script_dir=$(cd "$(dirname "$0")" && pwd)
repo=$(git -C "$script_dir" rev-parse --show-toplevel)
port="$work/lox/benchmarks/lox/ports/mylang"
if [[ -e "$work/lox" ]]; then
    echo "refusing to overwrite existing $work/lox" >&2
    exit 2
fi
mkdir -p "$work"
"$repo/experiments/perf-gc-dict-20260925/scripts/prepare_lox.sh" "$work"
(cd "$port" && sha256sum -c "$script_dir/lox-base-sha256.txt" >/dev/null)
(cd "$port" && patch --batch -p1 < "$script_dir/lox-value-port.patch")
if [[ "$optimization" == --optimized ]]; then
    (cd "$port" && patch --batch -p1 < "$script_dir/lox-source-perf.patch")
    (cd "$port" && patch --batch -p1 < "$script_dir/lox-runtime-perf-20261002.patch")
    (cd "$port" && patch --batch --fuzz=0 -p1 < "$script_dir/lox-runtime-perf-20261003.patch")
    (cd "$port" && patch --batch --fuzz=0 -p1 < "$script_dir/lox-runtime-perf-20261003-callee-table.patch")
fi

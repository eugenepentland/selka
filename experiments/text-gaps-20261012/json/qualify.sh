#!/usr/bin/env bash
# Invoke through scripts/build-slot.sh build; this script does not acquire a slot.
set -euo pipefail
cd "$(dirname "$0")/../../.."
stage="${1:?candidate stage required}"
compiler="${2:?complete installation compiler required}"
export MYL_CORE_LEAKCHECK=1
export MYLANG_COMPONENT_DIR="$(dirname "$compiler")/../libexec/mylang/components"
evidence="$PWD/experiments/text-gaps-20261012/json"
private="$PWD/.tmp/text-gaps/json"
mkdir -p "$private"
for mode in '--unoptimized' '' '--release --verify-facts' '--experimental-zero-rc --unoptimized' '--experimental-zero-rc --release --verify-facts' '--experimental-zero-rc --release' '--experimental-zero-rc --optimize-debug' '--experimental-zero-rc --release --no-facts'; do
    read -r -a flags <<< "$mode"
    for source in tests/lang/standard_json.my tests/lang/textgap_json.my tests/lang/textgap_json_copy.my tests/lang/textgap_json_dict.my; do
        "$compiler" test "$source" "${flags[@]}" --cache-dir "$private/test-cache-$stage" --json
    done
done
source="$PWD/experiments/micro-ownership-20261012/expanded/migrated/text.my"
common=(--release --experimental-zero-rc --link "$PWD/benchmarks/runtime/ports/native_clock.c")
"$compiler" build "$source" -o "$private/text-$stage-count" "${common[@]}" --counters --cache-dir "$private/guest-cache-$stage-count" --emit-llvm "$private/candidate-$stage-count.ll"
MYLANG_COUNTERS="$evidence/candidate-$stage-counts.json" "$private/text-$stage-count" json_transform 256 1 42
"$compiler" build "$source" -o "$private/text-$stage-runtime" "${common[@]}" --cache-dir "$private/guest-cache-$stage" --emit-llvm "$private/candidate-$stage.ll"

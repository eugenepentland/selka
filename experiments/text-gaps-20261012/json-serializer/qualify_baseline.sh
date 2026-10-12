#!/usr/bin/env bash
# Acquire one shared build slot outside this script.
set -euo pipefail
cd "$(dirname "$0")/../../.."
compiler="${1:?compiler required}"
private="$PWD/.tmp/text-gaps/json-serializer/baseline"
export MYLANG_COMPONENT_DIR="$(dirname "$compiler")/../libexec/mylang/components"
export MYL_CORE_LEAKCHECK=1
for mode in '--unoptimized' '' '--release --verify-facts' '--experimental-zero-rc --unoptimized' '--experimental-zero-rc --release --verify-facts' '--experimental-zero-rc --release' '--experimental-zero-rc --optimize-debug' '--experimental-zero-rc --release --no-facts'; do
    read -r -a flags <<< "$mode"
    for source in tests/lang/textgap_json_serializer.my; do
        "$compiler" test "$source" "${flags[@]}" --cache-dir "$private/test-cache" --json
    done
done

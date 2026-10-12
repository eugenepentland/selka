#!/bin/bash
set -euo pipefail
# Invoke under scripts/build-slot.sh build after sourcing dev-env.sh.
export MYLANG_COMPONENT_DIR=/home/epentland/ai/canopy/mylang-memory-20261012-verify-02/zig-out/libexec/mylang/components
probe=experiments/lox-eda-zero-rc-20261012/provider
for mode in unoptimized optimize-debug release release-no-facts release-facts debug-facts; do
    case "$mode" in
      unoptimized) flags=(--unoptimized);;
      optimize-debug) flags=(--optimize-debug);;
      release) flags=(--release);;
      release-no-facts) flags=(--release --no-facts);;
      release-facts) flags=(--release --verify-facts);;
      debug-facts) flags=(--optimize-debug --verify-facts);;
    esac
    zig-out/focus/mylang build "$probe/optional_clock_native.my" -o "$probe/optional-clock-$mode" --experimental-zero-rc --emit-llvm "$probe/optional-clock-$mode.ll" --cache-dir .tmp/optional-clock-native-cache "${flags[@]}" > "$probe/$mode-build.stdout" 2> "$probe/$mode-build.stderr"
    MYL_CORE_LEAKCHECK=1 "$probe/optional-clock-$mode" > "$probe/$mode-run.stdout" 2> "$probe/$mode-run.stderr"
    test ! -s "$probe/$mode-run.stderr"
    printf '%s passed\n' "$mode"
done

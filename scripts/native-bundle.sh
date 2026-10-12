#!/usr/bin/env bash
# Run the compiler in the reviewed native runtime; provisioning alone uses Python.
set -euo pipefail
if [[ $# -lt 5 || $5 != -- ]]; then
    echo "usage: $0 BUNDLE ZIG_DIRECTORY COMPILER PROJECT -- MYLANG_ARGUMENTS..." >&2
    exit 2
fi
bundle=$(realpath -- "$1")
toolchain=$(realpath -- "$2")
compiler=$(realpath -- "$3")
project=$(realpath -- "$4")
shift 5
[[ -d $bundle/rootfs && -d $project && -x $compiler && -x $toolchain/zig ]] || exit 2
[[ $("$toolchain/zig" version) == 0.17.0-dev.1683+5ceec001b ]] || {
    echo 'native-bundle: the repository-pinned Zig is required' >&2
    exit 2
}
mkdir -p -- "$project/.selka-native/tmp" "$project/.selka-native/zig-global" "$project/.selka-native/zig-local" "$project/.selka-native/runtime"
component_args=()
components=$(dirname -- "$compiler")/../libexec/mylang/components
if [[ -d $components ]]; then
    component_args=(--ro-bind "$(realpath -- "$components")" /opt/selka/components --setenv MYLANG_COMPONENT_DIR /opt/selka/components)
fi
# The root contains no host /etc, /lib or /usr. Fixed mount destinations preserve
# the reviewed absent sibling resources. The project is the only writable bind.
# Other inherited environment remains visible to Core's fail-closed override
# checks; this wrapper does not turn an unsafe environment into cache approval.
exec bwrap --unshare-user --die-with-parent \
    --ro-bind "$bundle/rootfs" / \
    --ro-bind "$toolchain" /opt/selka/toolchain \
    --ro-bind "$compiler" /opt/selka/mylang \
    "${component_args[@]}" \
    --bind "$project" /work --chdir /work \
    --proc /proc --dev /dev \
    --setenv PATH /opt/selka/toolchain:/usr/bin \
    --setenv ZIG /opt/selka/toolchain/zig \
    --setenv MYLANG_ZIG /opt/selka/toolchain/zig \
    --setenv XDG_CACHE_HOME /work/.selka-native/cache \
    --setenv ZIG_GLOBAL_CACHE_DIR /work/.selka-native/zig-global \
    --setenv ZIG_LOCAL_CACHE_DIR /work/.selka-native/zig-local \
    --setenv TMPDIR /work/.selka-native/tmp \
    --setenv MYLANG_CORE_RUNTIME_CACHE /work/.selka-native/runtime \
    -- /opt/selka/mylang "$@"

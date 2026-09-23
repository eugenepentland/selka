#!/bin/sh
# Build stage 0 in this worktree and install it into the shared,
# content-addressed stage-0 cache.
#
# The cache directory is derived from the mylang binary's sha256, so a rebuild
# that changes the compiler lands at a *new* path.  The runnable tool set is
# installed together: `mylang` resolves `qbe` beside itself, so the same
# content-addressed directory carries the matching `qbe`.  This script never
# overwrites an existing artifact with different bytes and never rewrites
# selfhost/stage0-pin.json: a new binary requires the operator to run
# selfhost/tools/pin-stage0.sh explicitly.
#
# Set MYLANG_STAGE0_CACHE to relocate the shared cache (default
# ~/.cache/mylang/stage0/<sha256>/mylang).
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root_dir=$(CDPATH='' cd -- "$script_dir/../.." && pwd)
binary="$root_dir/zig-out/bin/mylang"
qbe_binary="$root_dir/zig-out/bin/qbe"
pin_file="$root_dir/selfhost/stage0-pin.json"

install_artifact() {
    src=$1
    dst=$2
    name=$3
    src_sha=$(sha256sum "$src" | awk '{print $1}')
    if [ -e "$dst" ]; then
        existing=$(sha256sum "$dst" | awk '{print $1}')
        if [ "$existing" != "$src_sha" ]; then
            echo "build-stage0: refusing to overwrite $dst: it has sha256 $existing but the freshly built $name is $src_sha" >&2
            exit 1
        fi
        echo "build-stage0: $name already installed: $dst"
        return 0
    fi
    dst_dir=$(dirname -- "$dst")
    mkdir -p "$dst_dir"
    tmp="$dst.tmp.$$"
    cp "$src" "$tmp"
    chmod 755 "$tmp"
    if [ -e "$dst" ]; then
        existing=$(sha256sum "$dst" | awk '{print $1}')
        if [ "$existing" != "$src_sha" ]; then
            rm -f "$tmp"
            echo "build-stage0: refusing to overwrite $dst: it has sha256 $existing but the freshly built $name is $src_sha" >&2
            exit 1
        fi
        rm -f "$tmp"
    else
        mv -f "$tmp" "$dst"
    fi
    echo "build-stage0: installed $dst"
}

cd "$root_dir" || exit 1
zig build

if [ ! -f "$binary" ]; then
    echo "build-stage0: zig build did not produce $binary" >&2
    exit 1
fi
if [ ! -f "$qbe_binary" ]; then
    echo "build-stage0: zig build did not produce $qbe_binary; the pinned mylang cannot run without it" >&2
    exit 1
fi

sha=$(sha256sum "$binary" | awk '{print $1}')
cache_root=${MYLANG_STAGE0_CACHE:-$HOME/.cache/mylang/stage0}
artifact="$cache_root/$sha/mylang"
qbe_artifact="$cache_root/$sha/qbe"

install_artifact "$binary" "$artifact" "mylang"
install_artifact "$qbe_binary" "$qbe_artifact" "qbe"

echo "build-stage0: worktree binary sha256 $sha"
echo "build-stage0: pinned tool directory $cache_root/$sha"

if [ -f "$pin_file" ]; then
    pin_sha=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("sha256", ""))' "$pin_file" 2>/dev/null || true)
    if [ -n "$pin_sha" ] && [ "$pin_sha" != "$sha" ]; then
        echo "build-stage0: WARNING: selfhost/stage0-pin.json still records $pin_sha; run selfhost/tools/pin-stage0.sh to re-pin the new artifact" >&2
    fi
fi
